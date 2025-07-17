#!/bin/bash

# ====================================
# Logging and Display Functions
# ====================================

# Setup logging to file
setup_logging() {
    # Generate log filename with timestamp
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    LOG_FILE="/mnt/bak/mssql-bak2csv_${timestamp}.log"
    
    # Create a named pipe for tee
    PIPE=$(mktemp -u)
    mkfifo $PIPE
    
    # Start tee in background, reading from the pipe
    tee "$LOG_FILE" < $PIPE &
    TEE_PID=$!
    
    # Redirect stdout and stderr to the pipe
    exec > $PIPE 2>&1
    
    echo "MSSQL BAK to CSV Converter"
    date
    echo "---------------------------------------------"
}

# Track if we're currently exporting
EXPORTING=0

cleanup() {
    echo -e "\n\nCleaning up and exiting..."
    
    if [ $EXPORTING -eq 1 ]; then
        echo "Export cancelled by user signal."
        touch /tmp/cancel_export
    fi
    
    pkill -TERM sqlcmd 2>/dev/null
    sleep 1
    pkill -9 sqlcmd 2>/dev/null
    
    if [[ -n "$SQL_PID" ]]; then
        echo "Shutting down SQL Server..."
        kill -TERM "$SQL_PID" 2>/dev/null
        wait "$SQL_PID" 2>/dev/null
    fi
    
    exec >&- 2>&-
    wait $TEE_PID 2>/dev/null
    rm -f $PIPE
    
    exit 0
}

setup_signal_handlers() {
    trap cleanup SIGINT SIGTERM
}

# Function to output formatted section headers
print_section() {
    local title="$1"
    local char="${2:-=}"
    local width=50
    
    echo ""
    echo "${char}$(printf "%${width}s" | tr " " "$char")"
    echo "$char $title"
    echo "${char}$(printf "%${width}s" | tr " " "$char")"
}

