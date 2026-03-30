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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
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

# ── Locals ──────────────────────────────────────────────────────────────────
#
# Workspace-aware naming: "default" workspace uses vm_name as-is,
# other workspaces get "vm_name-workspace" to avoid Hetzner naming collisions.

locals {
  name_prefix = terraform.workspace == "default" ? var.vm_name : "${var.vm_name}-${terraform.workspace}"
  ssh_key_id  = terraform.workspace == "default" ? hcloud_ssh_key.research[0].id : data.hcloud_ssh_key.research[0].id
}

# ── Tailscale Auth Key ────────────────────────────────────────────────────────
#
# Generates a single-use, ephemeral auth key on every apply.
# No manual key management — Terraform handles it.

resource "tailscale_tailnet_key" "research" {
  reusable      = true
  ephemeral     = true
  preauthorized = true
  description   = "hetzner-${local.name_prefix}"
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
# Minimal surface: SSH inbound only (Phase 2: remove SSH rule, go Tailscale-only).
# TODO: Once Tailscale is proven reliable, remove SSH rule for max security.
#       Break-glass: re-add port 22 via Hetzner web console if needed.
# All outbound traffic allowed — needed for apt, npm, GitHub, claude.ai OAuth.

resource "hcloud_firewall" "research" {
  name = "${local.name_prefix}-fw"

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

  # cloud-init installs base packages + Tailscale, then you run init-ubuntu-vm.sh.
  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    tailscale_authkey = tailscale_tailnet_key.research.key
    vm_name           = var.vm_name
    repos_yaml        = file("${path.module}/../repos.yaml")
    claude_md         = file("${path.module}/../CLAUDE.md")
    work_on_cmd       = file("${path.module}/../commands/work-on.md")
    init_script       = file("${path.module}/../init-ubuntu-vm.sh")
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

# ── Copy SSH Private Key to VM ────────────────────────────────────────────────
#
# Securely copies your local SSH private key to the VM over SSH.
# The key is transferred directly — never stored in Terraform state.
# Needed for git clone over SSH, GitHub pushes, etc.

resource "null_resource" "copy_ssh_key" {
  depends_on = [hcloud_server.research]

  triggers = {
    server_id = hcloud_server.research.id
  }

  connection {
    type        = "ssh"
    host        = hcloud_server.research.ipv4_address
    user        = "root"
    private_key = file(pathexpand(var.ssh_private_key_path))
    timeout     = "2m"
  }

  provisioner "file" {
    source      = pathexpand(var.ssh_private_key_path)
    destination = "/root/.ssh/id_ed25519"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 600 /root/.ssh/id_ed25519",
      "ssh-keyscan github.com >> /root/.ssh/known_hosts 2>/dev/null",
    ]
  }
}

# ── Reserved IP (optional) ────────────────────────────────────────────────────
#
# With Tailscale, MagicDNS handles identity — reserved IPs are optional.
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
