#!/bin/bash

# SQL Server and database operations

execute_sql_query() {
    local database="$1"
    local query="$2"
    shift 2

    sqlcmd -S localhost -U sa -P "$SA_PASSWORD" ${database:+-d"$database"} -y 0 -C -X 1 -Q "$query" "$@"
}

start_sql_server() {
    mkdir -p "/var/opt/mssql/log"

    display -n "Starting SQL Server"
    /opt/mssql/bin/sqlservr >/var/opt/mssql/log/startup.log 2>&1 &
    export SQL_PID=$!

    for i in {1..60}; do
        if execute_sql_query "" "SELECT 1" >/dev/null 2>&1; then
            display -e "\nSQL Server is ready!"
            return 0
        fi

        if [[ $i -eq 60 ]]; then
            display -e "\nSQL Server failed to start"
            return 1
        fi

        display -n "." --nolog
        sleep 1
    done
}

get_database_name() {
    local bak_file="$1"
    local db_name
    db_name=$(execute_sql_query "" "RESTORE FILELISTONLY FROM DISK = '$bak_file'" | head -1 | awk '{print $1}')
    echo "$db_name" | xargs
}

restore_database() {
    local bak_file="$1"
    local db_name="$2"

    local logical_files
    logical_files=$(execute_sql_query "" "RESTORE FILELISTONLY FROM DISK = '$bak_file'")
    local data_file
    local log_file
    data_file=$(echo "$logical_files" | grep -E '\s+D\s+' | head -1 | awk '{print $1}')
    log_file=$(echo "$logical_files" | grep -E '\s+L\s+' | head -1 | awk '{print $1}')

    local output
    if ! output=$(execute_sql_query "" "
    RESTORE DATABASE [$db_name] 
    FROM DISK = '$bak_file' 
    WITH MOVE '$data_file' TO '/var/opt/mssql/data/${db_name}.mdf',
         MOVE '$log_file' TO '/var/opt/mssql/data/${db_name}.ldf',
         REPLACE" 2>&1); then
        display "$output"
        return 1
    fi

    log "$output"

    # Check for SQL errors in output even if the command succeeded
    if echo "$output" | grep -q "Msg [0-9]*, Level [0-9]*, State"; then
        display "$output"
        return 1
    fi

    return 0
}

process_database_restore() {
    local bak_file="$1"
    local db_name="$2"

    print_section "Database Restore" "-"
    display "🔄 Restoring database '$db_name' from '$(basename "$bak_file")'..."

    if ! restore_database "$bak_file" "$db_name"; then
        display "❌ Failed to restore database"
        return 1
    fi

    display "✅ Database '$db_name' restored successfully!"
    return 0
}

build_data_query() {
    local schema="$1"
    local table_name="$2"
    shift 2
    local column_info=("$@")

    local select_exprs=()
    for info in "${column_info[@]}"; do
        local col
        local data_type
        col=$(echo "$info" | cut -d'|' -f1)
        data_type=$(echo "$info" | cut -d'|' -f2)

        if [[ "$data_type" =~ ^(binary|varbinary|image|float)$ ]]; then
            # For raw data and float types, just select the column without transformation
            select_exprs+=(
                "[${col}]"
            )
        else
            # For all other types, cast to NVARCHAR and apply CSV formatting and escaping as needed
            select_exprs+=(
                "CASE
                    WHEN [${col}] IS NULL THEN ''
                    WHEN CAST([${col}] AS NVARCHAR(MAX)) = '' THEN '\"\"'
                    WHEN LOWER(CAST([${col}] AS NVARCHAR(MAX))) = 'null'
                        OR CHARINDEX(',', [${col}]) > 0
                        OR CHARINDEX(CHAR(10), [${col}]) > 0
                        OR CHARINDEX(CHAR(13), [${col}]) > 0
                        OR CHARINDEX('\"', [${col}]) > 0
                            THEN '\"' + REPLACE(CAST([${col}] AS NVARCHAR(MAX)), '\"', '\"\"') + '\"'
                    ELSE CAST([${col}] AS NVARCHAR(MAX))
                END AS [${col}]"
            )
        fi
    done

    echo "SET NOCOUNT ON; SELECT $(
        IFS=','
        printf '%s' "${select_exprs[*]}"
    ) FROM [${schema}].[${table_name}]"
}
