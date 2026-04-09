# Volume Backup & Restore (rsync over SSH)

Back up the Hetzner persistent volume (`/mnt/persist`) to your local machine
using rsync over SSH. Requires the VM to be running.

## Prerequisites

- SSH access to the VM (via Tailscale or public IP)
- `rsync` installed locally (included on macOS and most Linux distros)

## Get the connection info

```bash
pushd ../../infra
terraform output ssh_tailscale_command   # e.g. ssh root@spacebot
terraform output ssh_command             # fallback: ssh root@<public-ip>
popd
```

## Backup

```bash
./backup.sh backup
```

Dry run (see what would transfer without copying):

```bash
./backup.sh backup --dry-run
```

## Restore

```bash
./backup.sh restore
```

Dry run:

```bash
./backup.sh restore --dry-run
```

## Restore a single file

For a single file, use rsync directly:

```bash
rsync -avz ./data/somefile root@spacebot:/mnt/persist/somefile
```

## Tips

- Add `--delete` to make the destination an exact mirror of the source
  (deletes files on the destination that no longer exist on the source).
- Add `--progress` to see per-file transfer progress.
- Replace `spacebot` with the Tailscale hostname if you changed `vm_name`.
- If using the public IP instead of Tailscale, substitute it for `spacebot`
  in the commands above.
