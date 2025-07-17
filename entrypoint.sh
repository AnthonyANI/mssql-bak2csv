#!/bin/bash

# Source the functions file
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/functions.sh"

# Make sure we start with a clean state
rm -f /tmp/cancel_export

setup_logging
setup_signal_handlers

# Parse command line arguments
BAK_FILE=""
TABLES=""
PREFIX=""
SUFFIX=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --bak-file)
            BAK_FILE="$2"
            shift 2
            ;;
        --tables)
            TABLES="$2"
            shift 2
            ;;
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        --suffix)
            SUFFIX="$2"
            shift 2
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# ====================================
# BAK file detection/verification
# ====================================

# Check if BAK file is provided, if not try to auto-detect
if [[ -z "$BAK_FILE" ]]; then
    echo "Looking for .bak files in mounted directory..."
    
    # Find all .bak files in the mounted directory
    BAK_FILES=()
    while IFS= read -r -d '' file; do
        BAK_FILES+=("$file")
    done < <(find /mnt/bak -maxdepth 1 -name "*.bak" -type f -print0)
    
    if [[ ${#BAK_FILES[@]} -eq 0 ]]; then
        echo "Error: No .bak files found"
        echo "Make sure you mounted a directory containing .bak files to /mnt/bak"
        show_usage
        exit 1
    elif [[ ${#BAK_FILES[@]} -eq 1 ]]; then
        CONTAINER_BAK_FILE="${BAK_FILES[0]}"
        BAK_FILENAME=$(basename "$CONTAINER_BAK_FILE")
        echo "Found BAK file: $BAK_FILENAME"
    else
        echo "Error: Multiple .bak files found:"
        for file in "${BAK_FILES[@]}"; do
            echo "  $(basename "$file")"
        done
        echo "Please specify which one to use with --bak-file FILENAME"
        show_usage
        exit 1
    fi
else
    # BAK file specified, construct container path
    BAK_FILENAME="$BAK_FILE"
    CONTAINER_BAK_FILE="/mnt/bak/$BAK_FILENAME"
fi

# Set CSV output path with appropriate fallback
CONTAINER_CSV_PATH=$(determine_output_dir)

# Ensure output path exists in container
mkdir -p "$CONTAINER_CSV_PATH"

# ====================================
# SQL Server startup
# ====================================

# Ensure log directory exists
mkdir -p "/var/opt/mssql/log"

echo "Starting SQL Server..."
# Start SQL Server in the background and redirect output to log file
/opt/mssql/bin/sqlservr > /var/opt/mssql/log/startup.log 2>&1 &
# Store PID for potential shutdown later
SQL_PID=$!

# Wait for SQL Server to be ready with spinner animation
echo -n "Waiting for SQL Server to start"
for i in {1..60}; do
    if sqlcmd -S localhost -U SA -P "$SA_PASSWORD" -Q "SELECT 1" > /dev/null 2>&1; then
        echo -e "\nSQL Server is ready!"
        break
    fi
    if [[ $i -eq 60 ]]; then
        echo -e "\nSQL Server failed to start within 60 seconds"
        exit 1
    fi
    echo -n "."
    sleep 1
done

# ====================================
# Main workflow
# ====================================

# Main execution
print_section "MSSQL BAK to CSV Converter" "="
echo "BAK file: $BAK_FILENAME"
echo "Tables to export: ${TABLES:-all}"
if [[ -n "$PREFIX" ]]; then
    echo "Filename prefix: $PREFIX"
fi
if [[ -n "$SUFFIX" ]]; then
    echo "Filename suffix: $SUFFIX"
fi
echo "Log file: $LOG_FILE"

# Verify BAK file exists in container
if [[ ! -f "$CONTAINER_BAK_FILE" ]]; then
    echo "Error: BAK file '$BAK_FILENAME' not found"
    echo "Make sure you mounted the directory containing your BAK file to /mnt/bak"
    exit 1
fi

# Copy BAK file to backup directory
echo "📁 Copying BAK file to backup directory..."
cp "$CONTAINER_BAK_FILE" /var/opt/mssql/backup/
INTERNAL_BAK_FILE="/var/opt/mssql/backup/$BAK_FILENAME"

# Get database name and restore
DB_NAME=$(get_database_name "$INTERNAL_BAK_FILE")
if [[ -z "$DB_NAME" ]]; then
    echo "❌ Failed to get database name from BAK file"
    exit 1
fi

print_section "Restoring Database" "-"
echo "🔄 Restoring database '$DB_NAME' from '$BAK_FILENAME'..."
if ! restore_database "$INTERNAL_BAK_FILE" "$DB_NAME"; then
    echo "❌ Failed to restore database"
    exit 1
fi
echo "✅ Database '$DB_NAME' restored successfully!"

print_section "Available Tables" "-"
CLEAN_TABLES=$(list_tables)

if [ $? -ne 0 ]; then
    echo "❌ Failed to list tables from databases."
    exit 1
fi

# Display tables with numbers for reference
echo "Tables in restored database:"
table_count=0
while IFS= read -r table_info; do
    table_count=$((table_count+1))
    echo "  $table_count. $table_info"
done <<< "$CLEAN_TABLES"
echo "Found $table_count tables"

# ====================================
# Export process
# ====================================

print_section "Exporting Tables" "-"
echo "🔄 Starting exports (press Ctrl+C to interrupt)..."
# Add empty lines for status display
echo ""  # Current table line
echo ""  # Progress line
echo ""  # Stats line

# Add a counter for progress tracking
total_tables=$(echo "$CLEAN_TABLES" | wc -l)
current_table=0
success_count=0
failed_count=0
start_time=$(date +%s)

while read -r table_info; do
    # Check if we received a signal to exit
    if [ -f "/tmp/cancel_export" ]; then
        echo -e "\nExport cancelled."
        break
    fi
    
    if [ -n "$table_info" ]; then
        # Extract database and table name
        db_name=$(echo "$table_info" | cut -d'.' -f1)
        table_name=$(echo "$table_info" | cut -d'.' -f2)
        
        if [ -n "$db_name" ] && [ -n "$table_name" ]; then
            # Update progress counter
            current_table=$((current_table+1))
            
            # Update display
            update_display "$current_table" "$total_tables" "$db_name" "$table_name" \
                         "$success_count" "$failed_count" "$start_time"
            
            # Export the table
            result=$(export_table_to_csv "$db_name" "$table_name" "$CONTAINER_CSV_PATH")
            status=$(echo "$result" | cut -d':' -f1)
            row_count=$(echo "$result" | cut -d':' -f2)
            
            # Update success/failure count
            if [ "$status" -eq 0 ]; then
                echo "✅ Exported ${db_name}.${table_name} ($row_count rows)" >> "$LOG_FILE"
                success_count=$((success_count+1))
            else
                echo "❌ Failed: ${db_name}.${table_name}" >> "$LOG_FILE"
                failed_count=$((failed_count+1))
            fi
        fi
    fi
done < <(echo "$CLEAN_TABLES")

echo ""

print_section "Export Complete" "-"
echo "✅ Exported $success_count tables successfully${failed_count:+, $failed_count tables failed}"
echo "📝 Log file saved to: $LOG_FILE"

exit 0