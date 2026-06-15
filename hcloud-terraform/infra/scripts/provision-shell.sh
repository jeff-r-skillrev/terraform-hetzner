#!/bin/bash
set -euo pipefail

# tmux config
if [[ ! -f /root/.tmux.conf ]]; then
  echo ">>> Writing ~/.tmux.conf"
  cat > /root/.tmux.conf << 'TMUXEOF'
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
TMUXEOF
fi

# Shell aliases
if ! grep -q "# wireguard-helpers" /root/.bashrc 2>/dev/null; then
  echo ">>> Adding WireGuard helpers to ~/.bashrc"
  cat >> /root/.bashrc << 'BASHEOF'

# wireguard-helpers
alias work="tmux attach -t work 2>/dev/null || tmux new -s work"
alias ll="ls -lah"
alias wg-logs="docker logs -f wg-easy"
alias wg-restart="docker restart wg-easy"
alias wg-status="docker ps -a | grep wg-easy"
BASHEOF
fi

echo ">>> Shell setup complete"
