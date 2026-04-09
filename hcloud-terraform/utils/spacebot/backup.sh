#!/usr/bin/env bash
set -euo pipefail

REMOTE="root@spacebot"
REMOTE_PATH="/mnt/persist/"
LOCAL_PATH="$(cd "$(dirname "$0")" && pwd)/data/"

usage() {
  echo "Usage: $0 <backup|restore> [--dry-run]"
  echo
  echo "  backup   Pull $REMOTE_PATH → $LOCAL_PATH"
  echo "  restore  Push $LOCAL_PATH → $REMOTE_PATH"
  echo
  echo "  --dry-run  Show what would be transferred without copying"
  exit 1
}

[[ $# -lt 1 ]] && usage

CMD="$1"; shift
DRY_RUN=""
for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]] && DRY_RUN="-n"
done

RSYNC="rsync -avz${DRY_RUN:+ $DRY_RUN}"

case "$CMD" in
  backup)
    echo "Backing up $REMOTE:$REMOTE_PATH → $LOCAL_PATH"
    mkdir -p "$LOCAL_PATH"
    $RSYNC "$REMOTE:$REMOTE_PATH" "$LOCAL_PATH"
    ;;
  restore)
    echo "Restoring $LOCAL_PATH → $REMOTE:$REMOTE_PATH"
    $RSYNC "$LOCAL_PATH" "$REMOTE:$REMOTE_PATH"
    ;;
  *)
    usage
    ;;
esac
