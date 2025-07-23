# MSSQL BAK to CSV Converter

Docker container that converts SQL Server backup files (.bak) to CSV.

## Features

- Restores MSSQL .bak files to a temporary SQL Server instance
- Lists and exports tables to CSV format
- Supports selective table export
- Handles multiple databases and schemas
- Properly quotes and escapes values in CSV output
- Distinguishes between SQL `NULL`, the string `"null"`, and empty strings
- Outputs CSV files with configurable prefixes and suffixes

## Requirements

- Docker
- Sufficient disk space and memory for database restoration
- .bak file compatible with/upgradable to SQL Server 2022

## Usage

```bash
# Basic usage (auto-detect BAK file, output all tables to mounted bak path)
docker run --rm \
  -v /path/to/backup/directory:/mnt/bak \
  mssql-bak2csv

# Use specified bak file, output selected tables to mounted csv path with given prefix and suffix
docker run --rm \
  -v /path/to/backup/directory:/mnt/bak \
  -v /path/to/output/directory:/mnt/csv \
  mssql-bak2csv \
  --bak-file your-database.bak \
  --tables "table1,table2,table3" \
  --prefix "prefix_" \
  --suffix "_backup"
```

## Usage Options

- `--bak-file FILENAME`: Name of the .bak file (optional if only one exists)
- `--tables TABLE1,TABLE2`: Comma-separated list of tables to export (default: all)
- `--prefix PREFIX`: Prefix for CSV filenames (e.g., 'ABC1_AB_')
- `--suffix SUFFIX`: Suffix for CSV filenames (e.g., '_backup')
- `--help`: Show usage information

### Table Selection Formats

- Simple name: `table1` (uses default database and schema)
- With database: `mydatabase.table1` (specifies database, uses default schema)
- Fully qualified: `mydatabase.myschema.table1` (specifies database and schema)

## Output Format

CSV files are named using the simplest format that avoids collisions:

- `[PREFIX]{table}[SUFFIX].csv` (e.g., `Users.csv`)
- `[PREFIX]{schema}_{table}[SUFFIX].csv` (e.g., `dbo_Users.csv`)
- `[PREFIX]{database}_{schema}_{table}[SUFFIX].csv` (e.g., `MyDB_dbo_Users.csv`)

## Value Handling in CSV Output

### Raw Values

Data values, such as images and binary, and floats are exported from sqlcmd as-is to avoid mangling by casting or converting or truncating them.

### Distinguishing Between SQL NULL, "null", and Empty Strings

To ensure reliable parsing and distinction between SQL `NULL`, the string `"null"` (case-insensitive), and empty strings, the export logic encodes these values as follows:

- SQL `NULL` values are exported as an empty field (i.e., nothing between the commas: `,,`).
- The string value `"null"` (case-insensitive, e.g., `"NULL"`, `"Null"`, `"null"`) is always quoted and escaped (unless trailing or leading whitespace is present, in which case the value should be parsed as a string)
- Empty strings are exported as `""` (two double quotes), distinguishing them from null values

This helps ensure consumers of the CSV can always distinguish between a true SQL `NULL`, a string containing `"null"`, and an empty string.

### All Other Values

Values that contain the delimiting character (`,`), line breaks, or quotes are quoted and escaped as follows:
1. Replace any quotes (`"`) in the value with two quotes (`""`).
2. Wrap the value in quotes (`"`).

## Notes

- The container uses SQL Server Developer edition by default (not licensed for production use)
- Mounts: backup directory to `/mnt/bak`, optional output directory to `/mnt/csv`
- Database restoration is temporary - only CSV files persist between runs

### SQL Server Password

By default, the container generates a secure random password for the SQL Server `sa` user at runtime.  
To specify your own password, set the `MSSQL_SA_PASSWORD` environment variable when running the container:

```bash
docker run --rm \
  -e MSSQL_SA_PASSWORD='YourSecurePassword123!' \
  -v /path/to/backup/directory:/mnt/bak \
  mssql-bak2csv
```

The password must meet SQL Server complexity requirements (at least 8 characters, including uppercase, lowercase, number, and symbol).

## Licensing

This project uses the official Microsoft SQL Server container image (`mcr.microsoft.com/mssql/server:2022-latest`) and Microsoft SQL Server tools (`mssql-tools`, `sqlcmd`). By using this image and these tools, you agree to the [Microsoft SQL Server End User License Agreement (EULA)](https://go.microsoft.com/fwlink/?linkid=857698).

The default configuration uses SQL Server Developer edition, which is licensed for development and testing only—not for production workloads. To use another edition, set the `MSSQL_PID` environment variable as described in the [SQL Server container documentation](https://learn.microsoft.com/sql/linux/sql-server-linux-configure-environment-variables?view=sql-server-ver16).

This project itself is provided under the MIT License (see LICENSE file).
