# =============================================================================
# infra/variables.tf
# =============================================================================

variable "hcloud_token" {
  description = "Hetzner Cloud API token. Generate at: console.hetzner.cloud → project → Security → API Tokens"
  type        = string
  sensitive   = true
}

variable "vm_name" {
  description = "VM name and WireGuard peer identifier. Also used as volume prefix."
  type        = string
  default     = "wireguard-vpn"
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

variable "wg_admin_password" {
  description = "WireGuard admin panel password (plaintext; used to generate hash)"
  type        = string
  sensitive   = true
}

variable "wg_admin_password_hash" {
  description = "WireGuard admin panel password bcrypt hash (generate with: echo -n 'your-password' | mkpasswd -m bcrypt -R 10)"
  type        = string
  sensitive   = true
}

variable "wg_server_port" {
  description = "WireGuard server port (UDP)"
  type        = number
  default     = 51820

  validation {
    condition     = var.wg_server_port > 1024 && var.wg_server_port <= 65535
    error_message = "WireGuard port must be between 1025 and 65535."
  }
}

variable "use_reserved_ip" {
  description = "Allocate a stable public IPv4 for WireGuard endpoint."
  type        = bool
  default     = true
}
