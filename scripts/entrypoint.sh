#!/bin/bash
set -e

echo "==================================="
echo "Starting Greenhouse"
echo "==================================="

# Function to handle shutdown
shutdown() {
    echo "Shutting down..."
    supervisorctl stop all
    if [ -f /var/run/rtorrent/rpc.sock ]; then
        rm -f /var/run/rtorrent/rpc.sock
    fi
    wg-quick down wg0 2>/dev/null || true
    exit 0
}

trap shutdown SIGTERM SIGINT

# Apply PUID/PGID if different from default
PUID=${PUID:-1000}
PGID=${PGID:-1000}

if [ "$(id -u rtorrent)" != "$PUID" ] || [ "$(id -g rtorrent)" != "$PGID" ]; then
    echo "Updating rtorrent user to UID=$PUID GID=$PGID..."
    groupmod -o -g "$PGID" rtorrent
    usermod -o -u "$PUID" rtorrent
fi

# Set permissions
chown -R rtorrent:rtorrent /config /downloads /watch /session /var/run/rtorrent
chmod -R 755 /config /downloads /watch /session

# Check if WireGuard config exists
if [ -f /config/wireguard/wg0.conf ]; then
    echo "WireGuard configuration found. Setting up VPN..."

    # Copy WireGuard config to system location
    mkdir -p /etc/wireguard
    cp /config/wireguard/wg0.conf /etc/wireguard/wg0.conf
    chmod 600 /etc/wireguard/wg0.conf

    # Set up killswitch - block all traffic except through VPN
    echo "Setting up killswitch..."

    # --- IPv4 ---
    # Flush existing rules
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X

    # Set default policies to DROP
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT DROP

    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT

    # Allow established and related connections (CRITICAL for both TCP and UDP)
    iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    iptables -A OUTPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

    # Allow DNS queries to specific servers (needed before VPN connects)
    iptables -A OUTPUT -p udp --dport 53 -d 1.1.1.1 -j ACCEPT
    iptables -A OUTPUT -p udp --dport 53 -d 8.8.8.8 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 53 -d 1.1.1.1 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 53 -d 8.8.8.8 -j ACCEPT

    # Allow local network (for accessing Flood UI)
    # Note: NOT including 10.0.0.0/8 as it conflicts with many VPN internal networks
    iptables -A INPUT -s 172.16.0.0/12 -j ACCEPT
    iptables -A OUTPUT -d 172.16.0.0/12 -j ACCEPT
    iptables -A INPUT -s 192.168.0.0/16 -j ACCEPT
    iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT

    # Extract VPN endpoint from config (handles both IPv4 and IPv6 endpoints)
    ENDPOINT_RAW=$(awk '/^Endpoint[[:space:]]*=/ {sub(/^Endpoint[[:space:]]*=[[:space:]]*/, ""); print; exit}' /etc/wireguard/wg0.conf)
    VPN_PORT="${ENDPOINT_RAW##*:}"
    VPN_ENDPOINT="${ENDPOINT_RAW%:*}"
    # Strip brackets from IPv6 addresses (e.g. [2001:db8::1] -> 2001:db8::1)
    VPN_ENDPOINT="${VPN_ENDPOINT#[}"
    VPN_ENDPOINT="${VPN_ENDPOINT%]}"

    if [ -n "$VPN_ENDPOINT" ] && [ -n "$VPN_PORT" ]; then
        echo "Allowing traffic to VPN endpoint: $VPN_ENDPOINT:$VPN_PORT"
        # Allow traffic to VPN endpoint
        iptables -A OUTPUT -d "$VPN_ENDPOINT" -p udp --dport "$VPN_PORT" -j ACCEPT
    fi

    # Allow all traffic through WireGuard interface
    iptables -A INPUT -i wg0 -j ACCEPT
    iptables -A OUTPUT -o wg0 -j ACCEPT
    iptables -A FORWARD -i wg0 -j ACCEPT
    iptables -A FORWARD -o wg0 -j ACCEPT

    # --- IPv6 ---
    # Flush existing rules
    ip6tables -F
    ip6tables -X
    ip6tables -t nat -F
    ip6tables -t nat -X
    ip6tables -t mangle -F
    ip6tables -t mangle -X

    # Set default policies to DROP
    ip6tables -P INPUT DROP
    ip6tables -P FORWARD DROP
    ip6tables -P OUTPUT DROP

    # Allow loopback
    ip6tables -A INPUT -i lo -j ACCEPT
    ip6tables -A OUTPUT -o lo -j ACCEPT

    # Allow established and related connections
    ip6tables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    ip6tables -A OUTPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

    # Allow link-local addresses (required for basic IPv6 operation)
    ip6tables -A INPUT -s fe80::/10 -j ACCEPT
    ip6tables -A OUTPUT -d fe80::/10 -j ACCEPT

    # Allow unique-local (fc00::/7) for LAN access (IPv6 equivalent of RFC1918)
    ip6tables -A INPUT -s fc00::/7 -j ACCEPT
    ip6tables -A OUTPUT -d fc00::/7 -j ACCEPT

    # Allow all traffic through WireGuard interface
    ip6tables -A INPUT -i wg0 -j ACCEPT
    ip6tables -A OUTPUT -o wg0 -j ACCEPT
    ip6tables -A FORWARD -i wg0 -j ACCEPT
    ip6tables -A FORWARD -o wg0 -j ACCEPT

    echo "Killswitch enabled. All non-VPN traffic will be blocked."
    echo "VPN will be started by supervisord..."
