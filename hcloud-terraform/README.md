# hcloud-terraform

Terraform modules for the Hetzner Cloud research VM.

See the [top-level README](../README.md) for the full setup guide,
architecture overview, and daily workflow documentation.

## Quick reference

```bash
cd infra/
terraform init      # install deps, connect to shared state backend (if backend.tf is provided)
terraform plan      # review changes
terraform apply     # create/update VM
terraform destroy   # tear down VM (snapshot + reserved IP)
```
