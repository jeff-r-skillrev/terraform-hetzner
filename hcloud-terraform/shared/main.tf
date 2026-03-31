# =============================================================================
# shared/main.tf
#
# Long-lived resources that survive VM lifecycle and are shared across
# Terraform workspaces. Apply once, then leave alone.
#
# Usage:
#   cd shared && terraform init && terraform apply
#
# The infra/ config references these resources via data sources.
# `terraform destroy` in infra/ only detaches — it cannot delete these.
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

# ── Persistent Volume ─────────────────────────────────────────────────────────
#
# Block storage that survives VM destroy/recreate.
# Mounted at /mnt/persist on whichever VM attaches it.
#   /mnt/persist/spacebot/data  — Spacebot persistent data

resource "hcloud_volume" "persist" {
  name     = "${var.vm_name}-persist"
  size     = var.volume_size
  location = var.location
  format   = "ext4"

  labels = {
    purpose = "research"
    owner   = var.owner_tag
  }

  lifecycle {
    prevent_destroy = true
  }
}
