#!/bin/bash

# File handling functions

determine_output_dir() {
    if mountpoint -q /mnt/csv 2>/dev/null; then
        echo "/mnt/csv"
    else
        mkdir -p "/mnt/bak/output"
        echo "/mnt/bak/output"
    fi
}

find_bak_file() {
    if [[ -z "$BAK_FILE" ]]; then
        println "Looking for .bak files..."
        
        local bak_files=()
        while IFS= read -r -d '' file; do
            bak_files+=("$file")
        done < <(find /mnt/bak -maxdepth 1 -name "*.bak" -type f -print0)
        
        if [[ ${#bak_files[@]} -eq 0 ]]; then
            println "Error: No .bak files found"
            println "Make sure you mounted a directory containing .bak files to /mnt/bak"
            return 1
        elif [[ ${#bak_files[@]} -eq 1 ]]; then
            export CONTAINER_BAK_FILE="${bak_files[0]}"
            export BAK_FILENAME
            BAK_FILENAME=$(basename "$CONTAINER_BAK_FILE")
            println "Found BAK file: $BAK_FILENAME"
        else
            println "Error: Multiple .bak files found:"
            for file in "${bak_files[@]}"; do
                println "  $(basename "$file")"
            done
            println "Please specify which one to use with --bak-file FILENAME"
            return 1
        fi
    else
        export BAK_FILENAME="$BAK_FILE"
        export CONTAINER_BAK_FILE="/mnt/bak/$BAK_FILENAME"
        
        if [[ ! -f "$CONTAINER_BAK_FILE" ]]; then
            println "Error: BAK file '$BAK_FILENAME' not found"
            println "Make sure you mounted the directory containing your BAK file to /mnt/bak"
            return 1
        fi
    fi
    
    return 0
}

prepare_bak_file() {
    local bak_file="$1"
    local internal_path="/var/opt/mssql/backup"
    
    println "📁 Copying BAK file to SQL Server backup directory..." true
    mkdir -p "$internal_path"
    cp "$bak_file" "$internal_path/"
    sync
    
    local target
    target="${internal_path}/$(basename "$bak_file")"
    if [ ! -f "$target" ]; then
        println "Error: Failed to copy BAK file"
        return 1
    fi
    
    echo "$target"
}
