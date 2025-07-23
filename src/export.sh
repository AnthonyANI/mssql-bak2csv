#!/bin/bash

# CSV export functionality

write_csv_header() {
    local output_file="$1"
    shift
    local columns=("$@")

    IFS=','
    echo "${columns[*]}" >"$output_file"
}

truncate_error_msg() {
    local msg="$1"
    if [ ${#msg} -gt 200 ]; then
        echo "${msg:0:200}..."
    else
        echo "$msg"
    fi
}

EXPORT_RESULT_DELIMETER=$'\x1F'

export_table_to_csv() {
    EXPORT_RUNNING=1
    local database="$1"
    local table="$2"
    local output_path="$3"
    local output_file="${output_path}/${PREFIX}${table}${SUFFIX}.csv"
    local error_msg=""

    local table_info
    if ! table_info=$(get_table_schema_and_name "$database" "$table"); then
        EXPORT_RUNNING=0
        echo "1:0:${output_file}:Failed to get table schema and name"
        return 1
    fi

    local schema
    local table_name
    schema=$(echo "$table_info" | cut -d. -f1)
    table_name=$(echo "$table_info" | cut -d. -f2)

    local column_info
    mapfile -t column_info < <(get_column_info "$database" "$table_name" "$schema")

    if [ ${#column_info[@]} -eq 0 ]; then
        EXPORT_RUNNING=0
        echo "1:0:${output_file}:No columns found for table"
        return 1
    fi

    # Extract column names for header
    local columns=()
    for info in "${column_info[@]}"; do
        columns+=("$(echo "$info" | cut -d'|' -f1)")
    done

    write_csv_header "$output_file" "${columns[@]}"

    local data_query
    data_query=$(build_data_query "$schema" "$table_name" "${column_info[@]}")

    # Export data to file
    local error_output
    error_output=$(execute_sql_query "$database" "$data_query" -s"," -r1 2>&1 1>>"$output_file")

    local status=$?
    local row_count=0

    if [ ! -f "$output_file" ]; then
        status=1
        error_msg=$(truncate_error_msg "${error_output:-Failed to create output file (unknown error)}")
    elif [ -n "$error_output" ]; then
        status=1
        error_msg=$(truncate_error_msg "$error_output")
    elif [ "$(wc -l <"$output_file")" -ge 1 ]; then
        row_count=$(($(wc -l <"$output_file") - 1))
        [ $row_count -lt 0 ] && row_count=0
    else
        status=1
        error_msg="Empty or invalid CSV file"
    fi

    EXPORT_RUNNING=0
    echo "$status${EXPORT_RESULT_DELIMETER}$row_count${EXPORT_RESULT_DELIMETER}$output_file${EXPORT_RESULT_DELIMETER}$error_msg"
}

filter_tables_by_user_selection() {
    local all_tables="$1"
    local user_tables="$2"

    if [ -z "$user_tables" ]; then
        # Return all tables if no filter is specified
        echo "$all_tables"
        return
    fi

    local filtered_tables=""
    local IFS=','
    read -ra selected_tables <<<"$user_tables"

    local grep_pattern=""
    for selected in "${selected_tables[@]}"; do
        local trimmed_selected
        trimmed_selected=$(echo "$selected" | xargs)
        if [ -n "$grep_pattern" ]; then
            grep_pattern="${grep_pattern}|"
        fi
        grep_pattern="${grep_pattern}(^|\.)\b${trimmed_selected}\b($|\.)"
    done

    local matching_tables
    matching_tables=$(echo "$all_tables" | grep -E "$grep_pattern" || true)

    if [ -n "$matching_tables" ]; then
        filtered_tables="$matching_tables"
    fi

    for selected in "${selected_tables[@]}"; do
        local trimmed_selected
        trimmed_selected=$(echo "$selected" | xargs)
        if ! echo "$matching_tables" | grep -qE "(^|\.)\b${trimmed_selected}\b($|\.)"; then
            display "⚠️  Warning: Table '$trimmed_selected' not found"
        fi
    done

    if [ -z "$filtered_tables" ]; then
        display "❌ Error: None of the specified tables were found"
        return 1
    fi

    echo "$filtered_tables"
}

export_tables() {
    local db_name="$1"
    local tables="$2"
    local output_path="$3"

    print_section "Export" "-"
    display "🔄 Starting exports (press Ctrl+C to cancel)"
    echo ""

    local total_tables
    local current_table=0
    local success_count=0
    local failed_count=0
    local start_time

    total_tables=$(echo "$tables" | wc -l)
    start_time=$(date +%s)

    DISPLAY_INITIALIZED=0

    update_display 0 "$total_tables" "" "$success_count" "$failed_count" "$start_time"

    while read -r table_info; do
        if [ -f "/tmp/cancel_export" ]; then
            display "\nExport cancelled."
            break
        fi

        if [ -n "$table_info" ]; then
            local table_db
            local table_name

            table_db=$(echo "$table_info" | cut -d'.' -f1)
            table_name=$(echo "$table_info" | cut -d'.' -f2)

            if [ -n "$table_db" ] && [ -n "$table_name" ]; then
                current_table=$((current_table + 1))

                update_display $((success_count + failed_count)) "$total_tables" "$table_name" \
                    "$success_count" "$failed_count" "$start_time"

                local result
                local status
                local row_count
                local output_file
                local error_msg

                result=$(export_table_to_csv "$table_db" "$table_name" "$output_path")
                IFS="$EXPORT_RESULT_DELIMETER" read -r -d '' status row_count output_file error_msg <<<"$result"

                if [ "$status" -eq 0 ]; then
                    log "✅ Exported ${table_db}.${table_name} as $(basename "$output_file") ($row_count rows)"
                    success_count=$((success_count + 1))
                else
                    log "❌ Failed: ${table_db}.${table_name}${error_msg:+ - $error_msg}"
                    failed_count=$((failed_count + 1))
                fi

                update_display $((success_count + failed_count)) "$total_tables" "$table_name" \
                    "$success_count" "$failed_count" "$start_time"
            fi
        fi
    done < <(echo "$tables")

    reset_display
    display "✅ Exported $success_count tables successfully${failed_count:+, ❌ $failed_count tables failed}"
}

process_database_export() {
    local db_name="$1"
    local output_path="$2"

    print_section "Available Tables" "-"
    local clean_tables
    if ! clean_tables=$(list_tables); then
        display "❌ Failed to list tables from database."
        return 1
    fi

    count_and_display_tables "$clean_tables"

    local export_tables="$clean_tables"
    if [ -n "$TABLES" ]; then
        print_section "Selected Tables" "-"
        display "🔍 Filtering tables based on user selection: $TABLES"
        display ""

        if ! export_tables=$(filter_tables_by_user_selection "$clean_tables" "$TABLES"); then
            return 1
        fi

        display ""
        display "Selected tables for export:"
        count_and_display_tables "$export_tables"
    fi

    export_tables "$db_name" "$export_tables" "$output_path"
    return $?
}
