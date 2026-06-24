# Role: `ssh_hardening`  — ⚠️ access-sensitive · phase1

Enforces the SSH access policy via a `/etc/ssh/sshd_config.d/20-access-policy.conf` drop-in.

## Policy

| | Public internet | Trusted (Tailscale / Cloudflared / localhost) | VPS console |
|---|---|---|---|
| **root** | ❌ never | ✅ key-only | ✅ always (local login, not sshd) |
| **`ai`** (`ssh_internet_user`) | ✅ key or password | ✅ key or password | n/a |
| other users | ❌ | key-only | n/a |
| passwords | off, except `ai` | off, except `ai` | n/a |

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
