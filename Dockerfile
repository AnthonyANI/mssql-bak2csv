FROM mcr.microsoft.com/mssql/server:2022-latest

# Install necessary tools
USER root
RUN apt-get update && apt-get install -y \
    curl \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Add SQL Server tools to PATH
ENV PATH="$PATH:/opt/mssql-tools18/bin"

# Set environment variables for SQL Server
ENV ACCEPT_EULA=Y
ENV SA_PASSWORD=MSSQL_bak2csv!
ENV MSSQL_PID=Developer

# Create directories for mounting
RUN mkdir -p /mnt/bak /mnt/csv

# Create directories for SQL Server
RUN mkdir -p /var/opt/mssql/backup /var/opt/mssql/data

WORKDIR /opt/mssql-bak2csv

# Copy scripts to container
COPY --chmod=0755 src/entrypoint.sh \
    src/logging.sh \
    src/display.sh \
    src/database.sh \
    src/tables.sh \
    src/export.sh \
    src/files.sh \
    src/process.sh ./

# Set entrypoint
ENTRYPOINT ["/opt/mssql-bak2csv/entrypoint.sh"]
