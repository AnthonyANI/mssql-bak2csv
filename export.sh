#!/bin/bash

# CSV export functionality

export_table_to_csv() {
    EXPORT_RUNNING=1
    local database="$1"
    local table="$2"
    local output_path="$3"
    local output_file="${output_path}/${PREFIX}${table}${SUFFIX}.csv"
    
    local table_info
    if ! table_info=$(get_table_schema_and_name "$database" "$table"); then
        EXPORT_RUNNING=0
        echo "1:0"
        return 1
    fi
    
    local schema
    local table_name
    schema=$(echo "$table_info" | cut -d. -f1)
    table_name=$(echo "$table_info" | cut -d. -f2)
    
    execute_sql_query "$database" "
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
    
    if [ -f "$output_file" ]; then
        if grep -q "Invalid object name\|Msg [0-9]*, Level [0-9]*, State" "$output_file"; then
            status=1
        else
            row_count=$(($(wc -l < "$output_file") - 1))
            [ $row_count -lt 0 ] && row_count=0
        fi
    else
        status=1
    fi
    
    EXPORT_RUNNING=0
    echo "$status:$row_count"
}

export_tables() {
    local db_name="$1"
    local tables="$2"
    local output_path="$3"
    
    print_section "Export" "-"
    println "🔄 Starting exports (press Ctrl+C to interrupt)"
    echo ""
    
    local total_tables
    local current_table=0
    local success_count=0
    local failed_count=0
    local start_time
    
    total_tables=$(echo "$tables" | wc -l)
    start_time=$(date +%s)

    DISPLAY_INITIALIZED=0
    
    while read -r table_info; do
        if [ -f "/tmp/cancel_export" ]; then
            println "\nExport cancelled."
            break
        fi
        
        if [ -n "$table_info" ]; then
            local table_db
            local table_name
            
            table_db=$(echo "$table_info" | cut -d'.' -f1)
            table_name=$(echo "$table_info" | cut -d'.' -f2)
            
            if [ -n "$table_db" ] && [ -n "$table_name" ]; then
                current_table=$((current_table+1))
                
                update_display "$current_table" "$total_tables" "$table_name" \
                              "$success_count" "$failed_count" "$start_time"
                
                local result
                local status
                local row_count
                
                result=$(export_table_to_csv "$table_db" "$table_name" "$output_path")
                status=$(echo "$result" | cut -d':' -f1)
                row_count=$(echo "$result" | cut -d':' -f2)
                
                if [ "$status" -eq 0 ]; then
                    logln "✅ Exported ${table_db}.${table_name} ($row_count rows)"
                    success_count=$((success_count+1))
                else
                    logln "❌ Failed: ${table_db}.${table_name}"
                    failed_count=$((failed_count+1))
                fi
            fi
        fi
    done < <(echo "$tables")
    
    if [ $DISPLAY_INITIALIZED -eq 1 ]; then
        clear_previous_output
    fi
    
    echo ""
    print_section "Export Complete" "-"
    println "✅ Exported $success_count tables successfully${failed_count:+, ❌ $failed_count tables failed}"
}

process_database_export() {
    local db_name="$1"
    local output_path="$2"
    
    print_section "Available Tables" "-"
    local clean_tables
    if ! clean_tables=$(list_tables); then
        println "❌ Failed to list tables from database."
        return 1
    fi
    
    count_and_display_tables "$clean_tables"
    export_tables "$db_name" "$clean_tables" "$output_path"
    return $?
}
