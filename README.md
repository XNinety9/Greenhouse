# Greenhouse

A lightweight Docker image for a complete seedbox solution based on Alpine Linux, featuring:
- **jesec's rtorrent** - Modern fork of rtorrent with improvements
- **Flood UI** - Beautiful modern web interface for rtorrent
- **WireGuard VPN** - Fast, secure VPN with killswitch protection

## Features

- 🪶 **Lightweight**: Built on Alpine Linux (~200MB image size)
- 🔒 **Secure**: WireGuard VPN with killswitch to prevent IP leaks
- 🎨 **Modern UI**: Clean, responsive Flood interface
- 📦 **All-in-one**: Complete seedbox solution in a single container
- 🔄 **Auto-restart**: Supervisord manages all services with automatic recovery
- 🏥 **Health checks**: Built-in monitoring for all services

## Quick Start

### 1. Build the Image

```bash
docker-compose build
```

Or build manually:

```bash
docker build -t greenhouse:latest .
```

### 2. Configure WireGuard VPN

Create your WireGuard configuration file at `./config/wireguard/wg0.conf`:

```ini
[Interface]
PrivateKey = YOUR_PRIVATE_KEY
Address = 10.x.x.x/32
DNS = 1.1.1.1

[Peer]
PublicKey = SERVER_PUBLIC_KEY
Endpoint = vpn.example.com:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

**Note**: Replace with your actual VPN provider's configuration.

### 3. Start the Container

```bash
docker-compose up -d
```

Or manually:

```bash
docker run -d \
  --name greenhouse \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  -p 5000:5000 \
  -p 6881:6881 \
  -p 6881:6881/udp \
  -v $(pwd)/config:/config \
  -v $(pwd)/downloads:/downloads \
  -v $(pwd)/watch:/watch \
  -v /lib/modules:/lib/modules:ro \
  greenhouse:latest
```

### 4. Access Flood UI

Open your browser and navigate to: **http://localhost:5000**

## Directory Structure

```
greenhouse/
├── Dockerfile
├── docker-compose.yml
├── config/
│   ├── rtorrent.rc          # rtorrent configuration
│   └── supervisord.conf     # Service management
├── scripts/
│   ├── entrypoint.sh        # Container startup script
│   └── healthcheck.sh       # Health monitoring
└── README.md
```

After first run, your data will be organized as:

```
./config/
├── rtorrent/
│   ├── rtorrent.rc          # rtorrent configuration
│   └── log/                 # rtorrent logs
├── flood/                   # Flood data directory
└── wireguard/
    └── wg0.conf            # Your WireGuard config (you create this)

./downloads/                 # Downloaded torrents
./watch/                     # Drop .torrent files here for auto-loading
./session/                   # rtorrent session data
```

## Configuration

### WireGuard VPN

1. Obtain a WireGuard configuration from your VPN provider
2. Save it as `./config/wireguard/wg0.conf`
3. Restart the container

The container includes a **killswitch** that will block all non-VPN traffic, preventing IP leaks.

### rtorrent

Edit `./config/rtorrent/rtorrent.rc` to customize rtorrent settings:
- Download limits
- Upload limits
- Port configuration
- DHT settings
- And more

Default ports:
- **6881**: Incoming connections (already configured)

### Flood UI

Flood runs with authentication disabled by default for local use. To enable authentication, modify the supervisord.conf file:

```ini
command=/usr/bin/flood --host=0.0.0.0 --port=5000 --rundir=/config/flood --auth=default --rtsocket=/var/run/rtorrent/rpc.sock
```

Then restart the container.

## Usage

### Adding Torrents

**Method 1**: Via Flood UI
- Open http://localhost:5000
- Click the "+" button
- Add torrent URL or upload .torrent file

**Method 2**: Via Watch Directory
- Copy .torrent files to `./watch/` directory
- rtorrent will automatically load and start them

### Monitoring

Check container logs:
```bash
docker-compose logs -f
```

Check VPN connection:
```bash
docker exec greenhouse wg show
```

Check your IP address (should show VPN IP):
```bash
docker exec greenhouse curl -s ifconfig.me
```

## Troubleshooting

### VPN Not Connecting

1. Verify your `wg0.conf` is properly formatted
2. Check container logs: `docker-compose logs greenhouse`
3. Ensure your VPN provider's endpoint is reachable
4. Try testing the config outside Docker first

### Can't Access Flood UI

1. Check if container is running: `docker ps`
2. Check port mapping: `docker port greenhouse`
3. Check container health: `docker inspect greenhouse | grep Health`
4. Check Flood logs: `docker exec greenhouse cat /var/log/supervisor/flood.log`

### rtorrent Not Starting

1. Check rtorrent logs: `docker exec greenhouse cat /var/log/supervisor/rtorrent.log`
2. Verify configuration: `docker exec greenhouse rtorrent -n -o import=/config/rtorrent/rtorrent.rc`
3. Check permissions on directories

### Killswitch Issues

If you need to disable the killswitch temporarily for debugging:

```bash
docker exec greenhouse iptables -F
docker exec greenhouse iptables -P INPUT ACCEPT
docker exec greenhouse iptables -P FORWARD ACCEPT
docker exec greenhouse iptables -P OUTPUT ACCEPT
```

**Warning**: This disables leak protection!

## Advanced Configuration

### Custom DNS

Edit `docker-compose.yml`:

```yaml
dns:
  - 1.1.1.1
  - 9.9.9.9
```

### Port Forwarding

If your VPN provider supports port forwarding, add the forwarded port to your configuration:

1. Update `rtorrent.rc`:
   ```
   network.port_range.set = YOUR_FORWARDED_PORT-YOUR_FORWARDED_PORT
   ```

2. Expose the port in docker-compose.yml:
   ```yaml
   ports:
     - "YOUR_FORWARDED_PORT:YOUR_FORWARDED_PORT"
     - "YOUR_FORWARDED_PORT:YOUR_FORWARDED_PORT/udp"
   ```

### Resource Limits

Add to docker-compose.yml:

```yaml
deploy:
  resources:
    limits:
      cpus: '2'
      memory: 2G
    reservations:
      memory: 512M
```

## Security Notes

1. **Always use a VPN** when torrenting to protect your privacy
2. The killswitch prevents accidental IP leaks if VPN disconnects
3. Flood UI has no authentication by default - only expose on trusted networks
4. Keep your WireGuard config secure (it contains your private key)
5. Regularly update the container for security patches

## Requirements

- Docker 20.10+
- Docker Compose 1.29+
- Kernel with WireGuard support (Linux 5.6+)
- `NET_ADMIN` capability for VPN

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 5000 | TCP | Flood Web UI |
| 6881 | TCP/UDP | rtorrent incoming connections |
| 9091 | TCP | rtorrent XML-RPC (internal only) |

## Performance Tips

1. **SSD Storage**: Use SSD for session directory for better performance
2. **Memory**: Allocate at least 1GB RAM for smooth operation
3. **Network**: Use gigabit connection for best speeds
4. **rtorrent tuning**: Adjust `pieces.memory.max` in rtorrent.rc based on available RAM

## Support

For issues:
- Check logs: `docker-compose logs -f`
- Verify VPN connection: `docker exec greenhouse wg show`
- Test without VPN first to isolate issues
- Check rtorrent configuration syntax

## License

This Docker configuration is provided as-is for personal use. Please respect copyright laws and your VPN provider's terms of service.

## Credits

- rtorrent: https://github.com/jesec/rtorrent
- Flood: https://github.com/jesec/flood
- WireGuard: https://www.wireguard.com/
- Alpine Linux: https://alpinelinux.org/
