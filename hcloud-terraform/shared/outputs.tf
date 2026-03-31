# =============================================================================
# shared/outputs.tf
# =============================================================================

output "volume_id" {
  description = "Volume ID — for reference only; infra/ looks it up by name via data source."
  value       = hcloud_volume.persist.id
}

output "volume_name" {
  description = "Volume name used by infra/ data source lookup."
  value       = hcloud_volume.persist.name
}

output "volume_size" {
  description = "Volume size in GB."
  value       = hcloud_volume.persist.size
}
