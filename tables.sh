#!/bin/bash

# Table discovery and metadata functions

get_table_list_query() {
    echo "
    SET NOCOUNT ON;
    DECLARE @db_name NVARCHAR(128);
    SELECT @db_name = name FROM sys.databases 
    WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb');
    
    DECLARE @sql NVARCHAR(MAX);
    SET @sql = 'USE [' + @db_name + ']; 
    SELECT @db_name + ''.'' + TABLE_NAME 
    FROM INFORMATION_SCHEMA.TABLES 
    WHERE TABLE_TYPE = ''BASE TABLE'' 
    ORDER BY TABLE_NAME;';
    
    EXEC sp_executesql @sql, N'@db_name NVARCHAR(128)', @db_name;"
}

filter_table_output() {
    local raw_output="$1"
    echo "$raw_output" | grep -v "^$" | grep -v "^Msg" | 
                         grep -v "^Invalid" | grep -v "^Sqlcmd:" | grep -v "^Changed database context"
}

list_tables() {
    local tables
    tables=$(execute_sql_query "" "$(get_table_list_query)" -h-1 -s"," -W -r1)

    if ! echo "$tables" | grep -q "\."; then
        println "Error: Failed to list tables."
        return 1
    fi

    local clean_tables
    clean_tables=$(filter_table_output "$tables")

    if [ -z "$clean_tables" ]; then
        println "No tables found in restored database."
        return 1
    fi

    echo "$clean_tables"
}

create_table_lookup_query() {
    local table="$1"
    local fallback_mode="${2:-false}"
    local clean_table
    clean_table=$(echo "$table" | tr -d '[]')
    
    local additional_condition=""
    if [ "$fallback_mode" = "false" ]; then
        additional_condition="OR OBJECT_ID(N'$clean_table') IS NOT NULL"
    fi
    
    echo "
    SELECT SCHEMA_NAME(schema_id) + '.' + name 
    FROM sys.tables 
    WHERE LOWER(name) = LOWER('$clean_table') 
    $additional_condition"
}

execute_table_lookup() {
    local database="$1"
    local query="$2"
    
    execute_sql_query "$database" "$query" -h-1 -W | 
        grep -v "^Msg" | grep -v "^$" | head -1 | tr -d '[:space:]'
}

get_table_schema_and_name() {
    local database="$1"
    local table="$2"
    
    local found_table
    found_table=$(execute_table_lookup "$database" "$(create_table_lookup_query "$table")")
    
    if [ -z "$found_table" ]; then
        found_table=$(execute_table_lookup "$database" "$(create_table_lookup_query "$table" true)")
    fi
    
    if [ -z "$found_table" ]; then
        return 1
    fi
    
    if [[ "$found_table" != *"."* ]]; then
        echo "dbo.$found_table"
    else
        echo "$found_table"
    fi
}

parse_table_info() {
    local table_info="$1"
    local table_db
    table_db=$(echo "$table_info" | cut -d'.' -f1)
    local table_name
    table_name=$(echo "$table_info" | cut -d'.' -f2)
    
    if [ -n "$table_db" ] && [ -n "$table_name" ]; then
        echo "$table_db:$table_name"
        return 0
    else
        return 1
    fi
}
