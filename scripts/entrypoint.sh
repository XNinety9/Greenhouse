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

# Check if custom rtorrent.rc exists, if not copy default template
if [ ! -f /config/rtorrent/rtorrent.rc ]; then
    echo "Creating default rtorrent.rc..."
    mkdir -p /config/rtorrent
    cp /defaults/rtorrent.rc /config/rtorrent/rtorrent.rc
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
