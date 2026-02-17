FROM alpine:3.19

LABEL org.opencontainers.image.title="Greenhouse"
LABEL org.opencontainers.image.description="Lightweight Docker seedbox with rtorrent, Flood UI, and WireGuard VPN"

# Install runtime dependencies
RUN apk add --no-cache \
    # Core dependencies
    bash \
    curl \
    wget \
    ca-certificates \
    supervisor \
    coreutils \
    bind-tools \
    shadow \
    # WireGuard
    wireguard-tools \
    iptables \
    ip6tables \
    openresolv \
    # rtorrent dependencies
    rtorrent \
    mediainfo \
    ffmpeg \
    unzip \
    # unrar \
    # Node.js for Flood
    nodejs \
    npm \
    && mkdir -p /var/log/supervisor

# Install Flood UI (pinned version for reproducible builds)
RUN apk add --no-cache --virtual .build-deps \
        git \
        python3 \
        make \
        g++ \
    && npm install -g @jesec/flood@0.0.0-master.01f5a4a \
    && apk del .build-deps \
    && npm cache clean --force

# Create directories
RUN mkdir -p \
    /config \
    /config/rtorrent \
    /config/flood \
    /config/wireguard \
    /downloads \
    /watch \
    /session \
    /var/run/rtorrent \
    && chmod -R 755 /config /downloads /watch /session /var/run/rtorrent

# Create rtorrent user
RUN addgroup -g 1000 rtorrent \
    && adduser -D -u 1000 -G rtorrent rtorrent \
    && chown -R rtorrent:rtorrent /config /downloads /watch /session /var/run/rtorrent

# Copy configuration files
COPY config/rtorrent.rc /defaults/rtorrent.rc
COPY config/supervisord.conf /etc/supervisord.conf
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/healthcheck.sh /healthcheck.sh
COPY scripts/start-wireguard.sh /usr/local/bin/start-wireguard.sh

# Make scripts executable
RUN chmod +x /entrypoint.sh /healthcheck.sh /usr/local/bin/start-wireguard.sh

# Expose ports
# 5000 - Flood UI
# 6881 - rtorrent incoming connections (TCP + UDP)
EXPOSE 5000 6881

# Volumes
VOLUME ["/config", "/downloads", "/watch"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /healthcheck.sh

# Set working directory
WORKDIR /config

# Run entrypoint
ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisord.conf", "-n"]
