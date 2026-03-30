# =============================================================================
# infra/outputs.tf
# =============================================================================

output "server_ip" {
  description = "Public IP of the research VM (only set when use_reserved_ip = true)"
  value       = var.use_reserved_ip ? hcloud_primary_ip.research[0].ip_address : hcloud_server.research.ipv4_address
}

output "server_name" {
  description = "Server name"
  value       = hcloud_server.research.name
}

output "server_type" {
  description = "Server type provisioned"
  value       = hcloud_server.research.server_type
}

output "tailscale_hostname" {
  description = "Tailscale MagicDNS hostname — use this in ShellFish instead of an IP"
  value       = var.vm_name
}

output "ssh_command" {
  description = "SSH via public IP (fallback). Prefer: ssh root@<tailscale_hostname>"
  value       = "ssh root@${var.use_reserved_ip ? hcloud_primary_ip.research[0].ip_address : hcloud_server.research.ipv4_address}"
}

output "ssh_tailscale_command" {
  description = "SSH via Tailscale (preferred — works from any device on your tailnet)"
  value       = "ssh root@${var.vm_name}"
}

output "volume_name" {
  description = "Persistent volume name (survives VM rebuilds)"
  value       = hcloud_volume.persist.name
}

output "volume_size" {
  description = "Persistent volume size in GB"
  value       = hcloud_volume.persist.size
}

output "init_command" {
  description = "Run this after VM is up to complete setup"
  value       = "scp init-ubuntu-vm.sh root@${hcloud_server.research.ipv4_address}:~/ && ssh root@${hcloud_server.research.ipv4_address} './init-ubuntu-vm.sh'"
}
