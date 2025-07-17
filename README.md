# MSSQL BAK to CSV Converter

This Docker container converts Microsoft SQL Server backup files (.bak) to CSV format by restoring the database and exporting tables.

## Features

- Restores MSSQL .bak files to a temporary SQL Server instance
- Lists all tables in the restored database(s)
- Exports tables to CSV format
- Supports selective table export
- Handles multiple databases with table prefixes
- Automatic cleanup and proper error handling

## Building the Container

```bash
docker build -t mssql-bak2csv .
```

## Usage

### Basic Usage (Auto-detect BAK file)

If there's only one .bak file in your backup directory:

```bash
docker run --rm \
  -v /path/to/backup/directory:/mnt/bak \
  -v /path/to/output/directory:/mnt/csv \
  mssql-bak2csv
```

### Basic Usage (Specify BAK file)

```bash
docker run --rm \
  -v /path/to/backup/directory:/mnt/bak \
  -v /path/to/output/directory:/mnt/csv \
  mssql-bak2csv \
  --bak-file your-database.bak
```

### Export Specific Tables

```bash
docker run --rm \
  -v /path/to/backup/directory:/mnt/bak \
  -v /path/to/output/directory:/mnt/csv \
  mssql-bak2csv \
  --bak-file your-database.bak \
  --tables "table1,table2,table3"
```

### Export with Custom Filename Format

```bash
docker run --rm \
  -v /path/to/backup/directory:/mnt/bak \
  -v /path/to/output/directory:/mnt/csv \
  mssql-bak2csv \
  --bak-file your-database.bak \
  --prefix "ABC1_AB_" \
  --suffix "_backup"
```

## Parameters

- `--bak-file FILENAME`: Name of the .bak file in the mounted backup directory (optional if only one .bak file exists)
- `--tables TABLE1,TABLE2`: Comma-separated list of tables to export (default: all tables)
- `--prefix PREFIX`: Prefix to add to CSV filenames (e.g., 'ABC1_AB_')
- `--suffix SUFFIX`: Suffix to add to CSV filenames (e.g., '_backup')
- `--help`: Show usage information

## Path Handling

The container uses fixed mount points for simplicity:
- Mount your backup directory to `/mnt/bak`
- Mount your output directory to `/mnt/csv`
- `--bak-file` expects just the filename (e.g., `database.bak`) since it's relative to the mounted backup directory

**Auto-detection**: If you don't specify `--bak-file`, the container will automatically use the .bak file if there's exactly one in the mounted backup directory. If there are multiple .bak files, you'll need to specify which filename to use.

## Table Name Formats

The `--tables` parameter supports several formats:

1. **Simple table name**: `table1` - Uses default database and schema (dbo)
2. **Database.table**: `mydatabase.table1` - Specifies database, uses default schema (dbo)
3. **Database.schema.table**: `mydatabase.myschema.table1` - Fully qualified name

## Output Format

CSV files are named using the simplest possible format while avoiding collisions:

- **No collisions**: `[PREFIX]{table}[SUFFIX].csv` (e.g., `Users.csv`)
- **Schema collision**: `[PREFIX]{schema}_{table}[SUFFIX].csv` (e.g., `dbo_Users.csv`)
- **Database collision**: `[PREFIX]{database}_{schema}_{table}[SUFFIX].csv` (e.g., `MyDB_dbo_Users.csv`)

The system automatically detects naming conflicts and uses the minimum level of qualification needed to make filenames unique.

Additional format details:
- Headers are included in each CSV file
- Empty rows are removed from output
- Trailing spaces are trimmed

## Example Usage

Basic usage examples:

```bash
# Build the container
docker build -t mssql-bak2csv .

# Run with auto-detection (simplest approach)
docker run --rm \
  -v $(pwd):/mnt/bak \
  -v $(pwd)/output:/mnt/csv \
  mssql-bak2csv

# Or explicitly specify the BAK filename
docker run --rm \
  -v $(pwd):/mnt/bak \
  -v $(pwd)/output:/mnt/csv \
  mssql-bak2csv \
  --bak-file your-database.bak

# Export specific tables with custom filename format
docker run --rm \
  -v $(pwd):/mnt/bak \
  -v $(pwd)/output:/mnt/csv \
  mssql-bak2csv \
  --bak-file your-database.bak \
  --tables "table1,table2" \
  --prefix "ABC1_AB_" \
  --suffix "_export"
```

This will:
1. Auto-detect or restore the specified .bak file
2. List all tables in the restored database
3. Export all tables to CSV files in the `./output` directory

## Environment Variables

The container uses these SQL Server settings:
- `ACCEPT_EULA=Y` - Accepts the SQL Server license agreement
- `SA_PASSWORD=MSSQL_bak2csv!` - Sets the SQL Server system administrator password
- `MSSQL_PID=Express` - Specifies SQL Server Express edition (free, no licensing required)

## Troubleshooting

### Common Issues

1. **Permission denied**: Make sure the mounted directories have proper permissions
2. **Database restore fails**: Check that the .bak file is not corrupted and is compatible with SQL Server 2019
3. **Out of space**: Ensure sufficient disk space for database restoration and CSV export

### Debugging

To run the container interactively for debugging:

```bash
docker run -it --rm \
  -v /path/to/backup:/mnt/bak \
  -v /path/to/output:/mnt/csv \
  mssql-bak2csv \
  bash
```

## Requirements

- Docker
- Sufficient disk space for database restoration
- .bak file compatible with SQL Server 2019

## Notes

- The container automatically starts and stops SQL Server
- Database restoration is temporary - data is not persisted between runs
- CSV files are the only persistent output
- The container exits after export completion unless modified
