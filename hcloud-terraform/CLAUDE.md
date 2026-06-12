# WireGuard VPN on Hetzner — Instructions

This branch automates a **WireGuard VPN** server on Hetzner Cloud for secure remote access to home-based services (e.g., Ollama). Unlike the main branch (which is for agentic coding), this branch is **infrastructure-only**.

## Scope

This terraform configuration:
- **Creates**: A Hetzner Cloud VPS running WireGuard via wg-easy Docker container
- **Provides**: Hub-and-spoke VPN for home server + remote developers
- **Stores**: Configs on persistent volume (survives VM teardowns)

This terraform configuration does **NOT**:
- Clone or manage user repositories
- Install development tools (Node.js, GitHub CLI, etc.)
- Run agentic coding sessions

## Prerequisites

Before applying Terraform, ensure you have:

1. **Hetzner Cloud account** with valid API token
2. **SSH key** to authenticate with the VPS
3. **WireGuard client** installed locally (for testing after deployment)
4. **Terraform >= 1.6** installed locally

## Workflow

When working on this terraform:

1. **Before apply**: Always run `terraform plan` and review changes
2. **Password management**: `wg_admin_password` should be stored in `terraform.auto.tfvars` (gitignored)
3. **Network changes**: If modifying firewall rules, test them in a test workspace first:
   ```bash
   terraform workspace new test
   terraform apply -var-file=terraform.auto.tfvars
   # Test, then destroy
   terraform destroy
   terraform workspace select default
   ```
4. **Backup configs**: Before destroying, backup `/mnt/persist/wireguard/`:
   ```bash
   scp -r root@<vps-ip>:/mnt/persist/wireguard/ ./backup/
   ```
5. **Multi-region**: Use workspaces to manage multiple VPN instances (e.g., US, EU):
   ```bash
   terraform workspace new vpn-eu
   terraform apply -var="location=nbg1"
   ```

## Directory Structure

```
hcloud-terraform/
├── shared/          # Persistent volume (managed separately, survives VM teardowns)
├── infra/           # Hetzner VM + WireGuard + firewall
└── utils/wireguard/ # Admin guide + documentation
```

- **shared/**: Manages the persistent Hetzner volume. Apply this once and **leave it alone**.
- **infra/**: The VPN server itself. Can be destroyed and recreated (configs survive on the volume).

## Rules

- **Never modify `shared/`** after initial apply — it has `prevent_destroy = true`.
- **Backup before destroy**: Always backup `/mnt/persist/wireguard/` if you're destroying the VPS.
- **Test firewall changes** in a workspace before applying to production.
- **Update documentation** in `hcloud-terraform/utils/wireguard/README.md` when adding new peers or features.
- **Use terraform.auto.tfvars** for secrets (gitignored). Never commit passwords or API keys.

## Common Tasks

| Task | Command |
|---|---|
| **Stand up the VPN** | `cd hcloud-terraform/infra && terraform apply` |
| **Tear down (keep volume)** | `terraform destroy` |
| **Access admin UI** | `ssh -L 127.0.0.1:51821:127.0.0.1:51821 root@<vps-ip>` |
| **Add a new peer** | Via admin UI or `hcloud-terraform/utils/wireguard/README.md` |
| **Backup configs** | `scp -r root@<vps-ip>:/mnt/persist/wireguard/ ./backup/` |

## Documentation

- **Main guide**: [`README.md`](../../README.md) — Overview, quick start, troubleshooting
- **Admin guide**: [`utils/wireguard/README.md`](utils/wireguard/README.md) — Adding peers, managing configs
- **WireGuard protocol**: [wireguard.com](https://www.wireguard.com/)
