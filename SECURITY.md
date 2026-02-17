# Security Guidelines

## Critical Security Considerations

### 1. VPN Configuration

**ALWAYS use a VPN when running Greenhouse.** The container includes a killswitch to prevent IP leaks, but proper configuration is essential.

#### Killswitch Features
- Blocks all non-VPN traffic by default
- Allows only local network access for Flood UI
- Automatically configured when WireGuard config is present
- Prevents accidental IP exposure if VPN disconnects

#### Testing the Killswitch

Verify the killswitch is working:

```bash
# Check your IP (should show VPN IP)
docker exec greenhouse curl -s ifconfig.me

# Disable VPN temporarily
docker exec greenhouse wg-quick down wg0

# Try to access internet (should fail)
docker exec greenhouse curl -s ifconfig.me --max-time 5
# This should timeout or fail

# Re-enable VPN
docker exec greenhouse wg-quick up wg0
```

### 2. WireGuard Private Key Security

Your `wg0.conf` contains your **private key**. Protect it:

- ✅ Store it with restricted permissions (600)
- ✅ Never commit it to version control
- ✅ Never share it with anyone
- ✅ Keep backups encrypted
- ❌ Don't share your config online
- ❌ Don't store it in public repositories

The container automatically sets proper permissions (600) on the WireGuard config.

### 3. Flood UI Access

#### Default Configuration
- Flood runs **without authentication** by default
- Only accessible on your local network
- **Do NOT expose port 5000 to the internet without authentication**

#### Enabling Authentication

1. Edit `config/supervisord.conf`:
   ```ini
   command=/usr/bin/flood --host=0.0.0.0 --port=5000 --rundir=/config/flood --auth=default --rtsocket=/var/run/rtorrent/rpc.sock
   ```

2. Restart the container:
   ```bash
   docker-compose restart
   ```

3. Create a user account on first access

#### Secure Remote Access

If you need remote access to Flood:

**Option 1: VPN to your network**
- Use WireGuard/OpenVPN to access your home network
- Access Flood on the local IP

**Option 2: Reverse proxy with authentication**
- Use nginx, Traefik, or Caddy
- Enable HTTPS with Let's Encrypt
- Add authentication layer
- Use strong passwords

**Option 3: SSH tunnel**
```bash
ssh -L 5000:localhost:5000 user@your-server
# Access via http://localhost:5000
```

### 4. Docker Security

#### Required Capabilities
The container needs these capabilities for VPN:
- `NET_ADMIN`: Required for WireGuard
- `SYS_MODULE`: Required for kernel modules

These are necessary but powerful capabilities. Only run this container on trusted systems.

#### Container Isolation
- Container runs services as non-root user `rtorrent` (UID 1000)
- Only the entrypoint and VPN setup run as root
- Services are isolated using supervisord

#### Host Security
Ensure your Docker host is secure:
- Keep Docker updated
- Use firewall rules to restrict access
- Monitor container logs regularly
- Use Docker's user namespacing if possible

### 5. Network Security

#### Port Exposure
Only expose necessary ports:
- 5000 (Flood UI) - Local network only
- 6881 (rtorrent) - Required for incoming connections

#### Firewall Rules
On your host, restrict access:

```bash
# Allow only local network to Flood UI
iptables -A INPUT -p tcp --dport 5000 -s 192.168.0.0/16 -j ACCEPT
iptables -A INPUT -p tcp --dport 5000 -j DROP
```

### 6. DNS Leaks

The container uses custom DNS servers (1.1.1.1, 8.8.8.8 by default) to prevent DNS leaks.

Test for DNS leaks:
```bash
docker exec greenhouse curl -s https://www.dnsleaktest.com/
```

Or use your VPN provider's DNS leak test.

### 7. Legal Considerations

#### Important Warnings
- Respect copyright laws in your jurisdiction
- Only download content you have the right to access
- Understand your VPN provider's logging policies
- Read and comply with your ISP's terms of service
- Some countries have strict laws regarding torrenting

#### Best Practices
- Use VPN from a privacy-focused provider
- Choose providers with a no-logs policy
- Understand the legal implications in your region
- Keep the VPN connected at all times when torrenting

### 8. Update and Maintenance

#### Regular Updates
Keep the container updated:

```bash
# Rebuild with latest packages
docker-compose build --no-cache
docker-compose up -d
```

#### Security Patches
- Alpine Linux provides security updates
- Rebuild periodically for patches
- Monitor security advisories

#### Log Monitoring
Regularly check logs for suspicious activity:
```bash
docker-compose logs -f
docker exec greenhouse tail -f /var/log/supervisor/*.log
```

### 9. Backup and Recovery

#### What to Backup
- WireGuard configuration (`config/wireguard/wg0.conf`)
- rtorrent configuration (`config/rtorrent/rtorrent.rc`)
- Session data (for resume capability)
- Flood settings (`config/flood/`)

#### What NOT to Backup
- Downloaded files (too large)
- Logs (temporary data)
- Socket files

### 10. Incident Response

If you suspect a security breach:

1. **Immediately stop the container**
   ```bash
   docker-compose down
   ```

2. **Check for IP leaks**
   - Review logs for VPN disconnections
   - Check if killswitch was active

3. **Rotate credentials**
   - Generate new WireGuard keys
   - Change Flood password if exposed

4. **Investigate**
   - Review container logs
   - Check host system logs
   - Look for unauthorized access

5. **Secure the system**
   - Update all software
   - Review firewall rules
   - Rebuild container from scratch

## Security Checklist

Before running in production:

- [ ] WireGuard config is properly configured
- [ ] Killswitch is tested and working
- [ ] Flood authentication is enabled (if needed)
- [ ] Only necessary ports are exposed
- [ ] Host firewall is configured
- [ ] DNS leak test passed
- [ ] Backups are encrypted and secure
- [ ] Legal considerations are understood
- [ ] Monitoring is in place

## Reporting Security Issues

If you find a security vulnerability in this Docker configuration, please:
1. Do NOT open a public issue
2. Contact the maintainer privately
3. Provide details of the vulnerability
4. Allow time for a fix before disclosure

## Resources

- [WireGuard Security](https://www.wireguard.com/formal-verification/)
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)

---

**Remember**: Security is a shared responsibility. This container provides the tools, but proper configuration and maintenance are essential.
