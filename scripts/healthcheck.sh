#!/bin/bash

# Check if rtorrent is running
if ! pgrep rtorrent > /dev/null; then
    echo "rtorrent is not running"
    exit 1
fi

# Check if Flood is responding
if ! curl -sf http://localhost:5000 > /dev/null; then
    echo "Flood UI is not responding"
    exit 1
fi

# Check if rtorrent socket exists
if [ ! -S /var/run/rtorrent/rpc.sock ]; then
    echo "rtorrent RPC socket does not exist"
    exit 1
fi

# Check if WireGuard is configured and running
if [ -f /etc/wireguard/wg0.conf ]; then
    if ! ip link show wg0 > /dev/null 2>&1; then
        echo "WireGuard interface is not up"
        exit 1
    fi
fi

echo "All services healthy"
exit 0