# Function to update display without using tput
update_display() {
    local current_table="$1"
    local total_tables="$2"
    local db_name="$3"
    local table_name="$4"
    local success_count="$5"
    local failed_count="$6"
    local start_time="$7"
    
    # Get terminal width, default to 80 if not available
    local term_width=${COLUMNS:-80}
    
    # Clear the previous lines more robustly
    if [ "$current_table" -gt 1 ]; then
        # Move up and clear multiple lines to handle line wrapping
        printf "\033[2K\033[1A\033[2K\033[1A\033[2K\033[1A\033[2K"  # Clear current + 3 lines above
    fi
    
    # Update current file display with intelligent truncation
    local output_file="${PREFIX}${table_name}${SUFFIX}.csv"
    local current_display="🔄 ${table_name} → ${output_file}"
    
    # Truncate if longer than terminal width - 2 (for safety margin)
    if [ ${#current_display} -gt $((term_width - 2)) ]; then
        # Calculate available space
        local max_len=$((term_width - 10))
        
        # Truncate both table name and output file if needed
        if [ ${#table_name} -gt $max_len ]; then
            local truncated_name="${table_name:0:$((max_len/2))}...${table_name: -$((max_len/2))}"
            current_display="🔄 ${truncated_name} → ${output_file}"
            
            # If still too long, truncate the output file name too
            if [ ${#current_display} -gt $((term_width - 2)) ] && [ ${#output_file} -gt $((max_len/2)) ]; then
                local truncated_output="${output_file:0:$((max_len/4))}...${output_file: -$((max_len/4))}"
                current_display="🔄 ${truncated_name} → ${truncated_output}"
            fi
        fi
    fi
    
    printf "%s\n" "$current_display"
    
    # Calculate elapsed time and estimate remaining time using bash arithmetic
    local current_time
    current_time=$(date +%s)
    local elapsed=$((current_time - start_time))
    local time_estimate=""
    
    if [ $current_table -gt 1 ]; then
        local avg_time_per_table=$(( elapsed * 100 / current_table ))
        local est_remaining=$(( avg_time_per_table * (total_tables - current_table) / 100 ))
        local remaining_min=$((est_remaining / 60))
        local remaining_sec=$((est_remaining % 60))
        time_estimate=" (est. ${remaining_min}m ${remaining_sec}s remaining)"
    fi
    
    # Update progress bar
    local progress=$((current_table * 100 / total_tables))
    local bar_width=30
    local completed_width=$((bar_width * progress / 100))
    local remaining_width=$((bar_width - completed_width))
    
    printf "📊 Progress: ["
    printf "%${completed_width}s" | tr ' ' '#'
    printf "%${remaining_width}s" | tr ' ' '.'
    printf "] %d%% (%d/%d tables)%s\n" "$progress" "$current_table" "$total_tables" "$time_estimate"
    
    # Update statistics
    printf "📈 Stats: ✅ %d exported, ❌ %d failed\n" "$success_count" "$failed_count"
}

# ====================================
# Filesystem Functions
# ====================================

# Determine the best output directory
determine_output_dir() {
    if mountpoint -q /mnt/csv 2>/dev/null; then
        echo "/mnt/csv"
    else
        mkdir -p "/mnt/bak/output"
        echo "/mnt/bak/output"
    fi
}

# ====================================
# SQL Server Functions
# ====================================

# Function to get database name from BAK file
get_database_name() {
    local bak_file="$1"
    local db_name
    db_name=$(sqlcmd -S localhost -U SA -P "$SA_PASSWORD" -Q "RESTORE FILELISTONLY FROM DISK = '$bak_file'" -h -1 | head -1 | awk '{print $1}')
    echo "$db_name"
}

# Function to restore database
restore_database() {
    local bak_file="$1"
    local db_name="$2"
    
    echo "Restoring database '$db_name' from '$bak_file'..."
    
    # Get logical file names
    local logical_files
    logical_files=$(sqlcmd -S localhost -U SA -P "$SA_PASSWORD" -Q "RESTORE FILELISTONLY FROM DISK = '$bak_file'" -h -1)
    local data_file
    data_file=$(echo "$logical_files" | grep -E '\s+D\s+' | head -1 | awk '{print $1}')
    local log_file
    log_file=$(echo "$logical_files" | grep -E '\s+L\s+' | head -1 | awk '{print $1}')
    
    # Restore with MOVE options
    if sqlcmd -S localhost -U SA -P "$SA_PASSWORD" -Q "
    RESTORE DATABASE [$db_name] 
    FROM DISK = '$bak_file' 
    WITH MOVE '$data_file' TO '/var/opt/mssql/data/${db_name}.mdf',
         MOVE '$log_file' TO '/var/opt/mssql/data/${db_name}.ldf',
         REPLACE"; then
        echo "Database '$db_name' restored successfully!"
        return 0
    else
        echo "Failed to restore database '$db_name'"
        return 1
    fi
}

# Function to list all tables in all user databases
list_tables() {
    # Use a much simpler, more compatible query that works across SQL Server versions
    local tables
    tables=$(sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "
    SET NOCOUNT ON;
    DECLARE @db_name NVARCHAR(128);
    SELECT @db_name = name FROM sys.databases 
    WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb');
    
    DECLARE @sql NVARCHAR(MAX);
    SET @sql = 'USE [' + @db_name + ']; 
    SELECT @db_name + ''.'' + TABLE_NAME 
    FROM INFORMATION_SCHEMA.TABLES 
    WHERE TABLE_TYPE = ''BASE TABLE'' 
    ORDER BY TABLE_NAME;';
    
    EXEC sp_executesql @sql, N'@db_name NVARCHAR(128)', @db_name;
    " -h-1 -s"," -W -r1)

    # Check if the query succeeded
    if [ $? -ne 0 ]; then
        echo "Error: Failed to list tables."
        return 1
    fi

    # Clean up the output
    local clean_tables
    clean_tables=$(echo "$tables" | grep -v "^$" | grep -v "^Msg" | grep -v "^Invalid" | grep -v "^Sqlcmd:" | grep -v "^Changed database context")

    if [ -z "$clean_tables" ]; then
        echo "No tables found in restored database."
        return 1
    fi

    echo "$clean_tables"
    return 0
}

# ====================================
# Export Functions
# ====================================

# Function to export table to CSV
export_table_to_csv() {
    EXPORTING=1
    local database="$1"
    local table="$2"
    local output_path="$3"
    local output_file="${output_path}/${PREFIX}${table}${SUFFIX}.csv"
    
    # First verify table exists and get its proper schema
    local check_query="
    SELECT SCHEMA_NAME(schema_id) + '.' + name 
    FROM sys.tables 
    WHERE LOWER(name) = LOWER('$(echo "$table" | tr -d '[]')') 
    OR OBJECT_ID(N'$(echo "$table" | tr -d '[]')') IS NOT NULL"
    
    local table_check
    table_check=$(sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -d "$database" -Q "$check_query" -h-1 -W)
    
    # Extract just the table name without any error messages
    local found_table
    found_table=$(echo "$table_check" | grep -v "^Msg" | grep -v "^$" | head -1 | tr -d '[:space:]')
    
    if [ -z "$found_table" ]; then
        # Table not found, try with dbo schema explicitly
        local dbo_check="
        SELECT SCHEMA_NAME(schema_id) + '.' + name 
        FROM sys.tables 
        WHERE LOWER(name) = LOWER('$(echo "$table" | tr -d '[]')')"
        
        found_table=$(sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -d "$database" -Q "$dbo_check" -h-1 -W | 
                      grep -v "^Msg" | grep -v "^$" | head -1 | tr -d '[:space:]')
        
        if [ -z "$found_table" ]; then
            # Still not found, return error
            echo "1:0"
            return 1
        fi
    fi
    
    # Parse schema and table name
    local schema="dbo"
    local table_name="$table"
    
    if [[ "$found_table" == *"."* ]]; then
        schema=$(echo "$found_table" | cut -d. -f1)
        table_name=$(echo "$found_table" | cut -d. -f2)
    fi
    
    # Export directly to CSV with headers
    sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -d "$database" -Q "
    SET NOCOUNT ON;
    
    -- Get column names for header
    DECLARE @columns NVARCHAR(MAX) = '';
    SELECT @columns = @columns + COLUMN_NAME + ',' 
    FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = '$table_name' AND TABLE_SCHEMA = '$schema'
    ORDER BY ORDINAL_POSITION;
    
    -- Remove trailing comma
    IF LEN(@columns) > 0
        SET @columns = LEFT(@columns, LEN(@columns) - 1);
    ELSE
        SET @columns = 'No_columns_found';
    
    -- Output header
    PRINT @columns;
    
    -- Output data
    SELECT * FROM [$schema].[$table_name];
    " -o "$output_file" -h-1 -s"," -W -r1 2>/dev/null
    
    local status=$?
    local row_count=0
    
    # Check for errors in the output file
    if [ -f "$output_file" ]; then
        if grep -q "Invalid object name" "$output_file" || grep -q "Msg [0-9]*, Level [0-9]*, State" "$output_file"; then
            status=1
        else
            # Count lines only if no error messages found
            row_count=$(($(wc -l < "$output_file") - 1))
            if [ $row_count -lt 0 ]; then
                row_count=0
            fi
        fi
    else
        # File doesn't exist
        status=1
    fi
    
    # Return both status and row count
    EXPORTING=0
    echo "$status:$row_count"
}

# Function to generate filename with collision detection
generate_filename() {
    local database="$1"
    local schema="$2"
    local table="$3"
    local all_tables="$4"
    
    # Start with simple table name
    local base_filename="$table"
    
    # Check for naming collisions
    if echo "$all_tables" | grep -c "\.$table$" -gt 1; then
        # Add schema if it resolves the collision
        if echo "$all_tables" | grep -c "\.$schema\.$table$" -gt 1; then
            base_filename="${database}_${schema}_${table}"
        else
            base_filename="${schema}_${table}"
        fi
    fi
    
    echo "$base_filename"
}

# ====================================
# Usage/Help Functions
# ====================================

# Function to display usage
show_usage() {
    echo "Usage: docker run -v /host/path/to/bak:/mnt/bak -v /host/path/to/output:/mnt/csv mssql-bak2csv [options]"
    echo ""
    echo "Options:"
    echo "  --bak-file FILENAME       Name of the BAK file in the mounted directory (optional if only one .bak file exists)"
    echo "  --tables TABLE1,TABLE2    Comma-separated list of tables to export (default: all)"
    echo "                           Format: [database.]table_name"
    echo "  --prefix PREFIX           Prefix to add to CSV filenames (e.g., 'ABC1_AB_')"
    echo "  --suffix SUFFIX           Suffix to add to CSV filenames (e.g., '_backup')"
    echo "  --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  docker run -v /data:/mnt/bak -v /data/output:/mnt/csv mssql-bak2csv"
    echo "  docker run -v /data:/mnt/bak -v /data/output:/mnt/csv mssql-bak2csv --bak-file database.bak"
    echo "  docker run -v /data:/mnt/bak -v /data/output:/mnt/csv mssql-bak2csv --bak-file database.bak --tables table1,table2"
    echo "  docker run -v /data:/mnt/bak -v /data/output:/mnt/csv mssql-bak2csv --prefix 'ABC1_AB_' --suffix '_backup'"
}
