#!/bin/bash

CURSOR_UP="\033[1A"
CURSOR_DOWN="\033[1B"
CLEAR_LINE="\033[2K"
CLEAR_LINE_TO_END="\033[K"
CARRIAGE_RETURN="\r"

# Display and UI functions

display() {
    local skip_log="false"
    local echo_flags=()
    local message=""

    # Check for --nolog as last argument
    if [[ "$#" -gt 0 && "${!#}" == "--nolog" ]]; then
        skip_log="true"
        set -- "${@:1:$(($# - 1))}" # Remove last argument
    fi

    # Process echo flags
    while [[ "$#" -gt 0 && "$1" =~ ^-[a-zA-Z]+$ ]]; do
        echo_flags+=("$1")
        shift
    done

    # Remaining arguments form the message
    if [[ "$#" -gt 0 ]]; then
        message="$*"
    fi

    # Handle echo flags properly
    if [[ "${#echo_flags[@]}" -gt 0 ]]; then
        echo "${echo_flags[@]}" "$message" >&2
    else
        echo "$message" >&2
    fi

    # Log to file unless skip_log is true
    if [ "$skip_log" != "true" ]; then
        log "$message"
    fi
}

print_section() {
    local title="$1"
    local char="${2:-=}"
    local width=50

    display ""
    display "${char}$(printf "%${width}s" | tr " " "$char")"
    display "$title"
    display "${char}$(printf "%${width}s" | tr " " "$char")"
}

DISPLAY_LINES=3
DISPLAY_INITIALIZED=0

reset_display() {
    local reposition_only="${1:-false}"

    if [ $DISPLAY_INITIALIZED -eq 1 ]; then
        for ((i = 0; i < DISPLAY_LINES; i++)); do
            if [ "$reposition_only" != "true" ]; then
                echo -ne "$CURSOR_UP$CLEAR_LINE$CARRIAGE_RETURN"
            else
                echo -ne "$CURSOR_UP$CARRIAGE_RETURN"
            fi
        done

        DISPLAY_INITIALIZED=0
    fi
}

update_display() {
    local current_table="$1"
    local total_tables="$2"
    local table_name="$3"
    local success_count="$4"
    local failed_count="$5"
    local start_time="$6"

    reset_display true

    local table_display
    local progress_display
    local stats_display

    table_display=$(get_table_status_text "$table_name" "${PREFIX}${table_name}${SUFFIX}.csv")
    progress_display=$(get_progress_bar_text "$current_table" "$total_tables" "$start_time")
    stats_display=$(printf '📈 Stats: ✅ %d exported, ❌ %d failed' "$success_count" "$failed_count")

    printf "%s$CLEAR_LINE_TO_END\n" "$table_display"
    printf "%s$CLEAR_LINE_TO_END\n" "$progress_display"
    printf "%s$CLEAR_LINE_TO_END\n" "$stats_display"

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
        local truncated_name="${table_name:0:$((max_len / 2))}...${table_name: -$((max_len / 2))}"
        current_display="🔄 ${truncated_name} → ${output_file}"

        if [ ${#current_display} -gt $((term_width - 2)) ] && [ ${#output_file} -gt $((max_len / 2)) ]; then
            local truncated_output="${output_file:0:$((max_len / 4))}...${output_file: -$((max_len / 4))}"
            current_display="🔄 ${truncated_name} → ${truncated_output}"
        fi
    fi

    echo "$current_display"
}

get_progress_bar_text() {
    local processed="$1"
    local total="$2"
    local start_time="$3"

    local progress=0
    if [ "$total" -gt 0 ]; then
        progress=$((processed * 100 / total))
    fi

    local bar_width=30
    local completed_width=$((bar_width * progress / 100))
    local remaining_width=$((bar_width - completed_width))

    local time_estimate=""
    if [ "$processed" -gt 0 ]; then
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local avg_time_per_table=$((elapsed * 100 / processed))
        local est_remaining=$((avg_time_per_table * (total - processed) / 100))
        local remaining_min=$((est_remaining / 60))
        local remaining_sec=$((est_remaining % 60))

        time_estimate=" (est. ${remaining_min}m ${remaining_sec}s remaining)"
    fi

    echo "📊 Progress: [$(printf '%*s' "$completed_width" "" | tr ' ' '#')$(printf '%*s' "$remaining_width" "" | tr ' ' '.')] $progress% ($processed/$total tables)$time_estimate"
}
