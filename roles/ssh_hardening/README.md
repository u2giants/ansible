# Role: `ssh_hardening`  — ⚠️ access-sensitive · phase1

Enforces the SSH access policy via a `/etc/ssh/sshd_config.d/20-access-policy.conf` drop-in.

## Policy

| | Public internet | Trusted (Tailscale / Cloudflared / localhost) | VPS console |
|---|---|---|---|
| **root** | ❌ never | ✅ key **or** password (`ssh_trusted_root_password`) | ✅ always (local login, not sshd) |
| **`ai`** (`ssh_internet_user`) | ✅ key or password | ✅ key or password | n/a |
| other users | ❌ | key or password | n/a |
| passwords | off, except `ai` | **on** (trusted network) | n/a |

Rationale for passwords-on-trusted: a machine with no SSH key can still get in over Tailscale
(the break-glass the owner asked for). Set `ssh_trusted_root_password: false` for key-only root.

"Trusted" = `ssh_trusted_sources` (Tailscale v4/v6 ranges + `127.0.0.1`/`::1`). Cloudflared SSH
hands off from localhost, so it counts as trusted. The **VPS provider console** is a local
console login independent of sshd, so root can always get in there — the ultimate break-glass.

## Why it's reasonably safe to apply
- The full merged config is validated with `sshd -t`; if invalid, the drop-in is **auto-reverted**
  and sshd is **not** reloaded (previous config stays active).
- It **reloads** (not restarts) sshd, so existing sessions survive.
- The operator/automation connects as root over Tailscale (a trusted source), so applying this
  does not cut the control path. If anything is wrong, the VPS console restores access.

## Prerequisites
- The `ai` account must have a login method: the `users` role installs its authorized key
  (`users_authorized_keys`). If `ssh_ai_allow_password: true`, **the owner must set a strong `ai`
  password** (`passwd ai` on the box / via console) — Ansible does not set passwords.

## Caveats / verify
- `ssh_ai_allow_password: true` exposes password login on the public port — a brute-force surface.
  fail2ban mitigates; prefer a strong password (or set this `false` for key-only later).
- Verify the Tailscale IPv6 prefix in `ssh_trusted_sources` matches this tailnet (`tailscale ip -6`).
- This role does not change which ports sshd listens on (`/etc/ssh/sshd_config.d/10-ports.conf`,
  ports 22 + 1904) or the firewall; it governs *who* may log in *from where*.

## ⚠️ Coolify / Docker deploys depend on this policy

**Coolify deploys apps by SSHing in as `root` from the Docker bridge network `10.0.1.0/24`**
(to `host.docker.internal`, observed source `10.0.1.15`). The role grants the Docker bridge
**root key-only** access via **two** list variables (see `defaults/main.yml`):

```yaml
# Matched FIRST in the template, so root stays prohibit-password here even though
# root-password break-glass is enabled for the Tailscale/loopback sources.
ssh_trusted_root_key_only_sources:
  - "10.0.1.0/24"   # Coolify / Docker internal bridge — Coolify SSHes as root to deploy apps

# Union list — used to build the public-internet exclusion so the bridge is NOT
# caught by the `AllowUsers ai` (no-root) bucket. Must also contain the bridge.
ssh_trusted_sources:
  - "10.0.1.0/24"
```

This is safe and tightly scoped: Coolify's authorized key in `/root/.ssh/authorized_keys` is
already pinned to `from="10.0.1.0/24"` and is **key-only** (no password) — and the key-only
`Match` block means root gets **no** password access over the bridge either.

**Do-not-repeat warning.** Any future tightening of this role's access policy **MUST preserve root
SSH (key-only) from the Docker bridge `10.0.1.0/24`** — keep it in **both**
`ssh_trusted_root_key_only_sources` and `ssh_trusted_sources`, and never move it into
`ssh_trusted_root_password_sources`. Remove it and Coolify's root SSH falls into the "public internet" bucket
(`AllowUsers ai`, root refused) and **ALL app deploys on the host silently break** — popcrm-web,
poppim-web, popdam, monitor, hiclaw, etc. There is **no obvious error in GitHub Actions**: the
deploy trigger still returns "queued", but the container is never replaced and the live site keeps
serving the old bundle. Host `auth.log` shows `User root from 10.0.1.x not allowed because not
listed in AllowUsers`, and Coolify marks its localhost server `is_reachable=false, is_usable=false`.

Before changing this role's access policy, verify Coolify can still `is_usable=true` its localhost
server and that a test app deploy actually swaps the container. See
[`docs/incidents/2026-07-15-coolify-ssh-deploy-breakage.md`](../../docs/incidents/2026-07-15-coolify-ssh-deploy-breakage.md).
