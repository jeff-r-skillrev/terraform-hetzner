# =============================================================================
# shared/variables.tf
# =============================================================================

variable "hcloud_token" {
  description = "Hetzner Cloud API token."
  type        = string
  sensitive   = true
}

variable "vm_name" {
  description = "Base name used for shared resource naming (e.g. volume = vm_name-persist)."
  type        = string
  default     = "spacebot"
}

variable "location" {
  description = "Hetzner datacenter — must match the infra/ config so the volume can attach."
  type        = string
  default     = "ash"

  validation {
    condition     = contains(["ash", "hil", "nbg1", "fsn1", "hel1", "sin"], var.location)
    error_message = "Valid locations: ash, hil (US), nbg1, fsn1, hel1 (EU), sin (Singapore)."
  }
}

variable "volume_size" {
  description = "Size in GB of the persistent volume."
  type        = number
  default     = 10
}

variable "owner_tag" {
  description = "Your name or handle, used as a label."
  type        = string
  default     = "your-gh-userid"
}
