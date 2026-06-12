# WireGuard VPN Administration Guide

This guide covers how to manage the WireGuard VPN running on Hetzner Cloud via the `wg-easy` web interface.

## Quick Start

### 1. Access the Admin Dashboard

The admin dashboard is only available on `localhost:51821` (not exposed to the internet). Use SSH port forwarding to access it:

```bash
# Substitute your VPS IP
ssh -L 127.0.0.1:51821:127.0.0.1:51821 root@<your-vps-ip>

# Then open in your browser:
# http://127.0.0.1:51821
```

The dashboard is protected with the admin password you set in `terraform.auto.tfvars`.

### 2. Download the Auto-Generated Admin Config

After Terraform applies, the admin peer (10.0.0.2) is automatically generated and available for download:

```bash
# Substitute your VPS IP
scp root@<your-vps-ip>:/root/wireguard-admin.conf ./admin-wg0.conf
```

This config is for your home server connecting to the VPN. Import it into your WireGuard client:

- **WireGuard on Linux/Mac/Windows**: File → Import from file → Select `admin-wg0.conf`
- **WireGuard on Mobile**: Scan the QR code in the admin dashboard, or import the file

### 3. Connect and Test

Once imported, activate the VPN connection. You should:

- Be assigned IP `10.0.0.2` within the VPN
- See the VPN interface `wg0` as active
- Be able to ping other peers once they're added

To verify connectivity from your home server:

```bash
# Check WireGuard status
sudo wg show

# Ping the VPN hub
ping 10.0.0.1

# Your home server is accessible to VPN peers at:
# 10.0.0.2 (your VPN IP)
```

---

## Adding Peers (India Developers)

### Via Web Dashboard (Recommended)

1. Access the admin dashboard (see Step 1 above)
2. Scroll down to "Clients"
3. Click **"Add Peer"** button
4. Configure:
   - **Name**: Developer name (e.g., `india-dev-alice`)
   - **Allowed IPs**: `10.0.0.3/32` (their VPN IP)
   - **DNS**: `8.8.8.8, 1.1.1.1` (or leave default)
5. Click **"Add"**
6. A QR code appears — developer scans it, or download `.conf` and send securely

### Split Tunnel Configuration (For India Devs)

By default, wg-easy creates peers with `AllowedIPs = 10.0.0.0/24` (all VPN traffic routed through the tunnel).

For **split tunnel** (only 10.0.0.2/32 = your home server goes through VPN):

1. After adding a peer, click **"Edit"** (pencil icon)
2. Change **Allowed IPs** from `10.0.0.0/24` to `10.0.0.2/32`
3. Click **"Update"**
4. Developer must re-download/re-scan the updated config

This ensures India devs' regular internet traffic uses their local ISP, reducing Hetzner egress costs and lowering latency for local browsing.

---

## Peer Configuration Examples

### Admin Peer (Home Server) — Full Tunnel

```
Name:           admin
Internal IP:    10.0.0.2/32
AllowedIPs:     10.0.0.0/24           ← Can reach any peer (hub routes to others)
PersistentKeepalive: 25               ← Keeps connection alive through home NAT
```

This peer can reach the hub (10.0.0.1) and any other peer on the VPN.

### Developer Peer (India) — Split Tunnel

```
Name:           india-dev-alice
Internal IP:    10.0.0.3/32
AllowedIPs:     10.0.0.2/32           ← Only routes traffic destined for home server
PersistentKeepalive: 0                ← No keepalive needed (they initiate when connecting)
```

This peer **only** sends traffic destined for 10.0.0.2 (your home server) through the VPN. Everything else uses their local ISP.

---

## Downloading Client Configs

From the admin dashboard:

1. Find the peer under "Clients"
2. Click the **"Download"** icon (down arrow) next to their name
3. A `.conf` file is downloaded
4. Send to the developer securely (e.g., encrypted email, Slack with thread expiry)

Developers import the file into their WireGuard client and connect.

