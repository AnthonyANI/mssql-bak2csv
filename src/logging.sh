#!/bin/bash

# Logging functions

export LOG_BUFFER=""
export LOG_BUFFER_SIZE=0
export MAX_BUFFER_SIZE=100 # Number of lines before flushing
export LOGGING_INITIALIZED=0

setup_logging() {
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    export LOG_FILE="/mnt/bak/mssql-bak2csv_${timestamp}.log"

    touch "$LOG_FILE"

    display "============================================="
    display "MSSQL BAK to CSV Converter"
    display "$(date)"
    display "📝 Log file: $(basename "$LOG_FILE")"
    display "============================================="

    start_flush_timer

    LOGGING_INITIALIZED=1
}

log() {
    local message="$1"

    if [ "$LOGGING_INITIALIZED" -eq 1 ]; then
        add_to_log_buffer "$message"
    fi
}

flush_log_buffer() {
    if [[ -n "$LOG_BUFFER" && -n "$LOG_FILE" ]]; then
        echo -ne "$LOG_BUFFER" >>"$LOG_FILE"
        LOG_BUFFER=""
        LOG_BUFFER_SIZE=0
    fi
}

flush_logs_periodically() {
    while true; do
        sleep 5
        flush_log_buffer
    done
}

start_flush_timer() {
    flush_logs_periodically &
    export FLUSH_PID=$!
}

add_to_log_buffer() {
    local message="$1"

    LOG_BUFFER="${LOG_BUFFER}${message}"$'\n'
    LOG_BUFFER_SIZE=$((LOG_BUFFER_SIZE + 1))

    if [ "$LOG_BUFFER_SIZE" -ge "$MAX_BUFFER_SIZE" ]; then
        flush_log_buffer
    fi
}
