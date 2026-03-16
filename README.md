# Hetzner Cloud Research VM

Terraform-managed Hetzner Cloud VM for remote agentic coding. Access from
iPhone via Tailscale + Secure ShellFish, run Claude Code with your choice of
agent orchestrator, push PR branches to GitHub, Bitbucket, etc (repo host agnostic).

---

## Architecture Overview

```
iPhone
  ├── Tailscale app (VPN mesh)
  └── Secure ShellFish (SSH client)
        │
        │  SSH over Tailscale (WireGuard)
        ▼
Hetzner Cloud VM  ──── ~$5/month ──────────────────────────────────
  Ubuntu 24.04 x86                                                  │
  2 vCPU · 4GB RAM (cpx21)                                          │
                                                                     │
  Tailscale ────► auto-joins tailnet, MagicDNS hostname             │
  tmux session "work"                                                │
  ├── window 1: agentic coding session                              │
  ├── window 2: git / gh CLI / monitoring                           │
  └── window 3: spare                                               │
                                                                     │
  Claude Code ──── OAuth ────► claude.ai (Pro subscription)         │
  gh CLI ──── SSH ────────────► GitHub (PRs, branches)             │
─────────────────────────────────────────────────────────────────────
```

**Cost summary**

| Item | Cost |
|---|---|
| Hetzner cpx21 VM (while running) | ~$5/month |
| Hetzner Reserved IP | $0 while assigned to a server |
| Hetzner Snapshot (~20GB) | ~$0.20/month |
| S3 state bucket + DynamoDB lock | < $0.01/month |
| Tailscale | $0 (free tier: up to 100 devices) |
| Claude Pro (includes Claude Code) | $20/month (existing) |
| Secure ShellFish (iOS SSH client) | $30 one-time |
| GitHub | $0 (existing) |
| **New ongoing spend** | **~$5/month** |

When not in use, destroy the VM — cost drops to ~$0. The reserved IP and
snapshot persist and cost almost nothing. Recreate in ~30 seconds from a
snapshot, or ~5 minutes from scratch with `terraform apply`.

Because of tailscale, keeping a particular IP address is less
important. Tailscale's MagicDNS will connect you to the correct box.

---

## Part 1 — Hetzner Cloud Infrastructure (Terraform)

The infrastructure is fully automated with Terraform. Shared state is stored (if backend.tf is configured).

### Directory structure

```
hcloud-terraform/
├── bootstrap/          # Run ONCE to create S3 backend + DynamoDB lock table
│   └── main.tf
├── infra/              # The actual VM — run by anyone on the team
│   ├── backend.tf      # S3, Azure, etc remote state config
│   ├── main.tf         # Server, firewall, reserved IP
│   ├── variables.tf
│   ├── outputs.tf
│   ├── cloud-init.yaml # First-boot setup (used only when not using snapshot)
│   └── terraform.auto.tfvars.example
└── .gitignore
```

### 1.1 Prerequisites

- **Terraform** >= 1.6 — `brew install terraform`
- **hcloud CLI** — `brew install hcloud`
- **Hetzner Cloud API token** — console.hetzner.cloud → project → Security → API Tokens
- **Tailscale account** — login.tailscale.com (free tier works)
- **Tailscale API key** — login.tailscale.com/admin/settings/keys → API keys
  (Terraform uses this to auto-generate ephemeral auth keys — no manual key management)
