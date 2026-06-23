# Role: `backrest_watchdog`  — [non-disruptive · phase1]

Installs the systemd timer that self-heals the **backrest** backup agent after a host Docker
restart leaves it holding a stale `/var/run/docker.sock` handle (plan §3.4 — the June 2026
outage that silently broke database backups for 4 days).

## What it does
- Installs `/usr/local/bin/backrest-dump-watchdog.sh` (host-side, not in a container).
- Installs `backrest-dump-watchdog.service` (oneshot) + `.timer` (every 15 min), then enables it.
- The real watchdog heals three conditions: container down → `compose up`; stale docker.sock
  handle → restart + trigger a dump; freshest dump stale → trigger a dump.

## Canonical source — vendored VERBATIM
The script + units are copied **byte-for-byte** from the live box (captured 2026-06-23; their
canonical home is the **`backrest-wiz` repo → `hetzner-producer/`**). Deploying them verbatim
reproduces the exact prod watchdog and keeps re-applies idempotent. **Do not "improve" these
files here** — an earlier scaffolded version was simpler and would have regressed the real one,
which a prod `--check` caught. Update them only to track the canonical repo.

## Why it's safe
Host-side only. The worst it does is restart the single `backrest` container — no effect on
Coolify, app containers, or the Docker daemon. Prefer this host-side path over anything that
depends on `docker.sock` from inside a container (plan §3.4 lesson).
