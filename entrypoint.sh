#!/bin/bash

SCRIPT_DIR="$(dirname "$0")"

source "${SCRIPT_DIR}/logging.sh"
source "${SCRIPT_DIR}/display.sh"
source "${SCRIPT_DIR}/database.sh"
source "${SCRIPT_DIR}/tables.sh"
source "${SCRIPT_DIR}/export.sh"
source "${SCRIPT_DIR}/files.sh"

parse_arguments() {
    export BAK_FILE=""
    export TABLES=""
    export PREFIX=""
    export SUFFIX=""

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
            display "Unknown option: $1"
            show_usage
            exit 1
            ;;
        esac
    done
}

main() {
    setup_logging
    setup_signal_handlers
    parse_arguments "$@"

    if ! find_bak_file; then
        exit 1
    fi

    print_section "SQL Server" "-"
    if ! start_sql_server; then
        display "Failed to start SQL Server"
        exit 1
    fi

    local DB_NAME
    local INTERNAL_BAK_FILE
    local OUTPUT_PATH

    DB_NAME=$(get_database_name "$CONTAINER_BAK_FILE")
    if [ -z "$DB_NAME" ]; then
        display "Failed to get database name from BAK file"
        exit 1
    fi

    INTERNAL_BAK_FILE=$(prepare_bak_file "$CONTAINER_BAK_FILE")
    if [ -z "$INTERNAL_BAK_FILE" ] || [ ! -f "$INTERNAL_BAK_FILE" ]; then
        display "Failed to prepare BAK file for SQL Server"
        exit 1
    fi

    if ! process_database_restore "$INTERNAL_BAK_FILE" "$DB_NAME"; then
        exit 1
    fi

    OUTPUT_PATH=$(determine_output_dir)
    if ! process_database_export "$DB_NAME" "$OUTPUT_PATH"; then
        exit 1
    fi

    display "📝 Log file: $LOG_FILE"
}

main "$@"
