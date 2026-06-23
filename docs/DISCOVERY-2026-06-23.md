# Live discovery — hetz — 2026-06-23

Captured read-only from the box (`ssh vps`, root) and reconciled into the roles. Raw output is
kept locally in `discovery/` (gitignored — it contains ports/iptables/config internals).

## Confirmed & encoded
- **OS:** Ubuntu 24.04.4 LTS, kernel 6.8.0-124. **Timezone:** `America/New_York` (was scaffolded
  as UTC → corrected in `group_vars`).
- **Docker:** 29.6.0 (`5:29.6.0-1~ubuntu.24.04~noble`) → pinned in the `docker` role.
- **`daemon.json`:** captured verbatim → `roles/docker/files/daemon.json`. Keeps `log-opts`,
  `default-address-pools` (`10.0.0.0/8`), `dns: [1.1.1.1, 8.8.8.8]`, `live-restore: true`.
- **resolved fallback-dns.conf:** matches the `dns_hardening` role exactly.
- **cloudflared-coolify.service:** enabled; `/etc/cloudflared/coolify-tunnel.env` present (root-only).
- **fail2ban + netfilter-persistent:** enabled (firewall role assumptions hold).
- **backrest-dump-watchdog.timer:** already present on the box — the `backrest_watchdog` role matches it.
- **Cron:** root `tailscale ping` keepalive (*/4) and ai `sync-infra-docs.sh` (*/15) → encoded in `cron_glue`.

## ⚠️ Plan corrected by reality
- **`daemon.json` DOES carry a `dns` key** (public resolvers) — the plan said "no dns key." The
  real invariant is "never point dns at `127.0.0.53`." Plan §3.3/§3.5 and the `docker` role were
  corrected. **This was a latent landmine:** the original scaffold would have wiped the real
  `daemon.json` down to just `live-restore`.

## ⚠️ Needs your attention (discrepancies / decisions)
1. **`socks5-home-tunnel.service` is ENABLED** on the box, but the plan says it must stay
   disabled / never enabled (§3.5). Please confirm whether that's intentional. (Not touched.)
2. **Extra login users `nova` and `nasbridge`** exist (plan only documented `ai`/`root`). The
   `users` role manages only `ai`. Tell me if these should be encoded (and their key policy).
3. **`sudoers.d/ai`** already exists; the `users` role writes `90-ai`. Harmless (both NOPASSWD)
   but I should align the filename to avoid two files — confirm and I'll match the existing one.

## Intentionally NOT managed (out of scope per plan)
- **App-layer timers/crons:** `popcrm-*`, `plm-sync`, and the 5 `/worksp/hiclaw/*-keeper.sh`
  minute crons — owned by their app repos (§4a), not host Ansible.
- **Coolify-coupled glue:** `coolify-autostart`, `coolify-proxy-*` services/scripts,
  `restart-coolify-proxy-after-docker.sh`, `docker-update-check.sh` — Coolify's territory.

## Candidate for a future role
- **`dns-watchdog.timer`** is a host-level glue watchdog not yet wrapped in a role. Worth adding
  alongside `backrest_watchdog` in a later pass (host-side self-heal pattern, §3.4).

## Firewall reality (for Phase 2)
INPUT policy is **ACCEPT** with a targeted SSH lockdown: port 22 is allowed only from Tailscale
(`100.64.0.0/10`), localhost, and `10.0.1.0/24`, then **dropped** for everyone else (public SSH
is closed — Tailscale is the only way in, confirming the §4a lifeline). This differs from the
scaffold's scratch-only default-DROP template, which is why the `firewall` role uses **mode A**
(verbatim `iptables-save` capture) for prod. Full capture happens when we prove the role on the
scratch host.
