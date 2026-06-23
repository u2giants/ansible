# Role: `dns_hardening`  — [non-disruptive · phase1]

Reapplies the host-resolver half of the **May 2026 DNS-cascade outage** fix (plan §3.3) so a
rebuilt box is never one DNS hiccup away from taking down every tunnel and oauth2-proxy
container.

## What it does
- Writes `/etc/systemd/resolved.conf.d/fallback-dns.conf` with
  `FallbackDNS=1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4`.
- Restarts `systemd-resolved` (host-only, brief).

## What it deliberately does NOT do
- It does **not** touch `/etc/docker/daemon.json`. The Docker side of the §3.3 fix
  (`live-restore: true`, and crucially **no `dns` key**) is owned by the `docker` role, so the
  two never fight over the same file.
- It does **not** set any per-container DNS — `oauth2-proxy`'s `dns: [1.1.1.1, 8.8.8.8]` lives
  in its own compose file (manually managed, not Coolify, not Ansible).

## Why it's safe
Restarting `systemd-resolved` is a sub-second host DNS blip and does not restart Docker, so no
container is recreated.
