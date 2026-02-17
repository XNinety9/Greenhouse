#!/bin/bash
set -e

CONFIG_FILE="/etc/wireguard/wg0.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "No WireGuard configuration found at $CONFIG_FILE, skipping VPN setup."
    exit 0
fi

echo "Starting WireGuard interface wg0..."

# Parse the config file
PRIVATE_KEY=$(awk '/^PrivateKey/ {print $3}' "$CONFIG_FILE")
ADDRESS=$(awk '/^Address/ {print $3}' "$CONFIG_FILE" | tr -d ',')
DNS=$(awk '/^DNS/ {print $3}' "$CONFIG_FILE" | tr -d ',')
PEER_PUBLIC_KEY=$(awk '/^PublicKey/ {print $3}' "$CONFIG_FILE")
ENDPOINT=$(awk '/^Endpoint/ {print $3}' "$CONFIG_FILE")
ALLOWED_IPS=$(awk '/^AllowedIPs/ {print $3}' "$CONFIG_FILE" | tr -d ', ')
PERSISTENT_KEEPALIVE=$(awk '/^PersistentKeepalive/ {print $3}' "$CONFIG_FILE")

# Create the WireGuard interface
ip link add dev wg0 type wireguard

# Configure the interface
wg set wg0 private-key <(echo "$PRIVATE_KEY")
wg set wg0 peer "$PEER_PUBLIC_KEY" endpoint "$ENDPOINT" allowed-ips "$ALLOWED_IPS" persistent-keepalive "${PERSISTENT_KEEPALIVE:-25}"

# Set the IP address
ip address add "$ADDRESS" dev wg0

# Bring up the interface
ip link set wg0 up

echo "WireGuard interface brought up"

# Add routes - need to do this carefully
# Normalize allowed IPs (remove spaces) and check if routing all traffic
if echo "$ALLOWED_IPS" | grep -q '0\.0\.0\.0/0'; then
    echo "Routing all traffic through VPN..."

    # Get the current default route info
    DEFAULT_GW=$(ip route | grep '^default' | awk '{print $3}' | head -1)
    DEFAULT_IF=$(ip route | grep '^default' | awk '{print $5}' | head -1)

    # Add a specific route to the VPN endpoint via the original gateway
    # This ensures VPN traffic itself doesn't go through the VPN
    if [ -n "$DEFAULT_GW" ] && [ -n "$ENDPOINT" ]; then
        VPN_IP=$(echo "$ENDPOINT" | cut -d: -f1)
        echo "Adding route to VPN endpoint $VPN_IP via $DEFAULT_GW"
        ip route add "$VPN_IP/32" via "$DEFAULT_GW" dev "$DEFAULT_IF" 2>/dev/null || true
    fi

    # Delete the old default route
    if [ -n "$DEFAULT_GW" ]; then
        echo "Removing old default route via $DEFAULT_GW"
        ip route del default via "$DEFAULT_GW" 2>/dev/null || true
    fi

    # Set VPN as THE default route (no metric, highest priority)
    echo "Setting VPN as default route..."
    ip route add default dev wg0

    echo "Current routing table:"
    ip route show
else
    # Add specific routes for allowed IPs
    for ip in $(echo "$ALLOWED_IPS" | tr ',' ' '); do
        echo "Adding route for $ip via wg0"
        ip route add "$ip" dev wg0 2>/dev/null || true
    done
fi

# Set DNS if specified
if [ -n "$DNS" ]; then
    echo "Setting DNS servers: $DNS"
    # Handle multiple DNS servers (comma or space separated)
    DNS_CLEAN=$(echo "$DNS" | tr ',' ' ')
    > /etc/resolv.conf
    for dns_server in $DNS_CLEAN; do
        echo "nameserver $dns_server" >> /etc/resolv.conf
    done
fi

echo "WireGuard interface wg0 is up"
echo "Interface configuration:"
wg show wg0

# Wait a moment for routes to settle
sleep 2

# Test DNS resolution through VPN
echo "Testing DNS resolution..."
if nslookup google.com > /dev/null 2>&1; then
    echo "DNS resolution working"
else
    echo "WARNING: DNS resolution may not be working properly"
fi

# Keep the script running
tail -f /dev/null
