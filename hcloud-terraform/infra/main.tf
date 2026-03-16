# =============================================================================
# infra/main.tf
#
# Provisions a Hetzner Cloud research VM for Claude Flow / agentic coding.
# Each `terraform apply` creates a fresh Ubuntu VM with Tailscale pre-configured.
#
# Prerequisites:
#   - Run bootstrap/ once to create Azure storage backend
#   - Set HCLOUD_TOKEN env var (or use .auto.tfvars — see variables.tf)
#   - Set TAILSCALE_API_KEY env var (or use .auto.tfvars)
#   - Add your SSH public key to Hetzner console or let this config manage it
# =============================================================================

terraform {
  required_version = ">= 1.6"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.47"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.17"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "tailscale" {
  api_key = var.tailscale_api_key
  tailnet = var.tailscale_tailnet
}

# ── Tailscale Auth Key ────────────────────────────────────────────────────────
#
# Generates a single-use, ephemeral auth key on every apply.
# No manual key management — Terraform handles it.

resource "tailscale_tailnet_key" "research" {
  reusable      = false
  ephemeral     = true
  preauthorized = true
  description   = "hetzner-${var.vm_name}"
}

# ── SSH Key ───────────────────────────────────────────────────────────────────

resource "hcloud_ssh_key" "research" {
  name       = "${var.vm_name}-key"
  public_key = var.ssh_public_key
}

# ── Firewall ──────────────────────────────────────────────────────────────────
#
# Minimal surface: SSH inbound only (Phase 2: remove SSH rule, go Tailscale-only).
# TODO: Once Tailscale is proven reliable, remove SSH rule for max security.
#       Break-glass: re-add port 22 via Hetzner web console if needed.
# All outbound traffic allowed — needed for apt, npm, GitHub, claude.ai OAuth.

resource "hcloud_firewall" "research" {
  name = "${var.vm_name}-fw"

  # SSH
  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
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
  name        = var.vm_name
  server_type = var.server_type
  image       = "ubuntu-24.04"
  location    = var.location
  ssh_keys    = [hcloud_ssh_key.research.id]

  firewall_ids = [hcloud_firewall.research.id]

  public_net {
    ipv4_enabled = true
    ipv4         = var.use_reserved_ip ? hcloud_primary_ip.research[0].id : null
  }

  # cloud-init installs base packages + Tailscale, then you run init-ubuntu-vm.sh.
  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    tailscale_authkey = tailscale_tailnet_key.research.key
    vm_name           = var.vm_name
  })

  labels = {
    purpose = "research"
    tool    = "claude-flow"
    owner   = var.owner_tag
  }

  lifecycle {
    prevent_destroy = false
  }
}

# ── Reserved IP (optional) ────────────────────────────────────────────────────
#
# With Tailscale, MagicDNS handles identity — reserved IPs are optional.
# Enable with use_reserved_ip = true if you still want a stable public IP.
# Free when assigned to a server; €0.01/hr only if unassigned.

resource "hcloud_primary_ip" "research" {
  count         = var.use_reserved_ip ? 1 : 0
  name          = "${var.vm_name}-ip"
  type          = "ipv4"
  assignee_type = "server"
  location      = var.location
  auto_delete   = false
}
