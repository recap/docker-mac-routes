FROM alpine:latest

# Install essential networking tools
RUN apk add --no-cache \
    iptables \
    iproute2 \
    net-tools \
    iputils \
    dnsmasq \
    tcpdump \
    socat \
    curl \
    wget \
    nmap \
    bind-tools \
    && rm -rf /var/cache/apk/*

# Set default shell
CMD ["sh"]
