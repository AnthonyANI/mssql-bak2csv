#!/bin/bash

SCRIPT_DIR="$(dirname "$0")"

source "${SCRIPT_DIR}/logging.sh"
source "${SCRIPT_DIR}/display.sh"
source "${SCRIPT_DIR}/process.sh"
source "${SCRIPT_DIR}/database.sh"
source "${SCRIPT_DIR}/tables.sh"
source "${SCRIPT_DIR}/export.sh"
source "${SCRIPT_DIR}/files.sh"

generate_random_password() {
    # At least 1 uppercase, 1 lowercase, 1 digit, 1 symbol, min 12 chars
    local upper lower digit symbol rest
    upper=$(tr -dc '[:upper:]' < /dev/urandom | head -c1)
    lower=$(tr -dc '[:lower:]' < /dev/urandom | head -c1)
    digit=$(tr -dc '[:digit:]' < /dev/urandom | head -c1)
    symbol=$(tr -dc '[:punct:]' < /dev/urandom | head -c1)
    rest=$(tr -dc '[:alnum:][:punct:]' < /dev/urandom | head -c8)
    echo "${upper}${lower}${digit}${symbol}${rest}"
}

if [[ -z "$MSSQL_SA_PASSWORD" ]]; then
    export MSSQL_SA_PASSWORD="$(generate_random_password)"
fi

show_usage() {
    display "Usage: docker run -v /host/path/to/bak:/mnt/bak -v /host/path/to/output:/mnt/csv mssql-bak2csv [options]" --nolog
    display "" --nolog
    display "Options:" --nolog
    display "  --bak-file FILENAME       Name of the BAK file in the mounted directory (optional if only one .bak file exists)" --nolog
    display "  --tables TABLE1,TABLE2    Comma-separated list of tables to export (default: all)" --nolog
    display "                           Format: [database.]table_name" --nolog
    display "  --prefix PREFIX           Prefix to add to CSV filenames (e.g., 'ABC1_AB_')" --nolog
    display "  --suffix SUFFIX           Suffix to add to CSV filenames (e.g., '_backup')" --nolog
    display "  --help                    Show this help message" --nolog
    display "" --nolog
    display "Examples:" --nolog
    display "  docker run -v /data:/mnt/bak -v /data/output:/mnt/csv mssql-bak2csv" --nolog
    display "  docker run -v /data:/mnt/bak -v /data/output:/mnt/csv mssql-bak2csv --bak-file database.bak" --nolog
    display "  docker run -v /data:/mnt/bak -v /data/output:/mnt/csv mssql-bak2csv --bak-file database.bak --tables table1,table2" --nolog
    display "  docker run -v /data:/mnt/bak -v /data/output:/mnt/csv mssql-bak2csv --prefix 'ABC1_AB_' --suffix '_backup'" --nolog
}

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
            cleanup_and_exit 0
            ;;
        *)
            display "Unknown option: $1"
            show_usage
            cleanup_and_exit 1
            ;;
        esac
    done
}

main() {
    setup_logging
    setup_signal_handlers
    parse_arguments "$@"

    if ! find_bak_file; then
        cleanup_and_exit 1
    fi

    print_section "SQL Server" "-"
    if ! start_sql_server; then
        display "Failed to start SQL Server"
        cleanup_and_exit 1
    fi

    local DB_NAME
    local INTERNAL_BAK_FILE
    local OUTPUT_PATH

    DB_NAME=$(get_database_name "$CONTAINER_BAK_FILE")
    if [ -z "$DB_NAME" ]; then
        display "Failed to get database name from BAK file"
        cleanup_and_exit 1
    fi

    INTERNAL_BAK_FILE=$(prepare_bak_file "$CONTAINER_BAK_FILE")
    if [ -z "$INTERNAL_BAK_FILE" ] || [ ! -f "$INTERNAL_BAK_FILE" ]; then
        display "Failed to prepare BAK file for SQL Server"
        cleanup_and_exit 1
    fi

    if ! process_database_restore "$INTERNAL_BAK_FILE" "$DB_NAME"; then
        cleanup_and_exit 1
    fi

    OUTPUT_PATH=$(determine_output_dir)
    if ! process_database_export "$DB_NAME" "$OUTPUT_PATH"; then
        cleanup_and_exit 1
    fi

    cleanup_and_exit 0
}

main "$@"
