#!/bin/bash

# CSV export utility functions

write_csv_header() {
    local output_file="$1"
    shift
    local columns=("$@")

    IFS=','
    echo "${columns[*]}" >"$output_file"
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

        if [[ "$data_type" =~ ^(binary|varbinary|image)$ ]]; then
            # For binary types, just select the column without transformation
            select_exprs+=(
                "[${col}]"
            )
        else
            # For text types, apply CSV escaping and quoting
            select_exprs+=(
                "CASE WHEN CHARINDEX(',', [${col}]) > 0 OR CHARINDEX(CHAR(10), [${col}]) > 0 OR CHARINDEX(CHAR(13), [${col}]) > 0 OR CHARINDEX('\"', [${col}]) > 0 THEN '\"' + REPLACE(ISNULL(CAST([${col}] AS NVARCHAR(MAX)), ''), '\"', '\"\"') + '\"' ELSE ISNULL(CAST([${col}] AS NVARCHAR(MAX)), '') END AS [${col}]"
            )
        fi
    done

    echo "SET NOCOUNT ON; SELECT $(
        IFS=','
        printf '%s' "${select_exprs[*]}"
    ) FROM [${schema}].[${table_name}]"
}
