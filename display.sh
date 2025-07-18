#!/bin/bash

# Define terminal control sequences
CURSOR_UP="\033[1A"
CLEAR_LINE="\033[2K"
CARRIAGE_RETURN="\r"

# Display and UI functions
println() {
    local message="$1"
    local skip_log="${2:-false}"
    
    # Print to console (via stderr to avoid mangling return values)
    echo "$message" >&2

    # Log to file unless skip_log is true
    if [ "$skip_log" != "true" ]; then
        logln "$message"
    fi
}

print_section() {
    local title="$1"
    local char="${2:-=}"
    local width=50
    
    println ""
    println "${char}$(printf "%${width}s" | tr " " "$char")"
    println "$title"
    println "${char}$(printf "%${width}s" | tr " " "$char")"
}

# Number of lines used in display updates
DISPLAY_LINES=3
DISPLAY_INITIALIZED=0

# Helper function to clear and reposition cursor for display updates
clear_previous_output() {
    for ((i=0; i<DISPLAY_LINES; i++)); do
        echo -ne "$CURSOR_UP$CARRIAGE_RETURN$CLEAR_LINE"
    done
    echo -ne "$CARRIAGE_RETURN"
}

update_display() {
    local current_table="$1"
    local total_tables="$2"
    local table_name="$3"
    local success_count="$4"
    local failed_count="$5"
    local start_time="$6"
    
    if [ $DISPLAY_INITIALIZED -eq 1 ]; then
        clear_previous_output
    fi
    
    local table_display
    local progress_display
    local stats_display
    
    table_display=$(get_table_status_text "$table_name" "${PREFIX}${table_name}${SUFFIX}.csv")
    progress_display=$(get_progress_bar_text "$current_table" "$total_tables" "$start_time")
    stats_display=$(printf '📈 Stats: ✅ %d exported, ❌ %d failed' "$success_count" "$failed_count")
    
    printf '%s\n' "$table_display"
    printf '%s\n' "$progress_display"
    printf '%s\n' "$stats_display"
    
    DISPLAY_INITIALIZED=1
}

get_table_status_text() {
    local table_name="$1"
    local output_file="$2"
    local term_width
    term_width=$(tput cols 2>/dev/null || echo 80)
    local current_display="🔄 ${table_name} → ${output_file}"
    
    if [ ${#current_display} -le $((term_width - 2)) ]; then
        echo "$current_display"
        return
    fi
    
    local max_len=$((term_width - 10))
    
    if [ ${#table_name} -gt $max_len ]; then
        local truncated_name="${table_name:0:$((max_len/2))}...${table_name: -$((max_len/2))}"
        current_display="🔄 ${truncated_name} → ${output_file}"
        
        if [ ${#current_display} -gt $((term_width - 2)) ] && [ ${#output_file} -gt $((max_len/2)) ]; then
            local truncated_output="${output_file:0:$((max_len/4))}...${output_file: -$((max_len/4))}"
            current_display="🔄 ${truncated_name} → ${truncated_output}"
        fi
    fi
    
    echo "$current_display"
}

get_progress_bar_text() {
    local current="$1"
    local total="$2"
    local start_time="$3"
    
    local progress=$((current * 100 / total))
    
    local bar_width=30
    local completed_width=$((bar_width * progress / 100))
    local remaining_width=$((bar_width - completed_width))
    
    local time_estimate=""
    if [ "$current" -gt 1 ]; then
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local avg_time_per_table=$(( elapsed * 100 / current ))
        local est_remaining=$(( avg_time_per_table * (total - current) / 100 ))
        local remaining_min=$((est_remaining / 60))
        local remaining_sec=$((est_remaining % 60))
        
        time_estimate=" (est. ${remaining_min}m ${remaining_sec}s remaining)"
    fi
    
    echo "📊 Progress: [$(printf '%*s' "$completed_width" "" | tr ' ' '#')$(printf '%*s' "$remaining_width" "" | tr ' ' '.')] $progress% ($current/$total tables)$time_estimate"
}

count_and_display_tables() {
    local clean_tables="$1"
    
    local table_count=0
    while IFS= read -r table_info; do
        table_count=$((table_count+1))
        println "  $table_count. $table_info"
    done <<< "$clean_tables"
}

show_usage() {
    println "Usage: docker run -v /host/path/to/bak:/mnt/bak -v /host/path/to/output:/mnt/csv mssql-bak2csv [options]" true
    println "" true
    println "Options:" true
    println "  --bak-file FILENAME       Name of the BAK file in the mounted directory (optional if only one .bak file exists)" true
    println "  --tables TABLE1,TABLE2    Comma-separated list of tables to export (default: all)" true
    println "                           Format: [database.]table_name" true
    println "  --prefix PREFIX           Prefix to add to CSV filenames (e.g., 'ABC1_AB_')" true
    println "  --suffix SUFFIX           Suffix to add to CSV filenames (e.g., '_backup')" true
    println "  --help                    Show this help message" true
    println "" true
    println "Examples:" true
    println "  docker run -v /data:/mnt/bak -v /data/output:/mnt/csv mssql-bak2csv" true
    println "  docker run -v /data:/mnt/bak -v /data/output:/mnt/csv mssql-bak2csv --bak-file database.bak" true
    println "  docker run -v /data:/mnt/bak -v /data/output:/mnt/csv mssql-bak2csv --bak-file database.bak --tables table1,table2" true
    println "  docker run -v /data:/mnt/bak -v /data/output:/mnt/csv mssql-bak2csv --prefix 'ABC1_AB_' --suffix '_backup'" true
}
