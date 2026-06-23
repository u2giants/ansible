# Role: `docker`  — ⚠️ RISKY · phase2

Manages **only** `/etc/docker/daemon.json` and **pins** the Docker engine version. It
**never restarts Docker** — a restart hits Coolify + ~20 containers and causes `docker.sock`
staleness (the June 2026 outage). Read plan §3.3 / §4a.

## What it does
- Holds `docker-ce` at its installed version (`dpkg_selections … hold`) so an apply can never
  upgrade the engine. Pinned to `5:29.6.0-1~ubuntu.24.04~noble` (live on hetz 2026-06-23).
- Deploys `daemon.json` **verbatim** from `files/daemon.json` (captured from the live box, so
  re-applies are byte-idempotent). The real file keeps `log-opts`, `default-address-pools`,
  `dns: [1.1.1.1, 8.8.8.8]`, and `live-restore: true`.
- Asserts the real safety invariant: `live-restore` present and **`127.0.0.53` never appears**
  in the config. (Correction to plan §3.3: a `dns` key is fine — the landmine is specifically
  pointing it at the host resolver stub `127.0.0.53`, which is unreachable from containers.)
- A `daemon.json` change `notify`s a **manual-gated** handler that only prints "restart
  required in a maintenance window" — it does **not** restart the daemon.

## What it deliberately does NOT do
- Install/upgrade Docker. (Engine install is captured at bootstrap; this role only configures.)
- Manage containers, Compose stacks, or anything Coolify owns.
- Restart `dockerd`. Ever. Automatically.

## Applying a daemon.json change for real
After merge, in a maintenance window, a human runs `sudo systemctl restart docker` then
`docker restart backrest` (docker.sock staleness — also covered by `backrest_watchdog`).
