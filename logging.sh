#!/bin/bash

# Logging and signal handling functions

export LOG_BUFFER=""
export LOG_BUFFER_SIZE=0
export MAX_BUFFER_SIZE=100  # Number of lines before flushing
export LOGGING_INITIALIZED=0

setup_logging() {
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    export LOG_FILE="/mnt/bak/mssql-bak2csv_${timestamp}.log"
    
    touch "$LOG_FILE"
    
    display "============================================="
    display "MSSQL BAK to CSV Converter"
    display "$(date)"
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
        echo -n "$LOG_BUFFER" >> "$LOG_FILE"
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
    
    # Use printf to correctly interpret escape sequences
    printf -v escaped_message "%b" "$message"
    LOG_BUFFER="${LOG_BUFFER}${escaped_message}"$'\n'
    LOG_BUFFER_SIZE=$((LOG_BUFFER_SIZE + 1))
    
    if [ "$LOG_BUFFER_SIZE" -ge "$MAX_BUFFER_SIZE" ]; then
        flush_log_buffer
    fi
}

export EXPORT_RUNNING=0

cleanup() {
    display ""
    display ""
    display "⏹️ Cleaning up and exiting..."
    
    if [ $EXPORT_RUNNING -eq 1 ]; then
        display "Export cancelled by user signal."
        touch /tmp/cancel_export
    fi
    
    if [[ -n "$FLUSH_PID" ]]; then
        kill "$FLUSH_PID" 2>/dev/null
    fi
    
    pkill -TERM sqlcmd 2>/dev/null
    sleep 1
    pkill -9 sqlcmd 2>/dev/null
    
    if [[ -n "$SQL_PID" ]]; then
        display "Shutting down SQL Server..."
        kill -TERM "$SQL_PID" 2>/dev/null
        wait "$SQL_PID" 2>/dev/null
    fi
    
    flush_log_buffer
    exit 0
}

setup_signal_handlers() {
    rm -f /tmp/cancel_export
    trap cleanup SIGINT SIGTERM
}
