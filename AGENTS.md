# Terraform Best Practices for Hetzner WireGuard VPN

Lessons learned while building and iterating on this project.

## Environment Variables in Docker Compose

### ✅ Use `.env` file exclusively, avoid mixed approaches

**Problem:** Mixing `environment:` section in docker-compose.yml with `.env` file creates escaping nightmares in heredocs.

```yaml
# ❌ DON'T DO THIS
environment:
  WG_PORT: $${WG_PORT}      # Double-$$ to escape shell interpolation
  WG_HOST: 0.0.0.0          # Hardcoded in YAML
env_file: .env
```

**Solution:** Move all env vars to `.env`, reference only via `env_file`:

```yaml
# ✅ DO THIS
env_file: .env
```

```bash
# In provisioning script
cat > .env << ENVEOF
LANG=en
WG_HOST=$SERVER_IP
WG_PORT=$WG_PORT
WG_MTU=1420
# ... all other vars
ENVEOF
```

**Why:** Plain `KEY=VALUE` in `.env` has no shell escaping issues. Values are populated by the script before file creation, so `$SERVER_IP` is just normal variable substitution.

---

## Dynamic Values in Cloud-Init

### ✅ Fetch values early, use them throughout

**Problem:** Trying to pass dynamic values (server IP, etc.) through terraform template variables doesn't work—values don't exist until the instance is created.

**Solution:** Fetch all needed values in the provisioning script early, then use them in dependent configs:

```bash
# Fetch early
SERVER_IP=$(curl -s http://checkip.amazonaws.com 2>/dev/null | ...)

# Use in .env
cat > .env << ENVEOF
WG_HOST=$SERVER_IP
ENVEOF

# Use in client configs
cat > admin/wg0.conf << CONFEOF
Endpoint = $SERVER_IP:$WG_PORT
CONFEOF
```

**Why:** Allows you to generate correct configs that depend on runtime-determined values without convoluted terraform interpolation.

---

## WireGuard Configuration

### ✅ Set WG_HOST to actual public IP (not 0.0.0.0)

**Problem:** Setting `WG_HOST: 0.0.0.0` causes wg-easy to generate peer configs with invalid endpoints:
```conf
Endpoint = 0.0.0.0:51820  # ❌ Won't connect
```

**Solution:** Set WG_HOST to the server's actual public IP or DNS name:

```bash
WG_HOST=$SERVER_IP  # E.g., 203.0.113.45
```

This ensures new peer configs have correct endpoints:
```conf
Endpoint = 203.0.113.45:51820  # ✅ Works
```

**Scaling note:** Once DNS is set up (e.g., `vpn.skillrev.in`), you can use that instead and rescale without reissuing peer configs.

---

## Files Organization

### ✅ Keep provisioning script within cloud-init

Writing the provisioning script as part of `write_files` in cloud-init keeps everything in one place and avoids separate file management.

---

## Secrets Management

### ✅ Store secrets in .env, not in docker-compose YAML

```bash
# ✅ DO THIS
cat > .env << ENVEOF
PASSWORD_HASH=${wg_admin_password_hash}
ENVEOF
```

```yaml
# ❌ DON'T DO THIS
environment:
  PASSWORD_HASH: ${wg_admin_password_hash}  # Exposed in docker-compose.yml
```

**Why:** `.env` is easier to exclude/rotate, and it's clearer that these are secrets.

---

## Logging & Debugging

### ✅ Log major steps with timestamps

```bash
echo ">>> [$(date +%T)] Starting WireGuard provisioning..."
echo ">>> [$(date +%T)] Server IP: $SERVER_IP"
echo ">>> [$(date +%T)] Created .env with WG_HOST=$SERVER_IP"
```

Makes cloud-init logs easier to follow when troubleshooting.
