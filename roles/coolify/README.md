# Role: `coolify`  — ⚠️ phase2 · install path unproven until R7

Captures the **host side of Coolify** so a rebuild can stand it back up. Recovery gap **R4**
([`docs/RECOVERY-GAP-PLAN.md`](../../docs/RECOVERY-GAP-PLAN.md)).

## What it manages
- **Install** (rebuild only): runs the official Coolify installer pinned to `coolify_version`
  (4.1.2) **only when `/data/coolify` is absent** — so the running box is never reinstalled.
- **Custom host glue** (vendored verbatim): `coolify-autostart.sh`,
  `coolify-proxy-socket-watchdog.sh`, `docker-update-check.sh`,
  `restart-coolify-proxy-after-docker.sh` + their systemd units (these work around the proxy /
  docker.sock incidents). No-op on the live box.

## What it does NOT manage (by design)
- **Coolify's app state** — which ~20 apps exist, their env, settings — is **data** in
  `/data/coolify` + `coolify-db`, restored from **backrest** (Pillar 4), then Coolify redeploys the
  apps from their GitHub repos (Pillars 2+3). See [`docs/DISASTER-RECOVERY.md`](../../docs/DISASTER-RECOVERY.md).
- The ~20 app containers themselves (Coolify owns them).

## Status
The **glue scripts + units** are safe and verified no-op on prod. The **install path is UNPROVEN**
until the R7 rebuild-and-diff test on a throwaway box — verify the installer's version-arg syntax
and the full restore there before trusting it. Gated to phase2.
