# =============================================================================
# infra/outputs.tf
#
# WireGuard VPN outputs for admin access and configuration
# =============================================================================

locals {
  server_ip = var.use_reserved_ip ? hcloud_primary_ip.research[0].ip_address : hcloud_server.research.ipv4_address
}

output "server_ip" {
  description = "Public IP of the WireGuard VPN server"
  value       = local.server_ip
}

output "server_name" {
  description = "Server name"
  value       = hcloud_server.research.name
}

output "server_type" {
  description = "Server type provisioned"
  value       = hcloud_server.research.server_type
}

output "ssh_command" {
  description = "SSH to the WireGuard server"
  value       = "ssh root@${local.server_ip}"
}

output "wireguard_endpoint" {
  description = "WireGuard server endpoint (public_ip:port) for client configs"
  value       = "${local.server_ip}:${var.wg_server_port}"
}

output "wg_easy_admin_tunnel" {
  description = "SSH tunnel command to access wg-easy admin UI from localhost:51821"
  value       = "ssh -L 127.0.0.1:51821:127.0.0.1:51821 root@${local.server_ip}"
}

output "wg_easy_admin_url" {
  description = "Admin UI URL (access after establishing SSH tunnel above)"
  value       = "http://127.0.0.1:51821"
}

output "wg_config_download" {
  description = "SCP command to download admin peer WireGuard config"
  value       = "scp root@${local.server_ip}:/root/wireguard-admin.conf ./admin-wg0.conf"
}

output "volume_name" {
  description = "Persistent volume name (managed by shared/). WireGuard configs stored at /mnt/persist/wireguard/"
  value       = data.hcloud_volume.persist.name
}

output "volume_size" {
  description = "Persistent volume size in GB"
  value       = data.hcloud_volume.persist.size
}

output "dns_record_setup" {
  description = "DNS A record to create in Squarespace for stable endpoint"
  value       = <<-EOT
    Create this DNS record in Squarespace for vpn.skillrev.in:

    Record Type:  A
    Name:         vpn
    Value:        ${local.server_ip}
    TTL:          3600 (or lowest available)

    Steps:
    1. Go to squarespace.com → Domains → skillrev.in → DNS
    2. Click "Add Record" → Type: A
    3. Name: vpn
    4. Value: ${local.server_ip}
    5. Save

    After DNS propagates (~5-30 min), all peer configs can use:
      Endpoint = vpn.skillrev.in:${var.wg_server_port}

    This allows you to scale/recreate the server without reissuing configs.
    Just update the A record to the new IP.
  EOT
}

output "wg_next_steps" {
  description = "Quick start guide for WireGuard"
  value       = <<-EOT
    WireGuard VPN is ready!

    Quick start:
    ───────────

    1. (OPTIONAL) Set up DNS for stable endpoint:
       See output: dns_record_setup
       This allows scaling later without breaking peer configs.

    2. Access the admin dashboard to add more peers:
       ssh -L 127.0.0.1:51821:127.0.0.1:51821 root@${local.server_ip}
       Then open: http://127.0.0.1:51821

    3. Download the auto-generated admin config:
       scp root@${local.server_ip}:/root/wireguard-admin.conf ./admin-wg0.conf

    4. Import into your WireGuard client:
       - File → Import from file
       - Select admin-wg0.conf
       - Connect!

    5. Home server (10.0.0.2) will:
       - See the VPN and route via the Hetzner hub
       - Reach ollama on localhost:11434
       - Keep connection alive with PersistentKeepalive=25

    6. Add India developers:
       - Use admin dashboard to add peers
       - Set AllowedIPs = 10.0.0.2/32 for split tunnel
       - Issue each developer their .conf file
       - If using vpn.skillrev.in, use that in their Endpoint

    VPN Network:
    ────────────
    Hub (Hetzner):        10.0.0.1 (server)
    Home (You):           10.0.0.2 (auto-generated)
    India Dev 1:          10.0.0.3 (split tunnel)
    India Dev 2:          10.0.0.4 (split tunnel)
    ... and so on
  EOT
}
