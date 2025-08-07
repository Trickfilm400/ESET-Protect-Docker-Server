FROM ubuntu:24.04 AS odbc-build

# Set environment
ENV LANG=C.UTF-8

# ODBC Version
ARG ODBC_VERSION=8.0.43

# Set non-interactive (for apt etc.)
ENV DEBIAN_FRONTEND=noninteractive

# Depdenencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libmysqlclient-dev \
    unixodbc-dev \
    wget \
    cmake \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install MySQL ODBC connector
ADD https://cdn.mysql.com/Downloads/Connector-ODBC/8.0/mysql-connector-odbc-${ODBC_VERSION}-src.tar.gz /tmp/mysql-odbc.tar.gz
RUN mkdir -p /tmp/odbc \
    && tar -xzf /tmp/mysql-odbc.tar.gz -C /tmp/odbc --strip-components=1 \
    && cd /tmp/odbc \
    && cmake . -DDISABLE_GUI=1 -DWITH_UNIXODBC=1 -DMYSQLCLIENT_STATIC_LINKING=TRUE \
    && make

FROM ubuntu:24.04 AS eset-builder

# Add installer
# ESET versions
ARG ESET_VERSION=12.1.252.0

ADD https://repository.eset.com/v1/com/eset/apps/business/era/server/linux/v12/${ESET_VERSION}/server_linux_x86_64.sh /install/server-linux-x86_64.sh
RUN sed -i 's|config_ProgramConfigDir=.*|config_ProgramConfigDir=/config|g' /install/server-linux-x86_64.sh \
    && sed -i 's|^config_ProgramDataDir=.*|config_ProgramDataDir=/data|g' /install/server-linux-x86_64.sh \
    && sed -i 's|^config_ProgramLogsDir=.*|config_ProgramLogsDir=/logs|g' /install/server-linux-x86_64.sh \
    && chmod +x /install/server-linux-x86_64.sh

# Run installer in "files" mode
RUN install/server-linux-x86_64.sh \
    --install-type=files \
    --service-user=eset \
    --service-group=eset \
    --skip-license \
    && rm -f /install/server-linux-x86_64.sh


# Use Ubuntu 22.04
FROM ubuntu:24.04

# Set environment
ENV LANG=C.UTF-8

# Set non-interactive (for apt etc.)
ENV DEBIAN_FRONTEND=noninteractive

# Set python UNBUFFERED
ENV PYTHONUNBUFFERED=1

# Dependencies, taken from: https://help.eset.com/protect_install/latest/en-US/prerequisites_server_linux.html
RUN apt update && apt full-upgrade -y && apt install -y --no-install-recommends \
    xvfb \
    ca-certificates \
    cifs-utils \
    krb5-user \
    ldap-utils \
    libsasl2-modules-gssapi-mit \
    snmp \
    libodbc2 \
    libodbcinst2 \
    libssl-dev \
    samba \
    python3 \
    lshw \
    libglib2.0-0 \
    libnss3 \
    libatk1.0-0t64 \
    libatk-bridge2.0-0t64 \
    libxcomposite1 \
    libxdamage1 \
    libgbm1 \
    libcairo2 \
    libxkbcommon0 \
    libpango-1.0-0 \
    libasound2t64 \
    libxfixes3 \
    && rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir \
    /install \
    /config \
    /data \
    /logs

# Install ODBC
COPY --from=odbc-build /tmp/odbc /tmp/odbc
RUN cp /tmp/odbc/lib/*.so /usr/lib64 \
    && cp /tmp/odbc/bin/* /usr/bin \
    && /usr/bin/myodbc-installer -d -a -n "MySQL ODBC Unicode Driver" -t "DRIVER=/usr/lib64/libmyodbc8w.so" \
    && rm -rf /tmp/odbc \
    && rm -f /install/mysql-odbc.tar.gz

# Create user
RUN groupadd -r eset -g 3537 \
    &&  useradd --no-log-init -r -g eset -u 3537 eset

# Create directories and synlinks
RUN mkdir -p \
    /etc/opt/eset/RemoteAdministrator \
    /var/opt/eset/RemoteAdministrator \
    /var/log/eset \
    && ln -s /config /etc/opt/eset/RemoteAdministrator/Server \
    && ln -s /data /var/opt/eset/RemoteAdministrator/Server \
    && ln -s /logs /var/log/eset/RemoteAdministrator

# with correct permissions
COPY --from=eset-builder --chown=eset:eset /opt/eset/RemoteAdministrator/Server /opt/eset/RemoteAdministrator/Server


# Volumes
VOLUME [ "/config", "/data", "/logs" ]

# Create script for report generation
RUN cp /opt/eset/RemoteAdministrator/Server/ReportPrinterTool /opt/eset/RemoteAdministrator/Server/ReportPrinterToolOrig
COPY files/ReportPrinterTool /opt/eset/RemoteAdministrator/Server/ReportPrinterTool
RUN chmod 755 /opt/eset/RemoteAdministrator/Server/ReportPrinterTool


# Add entrypoint and healthcheck
COPY files/healthcheck.py /healthcheck.py
COPY files/run.py /run.py
RUN chmod +x \
    /run.py \
    /healthcheck.py


# Ports
EXPOSE 2222 2223

# Healthcheck
HEALTHCHECK --interval=1m --timeout=10s --start-period=10m \  
    CMD /healthcheck.py

# Set user
USER eset

# Entrypoint
ENTRYPOINT ["/run.py"]