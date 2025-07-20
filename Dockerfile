FROM mcr.microsoft.com/mssql/server:2022-latest

# Install necessary tools
USER root
RUN apt-get update && apt-get install -y \
    curl \
    gnupg \
    unixodbc-dev \
    && rm -rf /var/lib/apt/lists/*

# Install mssql-tools
RUN curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - \
    && curl https://packages.microsoft.com/config/ubuntu/22.04/prod.list > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y mssql-tools unixodbc-dev \
    && rm -rf /var/lib/apt/lists/*

# Add SQL Server tools to PATH
ENV PATH="$PATH:/opt/mssql-tools/bin"

# Set environment variables for SQL Server
ENV ACCEPT_EULA=Y
ENV SA_PASSWORD=MSSQL_bak2csv!
ENV MSSQL_PID=Express

# Create directories for mounting
RUN mkdir -p /mnt/bak /mnt/csv

# Create directories for SQL Server
RUN mkdir -p /var/opt/mssql/backup /var/opt/mssql/data

WORKDIR /opt/mssql-bak2csv

# Copy scripts to container
COPY --chmod=0755 src/entrypoint.sh src/logging.sh src/display.sh src/database.sh src/tables.sh src/csv.sh src/export.sh src/files.sh ./

# Set entrypoint
ENTRYPOINT ["/opt/mssql-bak2csv/entrypoint.sh"]