- **SSH key pair** — `ssh-keygen -t ed25519` (if you don't have one)
- **AWS credentials** — for S3 backend state storage (one-time bootstrap)
- **Azure CLI credentials** - for Azure blob backend state storage (one-time bootstrap)

### 1.3 Configure variables

```bash
cd hcloud-terraform/infra
cp terraform.auto.tfvars.example terraform.auto.tfvars
```

Edit `terraform.auto.tfvars` and fill in:

```hcl
hcloud_token      = "your-hetzner-api-token"
ssh_public_key    = "ssh-ed25519 AAAA... you@yourmachine"
tailscale_api_key = "tskey-api-..."
tailscale_tailnet = "your-tailnet"
owner_tag         = "your-gh-userid"
```

### 1.4 Provision the VM

```bash
terraform init      # pulls providers + connects to S3 backend
terraform plan      # review what will be created
terraform apply     # creates server, firewall, reserved IP
```

Terraform outputs the server IP, SSH command, and Tailscale hostname.

### 1.5 First-time setup

After provisioning, copy and run the init script:

```bash
# Terraform outputs the IP and a ready-to-use scp+ssh command
scp init-ubuntu-vm.sh root@<server_ip>:~/
ssh root@<server_ip>
./init-ubuntu-vm.sh
```

The init script installs: Node.js 22, GitHub CLI, Claude Code, tmux (configured),
Tailscale, git (configured), and shell aliases. Takes ~3-5 minutes.

Tailscale auto-joins your tailnet during cloud-init (before you even SSH in).
After the init script completes, you can connect via MagicDNS:
`ssh root@claude-research`.

### 1.7 Multi-instance with Terraform workspaces

Each workspace is an independent instance with isolated state:

```bash
cd hcloud-terraform/infra

# Create a second VM
terraform workspace new vm-2
terraform apply -var="vm_name=claude-vm-2"

# Switch between instances
terraform workspace select default    # your first VM
terraform workspace select vm-2       # your second VM

# Destroy just one instance
terraform workspace select vm-2
terraform destroy
```

Each VM auto-registers in Tailscale with its `vm_name` as hostname.

---

## Part 2 — What the Init Script Installs

This script gets you the basics in place to have an AI agent
capable of participating as a team-mate, pushing feature
branches and so forth.

- **System packages**: curl, git, tmux, build-essential, htop, jq, wget
- **Node.js 22** via NodeSource
- **GitHub CLI** (`gh`) via official apt repository
- **Claude Code** (`claude`) via npm global install
- **Tailscale** via official installer (auto-joins tailnet via cloud-init on first boot)
- **tmux config** at `~/.tmux.conf` with mouse support, 50k scrollback,
  sensible pane splits, and vim-style navigation
- **Shell aliases** in `~/.bashrc`:
  - `work` — attach to tmux session "work", or create it if new
  - `ll` — `ls -lah`
  - `gs` — `git status`
  - `gp` — push current branch to origin without typing its name
  - `unset ANTHROPIC_API_KEY` — safety line that prevents accidental API billing

After the script finishes, run:

```bash
source ~/.bashrc
```

---

## Part 3 — GitHub SSH Key Setup

The VM needs its own SSH key registered with GitHub so it can clone repos
and push branches.

### 3.1 Generate the key

```bash
ssh-keygen -t ed25519 -C "your@email.com" -f ~/.ssh/github_ed25519 -N ""
```

### 3.2 Configure SSH to use it for GitHub

```bash
cat >> ~/.ssh/config << 'EOF'

Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/github_ed25519
  AddKeysToAgent yes
EOF
chmod 600 ~/.ssh/config
```

### 3.3 Register the key with GitHub (or similar repo host)

```bash
cat ~/.ssh/github_ed25519.pub
```

Copy that entire line, then:
1. Go to github.com → **Settings → SSH and GPG keys → New SSH key**
2. Title: `hetzner-vm` (or anything descriptive)
3. Paste the public key
4. Click **Add SSH key**

### 3.4 Test the connection

```bash
ssh -T git@github.com
# Expected: "Hi yourusername! You've successfully authenticated..."
```

---

## Part 4 — GitHub CLI Authentication (optional)

The `gh` CLI creates pull requests from the command line. It uses a
Personal Access Token (PAT) for auth.

### 4.1 Create a PAT

On GitHub: **Settings → Developer settings → Personal access tokens →
Tokens (classic) → Generate new token**

Required scopes: `repo`, `workflow`, `read:org`

Copy the token — you won't see it again.

### 4.2 Authenticate gh CLI

```bash
gh auth login
```

Walk through the prompts:
- **Where do you use GitHub?** → GitHub.com
- **What is your preferred protocol?** → SSH
- **How would you like to authenticate?** → Paste an authentication token
- Paste your PAT

Verify it worked:

```bash
gh auth status
```

---

## Part 5 — Claude Code Authentication

Claude Code authenticates against your claude.ai Pro subscription via OAuth —
no API key needed or wanted.

```bash
claude
```

Claude Code will print a URL like:
```
Please visit: https://claude.ai/auth/cli?code=XXXXXXXX
```

Open that URL on any device (your laptop, phone, anything) and sign in with
your claude.ai account. The session is saved on the VM and persists across
reconnections.

**Important:** Do not set `ANTHROPIC_API_KEY` anywhere. The init script
adds `unset ANTHROPIC_API_KEY` to your `.bashrc` as a safety guard. If that
variable exists, Claude Code silently switches to API billing and your Pro
subscription is not used.

Verify the auth worked:

```bash
claude --version
# Should show version without prompting for login
```

---

## Part 6 — Secure ShellFish + Tailscale (iPhone Setup)

### 6.1 Install Tailscale on your iPhone

Install **Tailscale** from the App Store (free). Sign in with the same account
you used for the API key. Your Hetzner VM(s) will appear
automatically as devices on your tailnet.

### 6.2 Install Secure ShellFish

**Secure ShellFish** by Dag Ågren — $30 one-time purchase from the App Store.
No subscription. Search "Secure ShellFish" or "ShellFish SSH".

### 6.3 Add your VM as a host in ShellFish

With Tailscale running on your iPhone, ShellFish connects over the Tailscale
VPN — no public IP or port exposure needed.

In ShellFish:
1. Tap **+** to add a new server
2. Fill in:
   - **Host**: your VM's Tailscale MagicDNS name (e.g., `claude-research`)
   - **User**: `root`
   - **Port**: `22`
   - **Authentication**: SSH Key → select or import your key
3. Save and tap to connect

For multiple VMs, add each one by its MagicDNS name (e.g., `claude-vm-1`,
`claude-vm-2`). No IP addresses to manage.

### 6.4 Keyboard setup for tmux

ShellFish has a customizable extra keyboard row above the iOS keyboard. For
tmux and Claude Code use, configure it to include:

- `Ctrl` (essential for tmux prefix `Ctrl+b`)
- `Esc`
- `Tab`
- `↑` `↓` `←` `→` arrow keys

To send a tmux command on iPhone: tap **Ctrl**, tap **B**, then tap the
next key. For example, to create a new window: **Ctrl** → **B** → **C**.

---

## Part 7 — tmux Session Layout

### 7.1 The `work` alias

The init script added this alias:

```bash
alias work="tmux attach -t work 2>/dev/null || tmux new -s work"
```

Type `work` after connecting and you will always land in your persistent
session, creating it fresh if this is the first time.

### 7.2 Recommended window layout

```
tmux session: work
├── window 1 [agents]   — agentic coding session
├── window 2 [git]      — git status, gh pr, branch management
└── window 3 [monitor]  — htop, logs, watching agent output
```

Create this layout once:

```bash
# You're in window 1 by default after `work`
# Rename it
Ctrl+b  ,   →  type "agents"  →  Enter

# Create window 2
Ctrl+b  c
Ctrl+b  ,   →  type "git"     →  Enter

# Create window 3
Ctrl+b  c
Ctrl+b  ,   →  type "monitor" →  Enter

# Go back to window 1
Ctrl+b  1
```

Switch between windows: `Ctrl+b` then the window number (`1`, `2`, `3`).

### 7.3 Key tmux commands reference

| Action | Keys |
|---|---|
| Attach to session | `tmux attach -t work` (or just `work`) |
| Detach (leave running) | `Ctrl+b  d` |
| New window | `Ctrl+b  c` |
| Switch to window N | `Ctrl+b  N` |
| Rename window | `Ctrl+b  ,` |
| Split pane vertically | `Ctrl+b  \|` |
| Split pane horizontally | `Ctrl+b  -` |
| Navigate panes | `Ctrl+b  h/j/k/l` |
| Scroll mode (read agent output) | `Ctrl+b  [` then arrow keys, `q` to exit |
| Kill current window | `Ctrl+b  &` |
| List sessions | `tmux ls` |
| Reload tmux config | `Ctrl+b  r` |

---

## Part 8 — Daily Workflow

### 8.1 Connect from iPhone

1. Ensure Tailscale is connected on your iPhone (VPN toggle in Settings or the app)
2. Open ShellFish
3. Tap your VM host to connect
4. Type `work` — you are in your tmux session

### 8.2 Start an agentic coding task

In window 1 (agents), navigate to your repo and start Claude Code:

```bash
cd ~/your-repo
claude
```

Claude Code runs interactively. You can also use it in headless mode for
longer-running tasks:

```bash
claude -p "Add rate limiting middleware to all API routes and write integration tests"
```

You can switch to window 3 (monitor) with `Ctrl+b 3` and watch output, or
disconnect entirely — the task keeps running in tmux.

### 8.3 Review changes and create a PR branch

Switch to window 2 (git):

```bash
Ctrl+b  2
cd ~/your-repo

git diff
git status

git checkout -b feat/rate-limiting
git add -A
git commit -m "feat: add rate limiting middleware with integration tests"
gp   # alias for: git push origin HEAD

gh pr create \
  --title "feat: add rate limiting middleware" \
  --body "Implemented by Claude Code agentic session." \
  --base main
```

`gh` will print the PR URL. Open it in Mobile Safari on your iPhone to review
before merging.

---

### Keep Claude Code updated

```bash
npm update -g @anthropic-ai/claude-code
```

### If Claude Code auth expires

Sessions last a long time but do eventually expire. Re-authenticate with:

```bash
claude /logout
claude
# Open the new URL and sign in again
```

### VM disk space

The cpx21 has 40GB of disk. Agent sessions don't produce much disk usage,
but if you clone many large repos, check with:

```bash
df -h
du -sh ~/*/
```

### Keeping the VM's OS updated

Run periodically (safe to do in window 3 while agents run in window 1):

```bash
sudo apt update && sudo apt upgrade -y
```

### Destroying and recreating VMs

With Tailscale, VMs are disposable. Terraform auto-generates a fresh
Tailscale auth key on each apply:

```bash
cd hcloud-terraform/infra

# Destroy
terraform destroy

# Recreate (from snapshot ~30s, from scratch ~5 min)
terraform apply

# SSH in via Tailscale as soon as cloud-init finishes
ssh root@claude-research
```

### Resize to a bigger server temporarily

Edit `server_type` in `terraform.auto.tfvars`, then:
```bash
terraform apply
```

---

## Addendum — Agent Orchestrators

Claude Code is powerful on its own, but you can layer an agent orchestrator
on top for multi-agent workflows. This VM setup is orchestrator-agnostic —
here are some options that have been tested or are worth exploring:

### Claude Flow v3

[claude-flow](https://github.com/ruvnet/claude-flow) provides multi-agent
swarms with a SPARC workflow (Specification, Pseudocode, Architecture,
Refinement, Completion). It is initialized per repo, not globally.

```bash
cd ~/your-repo
npx claude-flow@v3alpha init
```

This creates a `.claude/` directory with agent definitions, slash commands,
and workflow components. Register it as an MCP server to give Claude Code
access to its tools natively:

```bash
claude mcp add claude-flow -- npx -y claude-flow@latest mcp start
claude mcp list   # verify
```

Run a task:

```bash
npx claude-flow@v3alpha --agent coder \
  --task "Add rate limiting middleware to all API routes"
```

Or use the structured SPARC workflow for larger tasks:

```bash
npx claude-flow@v3alpha /sparc "Refactor auth module to support OAuth2"
```

Update claude-flow:

```bash
npx claude-flow@v3alpha init upgrade --add-missing
```

### Other orchestrators

Any orchestrator that works with Claude Code or the Anthropic API can run
on this VM. The key requirements are:

- Runs on Linux x86_64 (Ubuntu 24.04)
- Can authenticate via Claude Code OAuth or an API key
- Works within a tmux session (no GUI required)

Examples worth evaluating: Claude's built-in `/claude-code-agent-sdk`,
custom MCP tool servers, shell-based agent scripts, or any framework that
can drive Claude Code in headless mode.
