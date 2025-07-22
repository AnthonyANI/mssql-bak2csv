#!/bin/bash

# Process and signal handling functions

export EXPORT_RUNNING=0

cleanup_and_exit() {
    local exit_code=${1:-0}

    reset_display
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
    exit "${exit_code}"
}

setup_signal_handlers() {
    rm -f /tmp/cancel_export
    trap 'cleanup_and_exit 0' SIGINT SIGTERM
}
