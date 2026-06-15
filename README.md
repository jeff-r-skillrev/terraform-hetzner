# WireGuard VPN on Hetzner Cloud

Terraform-managed WireGuard VPN server on Hetzner Cloud for secure, persistent access to home-based services (like Ollama) from remote locations (e.g., India). Hub-and-spoke topology with split tunneling for low bandwidth costs.

## Why This Project?

You run compute-intensive services at home (e.g., Ollama for LLM inference) that you want to access from remote offices or travel. **Direct access over the internet is insecure** — you'd expose your home IP and services to the world. **A cloud-based VPN hub solves this:**

- **Secure tunnel**: All traffic between home and remote devs is encrypted via WireGuard
- **Persistent endpoint**: A stable cloud IP replaces your dynamic home IP; devs connect to the VPN hub, not directly to your home
- **Low cost**: Split tunneling means devs use their local ISP for regular traffic; only internal service access routes through the VPN (minimal bandwidth)
- **Infrastructure-as-code**: Terraform automates provisioning, so you can tear down and recreate the server without losing configs or IP address
- **Self-contained**: Uses only Hetzner Cloud (VPS + persistent volume) and wg-easy (open-source Docker image); no external VPN service subscriptions

This is ideal for small teams, hobby projects, or when you need both **security** and **cost efficiency**.

---

## Architecture Overview

```
                    ┌─────────────────────────────────┐
                    │  Hetzner Cloud VPS (Hub)        │
                    │  • WireGuard on 51820/UDP       │
                    │  • Internal IP: 10.0.0.1        │
                    │  • wg-easy web UI: localhost    │
                    │  • Cost: ~$5-10/month           │
                    └────────────────┬────────────────┘
                                     │ (VPN Tunnel)
                    ┌────────────────┼────────────────┐
                    │                │                │
        ┌───────────▼────┐  ┌────────▼────────┐ ┌────▼──────────┐
        │ Home Desktop   │  │ India Dev 1     │ │ India Dev 2   │
        │ (Your House)   │  │ (Home Network)  │ │ (Home Network)│
        │                │  │                 │ │               │
        │ • IP: 10.0.0.2 │  │ • IP: 10.0.0.3  │ │ • IP: 10.0.0.4│
        │ • Full tunnel  │  │ • Split tunnel  │ │ • Split tunnel│
        │ • Persistent   │  │ • Auto-add      │ │ • Auto-add    │
        │   Keepalive    │  │ • Only sees     │ │ • Only sees   │
        │ • Ollama:11434 │  │   home server   │ │   home server │
        └────────────────┘  └─────────────────┘ └───────────────┘
        
        Split tunnel = traffic for 10.0.0.2 goes via VPN,
        everything else uses their local ISP (low cost, low latency)
```

**Cost Summary**

| Item | Cost |
|---|---|
| Hetzner Cloud VM (cpx21: 2vCPU, 4GB RAM) | ~$5-10/month |
| Persistent Block Storage (10-40GB) | ~$1-5/month |
| Reserved IPv4 (stable endpoint) | $0 while attached |
| **Total** | **~$6-15/month** |

---

## Quick Start

### Prerequisites

