FROM mcr.microsoft.com/powershell:7.1.2-ubuntu-20.04
LABEL maintainer="ricardo@datawan.net"
# Install Needed packages
RUN apt-get update && apt-get install -y \
        apt-utils \
        cron \
        software-properties-common \
        netbase

# Install WsMan manually to fix Ubuntu 20.04 known issue
RUN sh -c "yes | pwsh -Command 'Install-Module -Name PSWSMan'"
RUN pwsh -Command 'Install-WSMan'

# Add files
ADD entrypoint.sh /root/entrypoint.sh
RUN chmod +x /root/entrypoint.sh

# Entrypoint
ENTRYPOINT /root/entrypoint.sh