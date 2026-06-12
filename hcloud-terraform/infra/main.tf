# =============================================================================
# infra/main.tf
#
# Provisions a Hetzner Cloud VM running WireGuard VPN (via wg-easy).
# Persistent volume stores VPN configurations across VM teardowns.
#
# Prerequisites:
#   - Run shared/ once to create the persistent volume
#   - Set HCLOUD_TOKEN env var (or use .auto.tfvars)
#   - Set WG_ADMIN_PASSWORD env var (or use .auto.tfvars)
# =============================================================================

terraform {
  required_version = ">= 1.6"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.47"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

# ── Locals ──────────────────────────────────────────────────────────────────
#
# Workspace-aware naming: "default" workspace uses vm_name as-is,
# other workspaces get "vm_name-workspace" to avoid Hetzner naming collisions.

locals {
  name_prefix = terraform.workspace == "default" ? var.vm_name : "${var.vm_name}-${terraform.workspace}"
  ssh_key_id  = terraform.workspace == "default" ? hcloud_ssh_key.research[0].id : data.hcloud_ssh_key.research[0].id
}

# ── SSH Key ───────────────────────────────────────────────────────────────────
#
# Hetzner enforces uniqueness on the public key value, so we can only register
# it once. Use a data source to look up the existing key by fingerprint.
# The key must already exist in Hetzner (created by the default workspace or
# uploaded via the console).

resource "hcloud_ssh_key" "research" {
  count      = terraform.workspace == "default" ? 1 : 0
  name       = "${var.vm_name}-key"
  public_key = var.ssh_public_key
}

data "hcloud_ssh_key" "research" {
  count = terraform.workspace != "default" ? 1 : 0
  name  = "${var.vm_name}-key"
}

# ── Firewall ──────────────────────────────────────────────────────────────────
#
# Minimal surface: SSH + WireGuard inbound only.
# All outbound allowed — needed for apt, Docker Hub, package downloads.

resource "hcloud_firewall" "research" {
  name = "${local.name_prefix}-fw"

  # SSH (admin access)
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # WireGuard VPN
  rule {
    direction = "in"
    protocol  = "udp"
    port      = var.wg_server_port
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Allow all outbound
  rule {
    direction   = "out"
    protocol    = "tcp"
    port        = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction   = "out"
    protocol    = "udp"
    port        = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction   = "out"
    protocol    = "icmp"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}

# ── Server ────────────────────────────────────────────────────────────────────

resource "hcloud_server" "research" {
  name        = local.name_prefix
  server_type = var.server_type
  image       = "ubuntu-24.04"
  location    = var.location
  ssh_keys    = [local.ssh_key_id]

  firewall_ids = [hcloud_firewall.research.id]

  public_net {
    ipv4_enabled = true
    ipv4         = var.use_reserved_ip ? hcloud_primary_ip.research[0].id : null
  }

  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    wg_admin_password = var.wg_admin_password
    wg_server_port    = var.wg_server_port
  })

  labels = {
    purpose = "wireguard-vpn"
    owner   = var.owner_tag
  }

  lifecycle {
    prevent_destroy = false
  }
}

# ── Persistent Volume (managed by shared/) ────────────────────────────────────
#
# The volume lives in the shared/ config so it survives `terraform destroy`.
# WireGuard configs persist at /mnt/persist/wireguard/.

data "hcloud_volume" "persist" {
  name = "${var.vm_name}-persist"
}

resource "hcloud_volume_attachment" "persist" {
  volume_id = data.hcloud_volume.persist.id
  server_id = hcloud_server.research.id
  automount = true
}

# ── Reserved IP (optional) ────────────────────────────────────────────────────
#
# If Tailscale, then MagicDNS handles identity — reserved IPs are optional.
# Enable with use_reserved_ip = true if you still want a stable public IP.
# Free when assigned to a server; €0.01/hr only if unassigned.

resource "hcloud_primary_ip" "research" {
  count         = var.use_reserved_ip ? 1 : 0
  name          = "${local.name_prefix}-ip"
  type          = "ipv4"
  assignee_type = "server"
  location      = var.location
  auto_delete   = false
}
