# Quick Start Guide

Get Greenhouse running in 5 minutes!

## Prerequisites

- Docker 20.10+
- Docker Compose 1.29+
- Linux with WireGuard kernel support (5.6+)
- WireGuard configuration from your VPN provider

## Step 1: Get Your Files

All files are in the `greenhouse` directory.

## Step 2: Configure WireGuard

1. Get a WireGuard config from your VPN provider (Mullvad, ProtonVPN, etc.)
2. Save it as `config/wireguard/wg0.conf`

Example:
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

## Step 3: Build and Start

```bash
cd greenhouse
docker-compose build
docker-compose up -d
```

## Step 4: Access Flood UI

Open your browser: **http://localhost:5000**

## Step 5: Verify VPN

```bash
# Check VPN status
docker exec greenhouse wg show

# Check IP (should show VPN IP)
docker exec greenhouse curl -s ifconfig.me
```

## That's It!

You now have a fully functional Greenhouse seedbox with:
- ✅ rtorrent running
- ✅ Flood UI accessible
- ✅ VPN protection with killswitch
- ✅ Auto-start on boot

## Quick Commands

```bash
# View logs
docker-compose logs -f

# Restart container
docker-compose restart

# Stop container
docker-compose down

# Shell access
docker exec -it seedbox /bin/bash
```

## Adding Torrents

**Method 1**: Flood UI
- Go to http://localhost:5000
- Click "+" button
- Add torrent URL or file

**Method 2**: Watch folder
- Copy .torrent files to `./watch/`
- They'll auto-load

## Troubleshooting

**VPN not connecting?**
- Check your `wg0.conf` file
- View logs: `docker-compose logs greenhouse`

**Can't access Flood?**
- Wait 30 seconds after startup
- Check: `docker ps` to ensure container is running
- Check: `docker-compose logs flood`

**Need help?**
- Read the full README.md
- Check SECURITY.md for best practices

## What's Next?

1. Read README.md for detailed configuration
2. Review SECURITY.md for security best practices
3. Customize rtorrent.rc for your needs
4. Set up authentication for Flood (if needed)

---

**Important**: Always keep your VPN connected when torrenting!