---

## Troubleshooting

### Peer Can't Connect

1. Verify the peer config has:
   - Valid `Endpoint = <your-vps-ip>:51820`
   - Valid `PublicKey` (matches what's in the dashboard)
   - Correct `PrivateKey` (private keys must match what's on their device)

2. Check firewall:
   ```bash
   sudo ufw status | grep 51820
   # Should show: 51820/udp ALLOW
   ```

3. Check WireGuard status on the VPS:
   ```bash
   docker exec wg-easy wg show
   ```

4. Check logs:
   ```bash
   docker logs wg-easy | tail -20
   ```

### Using vpn.skillrev.in Instead of Raw IP

If you set up the DNS A record in Squarespace, peers can use the domain name:

```
# Instead of this (raw IP):
Endpoint = 1.2.3.4:51820

# Use this (domain name):
Endpoint = vpn.skillrev.in:51820
```

**Benefits:**
- Scales without reissuing configs (just update DNS A record)
- Easier to remember and share
- More professional appearance

When you recreate the VPS with a different IP, just:
1. Get new IP from `terraform outputs`
2. Update the DNS A record in Squarespace
3. All peer configs work without changes (they resolve vpn.skillrev.in to the new IP)

### Peer Connected but Can't Reach Home Server

1. Verify the home server is connected and has `10.0.0.2/32` as its IP:
   ```bash
   # On home server
   sudo wg show
   ```

2. Ensure home server has `PersistentKeepalive = 25` (keeps connection alive)

3. On home server, check Ollama is listening on all interfaces:
   ```bash
   # Should show listening on 0.0.0.0 or specific interface
   ss -tlnp | grep 11434
   ```

4. From developer's machine, test connectivity:
   ```bash
   ping 10.0.0.2
   curl http://10.0.0.2:11434/api/tags  # Test Ollama
   ```

### Admin Dashboard Not Accessible

1. Verify SSH tunnel is open:
   ```bash
   lsof -i :51821
   # Should show the SSH tunnel
   ```

2. If tunnel dropped, restart it:
   ```bash
   ssh -L 127.0.0.1:51821:127.0.0.1:51821 root@<your-vps-ip>
   ```

3. Check wg-easy container is running:
   ```bash
   docker ps | grep wg-easy
   ```

---

## Advanced: Managing Configs on Persistent Volume

WireGuard configs are stored at `/mnt/persist/wireguard/` on the VPS. They survive VM teardowns.

### Backup Configuration

```bash
# From your local machine:
scp -r root@<your-vps-ip>:/mnt/persist/wireguard/ ./wireguard-backup/
```

### Restore Configuration (After VM Recreate)

If you rebuild the VPS with the same persistent volume:

```bash
# SSH to the new VPS
ssh root@<new-vps-ip>

# Navigate to the WireGuard directory
cd /mnt/persist/wireguard/

# wg-easy will auto-load configs from the existing config/ directory
docker compose up -d
```

---

## VPN Network Topology

```
                    ┌─────────────────────────┐
                    │  Hetzner Cloud VPS      │
                    │  (Hub)                  │
                    │  10.0.0.1               │
                    │  Port: 51820/UDP        │
                    └──────────┬──────────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
         ┌────▼────┐      ┌────▼────┐     ┌────▼────┐
         │ Home    │      │  India  │     │  India  │
         │ Server  │      │  Dev 1  │     │  Dev 2  │
         │ (10.0.  │      │ (10.0.  │     │ (10.0.  │
         │ 0.2)    │      │ 0.3)    │     │ 0.4)    │
         │ Full    │      │ Split   │     │ Split   │
         │ Tunnel  │      │ Tunnel  │     │ Tunnel  │
         └─────────┘      └─────────┘     └─────────┘
```

---

## Support

For issues with wg-easy itself, see: https://github.com/wg-easy/wg-easy

For WireGuard protocol questions: https://www.wireguard.com/
