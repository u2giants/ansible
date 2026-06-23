# Role: `backrest_watchdog`  — [non-disruptive · phase1]

Installs the systemd timer that self-heals the **backrest** backup agent after a host Docker
restart leaves it holding a stale `/var/run/docker.sock` handle (plan §3.4 — the June 2026
outage that silently broke database backups for 4 days).

## What it does
- Installs `/usr/local/bin/backrest-dump-watchdog.sh` (host-side, not in a container).
- Installs `backrest-dump-watchdog.service` (oneshot) + `.timer`, then enables the timer.
- The watchdog probes whether the backrest container can still reach `docker.sock`; if not, it
  restarts **only that one container**.

## Canonical source
These units originate in the **`backrest-wiz` repo → `hetzner-producer/`** (`bin/` + `systemd/`).
This role vendors them so a rebuilt host re-creates the watchdog. Keep them in sync.

## Why it's safe
Host-side only. The worst it does is restart the single `backrest` container — no effect on
Coolify, app containers, or the Docker daemon. Prefer this host-side path over anything that
depends on `docker.sock` from inside a container (plan §3.4 lesson).