- **Terraform** >= 1.6 — `brew install terraform`
- **Hetzner Cloud API token** — [console.hetzner.cloud](https://console.hetzner.cloud) → project → Security → API Tokens
- **SSH key pair** — `ssh-keygen -t ed25519` (if you don't have one)
- **WireGuard client** — [wireguard.com/install](https://www.wireguard.com/install/)

### 1. Set up Terraform variables

```bash
cd hcloud-terraform/infra
cp terraform.auto.tfvars.example terraform.auto.tfvars
```

Edit `terraform.auto.tfvars`:

```hcl
hcloud_token           = "your-hetzner-api-token"
ssh_public_key         = "ssh-ed25519 AAAA... you@yourmachine"
wg_admin_password      = "choose-a-strong-password"
owner_tag              = "your-name"
vm_name                = "wireguard-vpn"
server_type            = "cpx21"
location               = "ash"  # or "hil" (US), "nbg1" (Germany), etc.
use_reserved_ip        = true
wg_server_port         = 51820
```

### 2. Provision the VPN server

```bash
terraform init
terraform plan
terraform apply
```

Terraform outputs:
- `server_ip` — The VPS public IP
- `wg_easy_admin_tunnel` — SSH command to access admin UI
- `wg_config_download` — SCP command to download your peer config
- `wireguard_endpoint` — Endpoint for client configs (e.g., `1.2.3.4:51820`)
- `wg_next_steps` — Quick reference guide

### 3. Download your home server config

After the VM is up (cloud-init takes ~3 minutes):

```bash
# Copy-paste the command from Terraform outputs
scp root@<your-vps-ip>:/root/wireguard-admin.conf ./admin-wg0.conf
```

This config is pre-generated and ready to use. It includes:
- Your internal VPN IP: `10.0.0.2`
- The server's public key
- PersistentKeepalive=25 (keeps connection alive through NAT)

### 3b. (Recommended) Set up DNS for stable endpoint

Before distributing configs to developers, set up a DNS record so you can scale/recreate the server later without breaking everyone's configs:

**In Squarespace (or your DNS provider):**
1. Go to Domains → skillrev.in → DNS settings
2. Add an A record:
   - Name: `vpn`
   - Value: `<your-vps-ip>` (from Terraform output)
   - TTL: 3600
3. Save and wait 5-30 minutes for propagation

Now all peer configs can use `vpn.skillrev.in:51820` instead of the raw IP. If you ever need to scale up or migrate servers, just update the A record — no peer reconfigs needed.

### 4. Connect your home server

**On Linux:**

```bash
# Install WireGuard if not already installed
sudo apt install wireguard wireguard-tools

# Import the config
sudo cp admin-wg0.conf /etc/wireguard/wg0.conf
sudo chmod 600 /etc/wireguard/wg0.conf

# Bring up the interface
sudo wg-up wg0
# or
sudo wg-quick up ./admin-wg0.conf

# Verify
sudo wg show
```

**On macOS/Windows/iOS/Android:**
- Open WireGuard client
- File → Import from file → Select `admin-wg0.conf`
- Click **Activate**

### 5. Test the connection

```bash
# Your VPN IP should be 10.0.0.2
ip addr show wg0

# Ping the VPN hub
ping 10.0.0.1

# Ping from a remote developer (once they're added)
ping 10.0.0.3
```

---

## Adding Remote Developers

### Via Web Dashboard (Recommended)

1. Access the admin UI:
   ```bash
   # Copy-paste from Terraform outputs
   ssh -L 127.0.0.1:51821:127.0.0.1:51821 root@<your-vps-ip>
   ```
   Then open **http://127.0.0.1:51821** in your browser

2. Login with the password from `terraform.auto.tfvars`

3. Click **"Add Peer"**:
   - **Name**: `india-dev-alice`
   - **Allowed IPs**: `10.0.0.3/32` (their VPN IP)
   - Leave DNS and other fields at defaults

4. A QR code appears. Developer scans it with WireGuard mobile app, or you send them the downloaded `.conf` file securely.

### Split Tunnel (For Devs)

By default, all traffic goes through the VPN. For **split tunnel** (only Ollama traffic uses VPN):

1. Click **Edit** on the peer
2. Change **AllowedIPs** from `10.0.0.0/24` to `10.0.0.2/32`
3. **Update**
4. Developer re-downloads the config

This ensures:
- Devs' regular internet uses their local ISP (fast, cheap)
- Only traffic destined for your home server (10.0.0.2) uses the Hetzner VPN
- Ollama remains accessible from India via secure tunnel

---

## Home Server Setup

Your home server (10.0.0.2) will connect 24x7 to the Hetzner hub. It needs to:

1. **Run WireGuard** (see "Connect your home server" above)

2. **Make Ollama accessible to VPN peers**:
   ```bash
   # On your home server, configure Ollama to listen on all interfaces
   export OLLAMA_HOST=0.0.0.0:11434
   ollama serve
   
   # Or set it in systemd service:
   # /etc/systemd/system/ollama.service
   # Environment="OLLAMA_HOST=0.0.0.0:11434"
   ```

3. **(Optional) Firewall India devs to Ollama only**:
   ```bash
   # Allow VPN subnet to reach Ollama, deny everything else
   sudo ufw allow from 10.0.0.0/24 to any port 11434
   sudo ufw deny to 127.0.0.1 port 11434  # Deny local to prevent accidental exposure
   ```

4. **Verify connectivity** from India:
   ```bash
   # From India dev's machine (after connecting to VPN)
   curl http://10.0.0.2:11434/api/tags
   ```

---

## Managing the VPN

### Common Tasks

| Task | Command |
|---|---|
| SSH to the VPS | `ssh root@<your-vps-ip>` |
| Access admin UI | `ssh -L 127.0.0.1:51821:127.0.0.1:51821 root@<your-vps-ip>` → http://127.0.0.1:51821 |
| View WireGuard status | `ssh root@<your-vps-ip> "docker exec wg-easy wg show"` |
| View Docker logs | `ssh root@<your-vps-ip> "docker logs wg-easy"` |
| Restart WireGuard | `ssh root@<your-vps-ip> "docker restart wg-easy"` |
| Backup configs | `scp -r root@<your-vps-ip>:/mnt/persist/wireguard/ ./wireguard-backup/` |

### Persistent Volume

All WireGuard configs are stored on a persistent Hetzner volume at `/mnt/persist/wireguard/`. This means:

- **Survives VM teardown**: Destroy and recreate the VM, configs persist
- **Quick spinup**: VM comes back up with the same peer configs (no manual re-creation)
- **Backup**: Configs are automatically isolated from the VM's ephemeral disk

### Scaling Down / Destroying

```bash
terraform destroy
```

This removes the VM but **keeps the persistent volume**. Next time:

```bash
terraform apply
```

The VM comes back up in ~2-5 minutes with the same WireGuard configs (no re-configuration needed).

---

## Architecture & File Structure

The project is organized into two Terraform modules: **shared** (persistent state) and **infra** (ephemeral compute). This separation means you can destroy and recreate the VPS without losing WireGuard peer configurations.

```
hcloud-terraform/
├── shared/                      # Persistent Hetzner volume (data layer)
│   ├── main.tf                  # Defines the persistent volume resource
│   ├── variables.tf             # Volume size, labels, etc.
│   └── outputs.tf               # Volume ID for infra to mount
│   
│   Purpose: Create a persistent block storage volume that survives
│   VM teardowns. All WireGuard configs are stored here.
│
├── infra/                       # Ephemeral VPS + provisioning (compute layer)
│   ├── main.tf                  # Server resource, network, SSH key, firewall rules
│   ├── variables.tf             # Hetzner token, SSH pubkey, VPN params (port, admin password)
│   ├── outputs.tf               # Server IP, SSH tunnel command, config download command
│   ├── cloud-init.yaml.tftpl    # First-boot provisioning template
│   │   ├── Installs Docker and WireGuard tools
│   │   ├── Generates WireGuard server keys
│   │   ├── Starts wg-easy container with admin UI
│   │   ├── Auto-generates the admin peer (10.0.0.2)
│   │   ├── Hashes the admin password (bcrypt)
│   │   └── Mounts the persistent volume at /mnt/persist
│   │
│   ├── terraform.auto.tfvars.example  # Template for your secrets (token, SSH key, password)
│   └── terraform.tfstate              # Local state (git-ignored for safety)
│
├── utils/
│   └── wireguard/
│       └── README.md            # Detailed operational guide (admin tasks, troubleshooting)
│
└── .gitignore                   # Protects .tfstate, .conf files, secrets
```

### How It Works Together

1. **shared/main.tf** creates a persistent Hetzner volume (e.g., `wg-persist-01`)
2. **infra/main.tf** provisions a VPS and:
   - Attaches the persistent volume from shared/
   - Runs cloud-init (from cloud-init.yaml.tftpl) on first boot
   - cloud-init starts the wg-easy Docker container, which reads/writes peer configs to the mounted volume
3. When you run `terraform destroy`, the VPS is deleted but the volume (and all WireGuard configs) remain
4. When you run `terraform apply` again, a new VPS comes up, re-attaches the same volume, and all peers are back online

### Terraform Workspaces (Multiple VPNs)

To run multiple WireGuard instances (e.g., one for US, one for EU):

```bash
cd hcloud-terraform/infra

# Create a second VPN
terraform workspace new vpn-eu
terraform apply -var="vm_name=wg-eu" -var="location=nbg1"

# Switch between VPNs
terraform workspace select default   # First VPN
terraform workspace select vpn-eu    # Second VPN

# Each has isolated state and separate Hetzner resources
```

---

## Security

### Public Exposure

- **Port 51820/UDP** is open to the entire internet (required for VPN to work)
- **Security model**: WireGuard uses cryptographic key exchange (Curve25519). Only peers with valid private keys can connect. No weak credentials or brute-force risk.
- **Admin UI** is **not** exposed — only accessible on localhost via SSH tunnel

### Firewall Rules

```
Inbound:
├── TCP 22 (SSH admin access) — from anywhere
├── UDP 51820 (WireGuard) — from anywhere
Outbound:
└── All allowed (needed for apt, Docker Hub, etc.)
```

### Best Practices

1. **Backup admin password**: Store `wg_admin_password` securely (not in git)
2. **Rotate keys periodically**: Delete/re-add peers as developers churn
3. **Monitor logs**: `docker logs wg-easy` on the VPS
4. **Update regularly**: `terraform apply` picks up security patches automatically (cloud-init)

---

## Troubleshooting

### Can't connect to admin UI

1. Verify SSH tunnel is open:
   ```bash
   lsof -i :51821
   ```
   If nothing, the tunnel dropped. Re-run the SSH command.

2. Check wg-easy container is running:
   ```bash
   ssh root@<your-vps-ip> "docker ps | grep wg-easy"
   ```

3. Verify password is correct (check `terraform.auto.tfvars`)

### Peer can't connect

1. Check firewall rule for UDP 51820:
   ```bash
   ssh root@<your-vps-ip> "sudo ufw status | grep 51820"
   ```

2. Verify peer config has correct `Endpoint`:
   ```bash
   # Should be the VPS public IP from Terraform outputs
   grep "Endpoint" ./admin-wg0.conf
   ```

3. Test from VPS:
   ```bash
   ssh root@<your-vps-ip> "docker exec wg-easy wg show"
   ```

### Peer can't reach home server

1. Ensure home server is connected with `10.0.0.2`:
   ```bash
   # On home server
   ip addr show wg0
   ```

2. Verify Ollama is listening:
   ```bash
   # On home server
   ss -tlnp | grep 11434
   ```

3. Test from India dev:
   ```bash
   # After connecting to VPN
   ping 10.0.0.2
   curl http://10.0.0.2:11434/api/tags
   ```

---

## Costs & Cleanup

### Ongoing Costs

- Hetzner VM: ~$5-10/month (running)
- Persistent volume: ~$1-5/month (always)
- Reserved IP: $0 (while attached)
- **Total**: ~$6-15/month

### Pause or Destroy

If you don't need the VPN for a while:

```bash
# Stop the server (keep volume + IP)
terraform destroy
# Cost drops to ~$1-5/month (volume only)

# Spin it back up whenever
terraform apply
# VM back in 2-5 minutes, configs intact
```

---

## Documentation

- **Admin Guide**: [`hcloud-terraform/utils/wireguard/README.md`](hcloud-terraform/utils/wireguard/README.md) — Adding peers, managing configs, troubleshooting
- **Terraform Code**: [`hcloud-terraform/infra/`](hcloud-terraform/infra/) — Variable definitions, outputs, provisioning logic
- **WireGuard Protocol**: [wireguard.com](https://www.wireguard.com/) — General WireGuard documentation
- **wg-easy**: [github.com/wg-easy/wg-easy](https://github.com/wg-easy/wg-easy) — Docker image we use

---

## Support

For issues with:
- **Terraform**: Check variable names, ensure `terraform.auto.tfvars` is set correctly
- **WireGuard connection**: See "Troubleshooting" above
- **wg-easy UI**: See admin guide in [`hcloud-terraform/utils/wireguard/README.md`](hcloud-terraform/utils/wireguard/README.md)
- **Hetzner**: [hetzner.com/support](https://www.hetzner.com/support)
