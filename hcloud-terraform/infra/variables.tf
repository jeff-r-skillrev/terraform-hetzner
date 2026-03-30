# =============================================================================
# infra/variables.tf
# =============================================================================

variable "hcloud_token" {
  description = "Hetzner Cloud API token. Generate at: console.hetzner.cloud → project → Security → API Tokens"
  type        = string
  sensitive   = true
}

variable "vm_name" {
  description = "Name of the research VM. Also used as the Tailscale MagicDNS hostname."
  type        = string
  default     = "claude-research"
}

variable "server_type" {
  description = "Hetzner server type"
  type        = string
  default     = "cpx21"

  validation {
    condition     = contains(["cpx21", "cax11"], var.server_type)
    error_message = "Choose one of: cpx21 (budget x86) 2 vCPU shared, 4GB RAM, ~$5/mo, cax11 (budget ARM) 2 vCPU shared, 4GB RAM, ~$5/mo."
  }
}

variable "location" {
  description = "Hetzner datacenter. ash = Ashburn VA (best for US East). hil = Hillsboro OR (US West)."
  type        = string
  default     = "ash"

  validation {
    condition     = contains(["ash", "hil", "nbg1", "fsn1", "hel1", "sin"], var.location)
    error_message = "Valid locations: ash, hil (US), nbg1, fsn1, hel1 (EU), sin (Singapore)."
  }
}

variable "ssh_public_key" {
  description = "Your SSH public key content (the .pub file). Paste the full string."
  type        = string
}

variable "owner_tag" {
  description = "Your name or handle, used as a label on the server for multi-user projects."
  type        = string
  default     = "your-gh-userid"
}

variable "tailscale_api_key" {
  description = "Tailscale API key for auto-generating auth keys. Generate at: login.tailscale.com/admin/settings/keys → API keys"
  type        = string
  sensitive   = true
}

variable "tailscale_tailnet" {
  description = "Your Tailscale tailnet name (e.g. 'yourname@gmail.com' or your org name). Find at: login.tailscale.com/admin/settings/general"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Local path to your SSH private key. Used to copy the key to the VM for GitHub access (never stored in Terraform state)."
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "use_reserved_ip" {
  description = "Allocate a stable public IPv4. With Tailscale, MagicDNS handles identity so this is optional."
  type        = bool
  default     = false
}
