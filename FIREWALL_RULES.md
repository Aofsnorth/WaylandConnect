# Firewall Configuration for WaylandConnect

## Required Ports

WaylandConnect requires the following ports to be open on your Linux PC:

| Port | Protocol | Purpose | Direction |
|------|----------|---------|-----------|
| **12345** | TCP | Main connection (TLS) | Inbound |
| **12346** | UDP | Device discovery (broadcast) | Inbound |

## Linux Firewall Configuration

### UFW (Ubuntu/Debian)

```bash
# Allow TCP port 12345 for main connection
sudo ufw allow 12345/tcp

# Allow UDP port 12346 for device discovery
sudo ufw allow 12346/udp

# Reload firewall
sudo ufw reload

# Check status
sudo ufw status
```

### Firewalld (Fedora/RHEL/CentOS)

```bash
# Allow TCP port 12345
sudo firewall-cmd --permanent --add-port=12345/tcp

# Allow UDP port 12346
sudo firewall-cmd --permanent --add-port=12346/udp

# Reload firewall
sudo firewall-cmd --reload

# Check status
sudo firewall-cmd --list-ports
```

### iptables (Generic)

```bash
# Allow TCP port 12345
sudo iptables -A INPUT -p tcp --dport 12345 -j ACCEPT

# Allow UDP port 12346
sudo iptables -A INPUT -p udp --dport 12346 -j ACCEPT

# Save rules (Ubuntu/Debian)
sudo iptables-save | sudo tee /etc/iptables/rules.v4

# Or (RHEL/CentOS)
sudo service iptables save
```

## Troubleshooting

### Check if ports are listening

```bash
# Check if backend is listening on port 12345
sudo netstat -tlnp | grep 12345

# Check if UDP discovery is active on port 12346
sudo netstat -ulnp | grep 12346
```

### Test UDP broadcast manually

```bash
# Send a test UDP broadcast
echo -n "discovery" | nc -u -b -w1 255.255.255.255 12346

# Or using socat
echo -n "discovery" | socat - UDP4-DATAGRAM:255.255.255.255:12346,broadcast
```

### Common Issues

1. **Android can't find PC during scanning**
   - ✅ Ensure firewall allows UDP port 12346
   - ✅ Verify backend is running: `ps aux | grep wayland_connect_backend`
   - ✅ Check both devices are on same WiFi network
   - ✅ Check router allows broadcast packets (some routers block this)

2. **Connection refused on port 12345**
   - ✅ Ensure backend is running
   - ✅ Firewall allows TCP port 12345
   - ✅ Check IP address is correct

3. **Discovery works but connection fails**
   - ✅ Check TLS certificate hasn't changed
   - ✅ Reset pairing on both devices
