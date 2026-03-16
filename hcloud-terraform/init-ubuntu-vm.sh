#!/usr/bin/env bash
# Ubuntu VM Initializer — sets up Node.js, git, gh, tmux, Tailscale, Claude Code
set -euo pipefail

NODE_MAJOR=22
TMUX_SESSION="work"

log() { echo ">>> $1"; }

GITHUB_EMAIL="${GITHUB_EMAIL:-user@host.com}"
GITHUB_USERNAME="${GITHUB_USERNAME:-your-gh-userid}"

# System packages
log "Updating system and installing packages"
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y \
  curl git tmux unzip build-essential ca-certificates gnupg lsb-release htop jq wget

# Node.js
if ! command -v node &>/dev/null || [[ "$(node -v | tr -d 'v' | cut -d. -f1)" -lt "$NODE_MAJOR" ]]; then
  log "Installing Node.js $NODE_MAJOR"
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | sudo -E bash -
  sudo apt-get install -y nodejs
fi
log "Node $(node -v), npm $(npm -v)"

# GitHub CLI
if ! command -v gh &>/dev/null; then
  log "Installing GitHub CLI"
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
  sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
    https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt-get update && sudo apt-get install -y gh
fi
log "gh $(gh --version | head -1)"

# Git config
log "Configuring git for $GITHUB_USERNAME <$GITHUB_EMAIL>"
git config --global user.name "$GITHUB_USERNAME"
git config --global user.email "$GITHUB_EMAIL"
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.editor nano
git config --global alias.st "status"
git config --global alias.lg "log --oneline --graph --decorate --all"
git config --global alias.pushb "push origin HEAD"

# Claude Code
if ! command -v claude &>/dev/null; then
  log "Installing Claude Code"
  npm install -g @anthropic-ai/claude-code
fi

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
if ! grep -q "# claude-flow-init" "$HOME/.bashrc" 2>/dev/null; then
  log "Adding shell helpers to ~/.bashrc"
  cat >> "$HOME/.bashrc" << EOF

# claude-flow-init
alias work="tmux attach -t $TMUX_SESSION 2>/dev/null || tmux new -s $TMUX_SESSION"
alias ll="ls -lah"
alias gs="git status"
alias gp="git pushb"
unset ANTHROPIC_API_KEY
EOF
fi

# Repo registry and global Claude instructions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/repos.yaml" ]]; then
  log "Installing repo registry to ~/repos.yaml"
  cp "$SCRIPT_DIR/repos.yaml" "$HOME/repos.yaml"
fi

if [[ -f "$SCRIPT_DIR/CLAUDE.md" ]]; then
  log "Installing global CLAUDE.md to ~/CLAUDE.md"
  cp "$SCRIPT_DIR/CLAUDE.md" "$HOME/CLAUDE.md"
fi

if [[ -d "$SCRIPT_DIR/commands" ]]; then
  log "Installing global Claude commands to ~/.claude/commands/"
  mkdir -p "$HOME/.claude/commands"
  cp "$SCRIPT_DIR/commands/"*.md "$HOME/.claude/commands/"
fi

# Done
echo ""
log "Setup complete! Installed: Node $(node -v), git $(git --version | cut -d' ' -f3), gh, tmux, claude, tailscale"
log "Next steps:"
log "  1. gh auth login"
log "  2. claude  (to authenticate)"
log "  3. source ~/.bashrc && work"
