#!/usr/bin/env bash
# Ubuntu VM Initializer — sets up tmux and shell helpers
set -euo pipefail

# Prevent debconf dialogs from blocking in non-interactive cloud-init
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Ensure HOME is set (cloud-init may not set it)
export HOME="${HOME:-/root}"

TMUX_SESSION="work"

log() { echo ">>> $1"; }

# Wait for any existing apt/dpkg locks (cloud-init, unattended-upgrades, etc.)
wait_for_apt() {
  local tries=0
  while fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock &>/dev/null; do
    if (( tries++ >= 30 )); then
      log "ERROR: apt lock held for over 5 minutes, giving up"
      return 1
    fi
    log "Waiting for apt lock (attempt $tries/30)..."
    sleep 10
  done
}

# System packages
wait_for_apt
log "Updating apt and installing packages"
sudo apt-get update -y
sudo apt-get install -y curl tmux unzip ca-certificates

# Tailscale (install only — auth happens via cloud-init authkey on first boot)
if ! command -v tailscale &>/dev/null; then
  log "Installing Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
fi

# tmux config
if [[ ! -f "$HOME/.tmux.conf" ]]; then
  log "Writing ~/.tmux.conf"
  cat > "$HOME/.tmux.conf" << 'EOF'
set -g history-limit 50000
set -g mouse on
set -g set-clipboard on
set -g base-index 1
setw -g pane-base-index 1
set -g status-interval 5
set -g status-left "#[fg=green][#S] "
set -g status-right "#[fg=yellow]%H:%M %d-%b"
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
bind r source-file ~/.tmux.conf \; display "Config reloaded!"
EOF
fi

# Shell helpers
if ! grep -q "# spacebot-init" "$HOME/.bashrc" 2>/dev/null; then
  log "Adding shell helpers to ~/.bashrc"
  cat >> "$HOME/.bashrc" << EOF

# spacebot-init
alias work="tmux attach -t $TMUX_SESSION 2>/dev/null || tmux new -s $TMUX_SESSION"
alias ll="ls -lah"
EOF
fi

# Done
echo ""
log "Setup complete! Installed: tmux, tailscale"
log "Run: work"
