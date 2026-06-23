# Role: `docker`  — ⚠️ RISKY · phase2

Manages **only** `/etc/docker/daemon.json` and **pins** the Docker engine version. It
**never restarts Docker** — a restart hits Coolify + ~20 containers and causes `docker.sock`
staleness (the June 2026 outage). Read plan §3.3 / §4a.

## What it does
- Holds `docker-ce` at its installed version (`dpkg_selections … hold`) so an apply can never
  upgrade the engine.
- Writes `daemon.json` from a dict that guarantees `live-restore: true` and — critically —
  **no `dns` key** (a `dns` key pointing at `127.0.0.53` breaks every container, §3.3).
- A `daemon.json` change `notify`s a **manual-gated** handler that only prints "restart
  required in a maintenance window" — it does **not** restart the daemon.

## What it deliberately does NOT do
- Install/upgrade Docker. (Engine install is captured at bootstrap; this role only configures.)
- Manage containers, Compose stacks, or anything Coolify owns.
- Restart `dockerd`. Ever. Automatically.

## Applying a daemon.json change for real
After merge, in a maintenance window, a human runs `sudo systemctl restart docker` then
`docker restart backrest` (docker.sock staleness — also covered by `backrest_watchdog`).
