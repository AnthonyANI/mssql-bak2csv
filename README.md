# MSSQL BAK to CSV Converter

Docker container that converts SQL Server backup files (.bak) to CSV by restoring the database and exporting tables.

## Quick Start

```bash
# Basic usage (auto-detect BAK file)
docker run --rm \
  -v /path/to/backup/directory:/mnt/bak \
  -v /path/to/output/directory:/mnt/csv \
  mssql-bak2csv

# Specify BAK file and tables
docker run --rm \
  -v /path/to/backup/directory:/mnt/bak \
  -v /path/to/output/directory:/mnt/csv \
  mssql-bak2csv \
  --bak-file your-database.bak \
  --tables "table1,table2,table3" \
  --prefix "prefix_" \
  --suffix "_backup"
```

## Features

- Restores MSSQL .bak files to a temporary SQL Server instance
- Lists and exports tables to CSV format
- Supports selective table export
- Handles multiple databases and schemas

## Usage Options

- `--bak-file FILENAME`: Name of the .bak file (optional if only one exists)
- `--tables TABLE1,TABLE2`: Comma-separated list of tables to export (default: all)
- `--prefix PREFIX`: Prefix for CSV filenames (e.g., 'ABC1_AB_')
- `--suffix SUFFIX`: Suffix for CSV filenames (e.g., '_backup')
- `--help`: Show usage information

## Table Selection Formats

- Simple name: `table1` (uses default database and schema)
- With database: `mydatabase.table1` (specifies database, uses default schema)
- Fully qualified: `mydatabase.myschema.table1` (specifies database and schema)

## Output Format

CSV files are named using the simplest format that avoids collisions:

- `[PREFIX]{table}[SUFFIX].csv` (e.g., `Users.csv`)
- `[PREFIX]{schema}_{table}[SUFFIX].csv` (e.g., `dbo_Users.csv`)
- `[PREFIX]{database}_{schema}_{table}[SUFFIX].csv` (e.g., `MyDB_dbo_Users.csv`)

## Requirements

- Docker
- Sufficient disk space and memory for database restoration
- .bak file compatible with/upgradable to SQL Server 2022

## Notes

- The container uses SQL Server Developer edition by default (not licensed for production use)
- Mounts: backup directory to `/mnt/bak`, optional output directory to `/mnt/csv`
- Database restoration is temporary - only CSV files persist between runs

## Licensing

This project uses the official Microsoft SQL Server container image (`mcr.microsoft.com/mssql/server:2022-latest`) and Microsoft SQL Server tools (`mssql-tools`, `sqlcmd`). By using this image and these tools, you agree to the [Microsoft SQL Server End User License Agreement (EULA)](https://go.microsoft.com/fwlink/?linkid=857698).

The default configuration uses SQL Server Developer edition, which is licensed for development and testing only—not for production workloads. To use another edition, set the `MSSQL_PID` environment variable as described in the [SQL Server container documentation](https://learn.microsoft.com/sql/linux/sql-server-linux-configure-environment-variables?view=sql-server-ver16).

This project itself is provided under the MIT License (see LICENSE file).