else
    echo "WARNING: No WireGuard configuration found at /config/wireguard/wg0.conf"
    echo "The container will start without VPN. Please add your WireGuard config and restart."
    echo ""
    echo "To use WireGuard VPN:"
    echo "1. Place your wg0.conf file in the /config/wireguard/ directory"
    echo "2. Restart the container"
    echo ""
fi

# Check if custom rtorrent.rc exists, if not create default
if [ ! -f /config/rtorrent/rtorrent.rc ]; then
    echo "Creating default rtorrent.rc..."
    mkdir -p /config/rtorrent
    cat > /config/rtorrent/rtorrent.rc << 'RTORRENT_EOF'
# Instance layout (base paths)
method.insert = cfg.basedir,  private|const|string, (cat,"/config/rtorrent/")
method.insert = cfg.download, private|const|string, (cat,"/downloads/")
method.insert = cfg.logs,     private|const|string, (cat,(cfg.basedir),"log/")
method.insert = cfg.logfile,  private|const|string, (cat,(cfg.logs),"rtorrent-",(system.time),".log")
method.insert = cfg.session,  private|const|string, (cat,"/session/")
method.insert = cfg.watch,    private|const|string, (cat,"/watch/")

# Create instance directories
execute.throw = sh, -c, (cat, "mkdir -p ", (cfg.download), " ", (cfg.logs), " ", (cfg.session), " ", (cfg.watch))

# Listening port for incoming peer connections
network.port_range.set = 6881-6881
network.port_random.set = no

# Tracker-less torrent and UDP tracker support
dht.mode.set = auto
dht.port.set = 6881
protocol.pex.set = yes
trackers.use_udp.set = yes

# DHT bootstrap nodes - needed to join the DHT network on startup.
# Without these, rtorrent can only rely on stale session data and
# will show "No DHT nodes available" errors for public torrents.
schedule2 = dht_bootstrap_1, 30, 3600, ((dht.add_node, "dht.transmissionbt.com:6881"))
schedule2 = dht_bootstrap_2, 30, 3600, ((dht.add_node, "router.bittorrent.com:6881"))
schedule2 = dht_bootstrap_3, 30, 3600, ((dht.add_node, "router.utorrent.com:6881"))
schedule2 = dht_bootstrap_4, 30, 3600, ((dht.add_node, "dht.aelitis.com:6881"))

# More aggressive peer settings for public torrents
throttle.max_uploads.set = 100
throttle.max_uploads.global.set = 250
throttle.min_peers.normal.set = 40
throttle.max_peers.normal.set = 100
throttle.min_peers.seed.set = 50
throttle.max_peers.seed.set = 150
trackers.numwant.set = 100

# Enable more peer exchange
protocol.encryption.set = allow_incoming,try_outgoing,enable_retry

# Limits for file handle resources
network.http.max_open.set = 50
network.max_open_files.set = 600
network.max_open_sockets.set = 300

# Memory resource usage
pieces.memory.max.set = 1800M
network.xmlrpc.size_limit.set = 4M

# Basic operational settings
session.path.set = (cat, (cfg.session))
directory.default.set = (cat, (cfg.download))
log.execute = (cat, (cfg.logs), "execute.log")

# Other operational settings
encoding.add = utf8
system.umask.set = 0022
system.cwd.set = (directory.default)
network.http.dns_cache_timeout.set = 25

# Run the rTorrent process as a daemon in the background
system.daemon.set = false

# SCGI socket for communication with Flood
network.scgi.open_local = /var/run/rtorrent/rpc.sock
execute.nothrow = chmod,660,/var/run/rtorrent/rpc.sock

# Watch directories
schedule2 = watch_directory_1, 10, 10, ((load.start, (cat, (cfg.watch), "*.torrent")))
schedule2 = untied_directory, 5, 5, ((stop_untied))

# Close torrents when diskspace is low
schedule2 = monitor_diskspace, 15, 60, ((close_low_diskspace,1000M))
RTORRENT_EOF
fi

echo "==================================="
echo "Configuration complete!"
echo "Starting services..."
echo "==================================="
echo ""
echo "Flood UI will be available at: http://localhost:5000"
echo "rtorrent XML-RPC socket: /var/run/rtorrent/rpc.sock"
echo ""

# Execute the command passed to the container
exec "$@"
