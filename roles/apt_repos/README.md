# Role: `apt_repos`  — [non-disruptive · phase1]

Recreates the **third-party APT repositories + their signing keys** that the host's CLIs and tools
come from. Without this, a rebuilt box has no way to install `gcloud`, `az`, `gh`, `op`, Node,
`postgresql-client`, Tailscale, Chrome, or Docker. Part of the recovery mission
([`docs/DISASTER-RECOVERY.md`](../../docs/DISASTER-RECOVERY.md), gap **R1**).

## What it does
- Deploys 9 signing keys (verbatim, `files/keyrings/*`) to `/usr/share/keyrings/` and
  `/etc/apt/keyrings/`.
- Deploys 10 source files (verbatim, `files/sources/*`) to `/etc/apt/sources.list.d/`:
  1password, azure-cli, cloudflared, docker, google-chrome (×2), google-cloud-sdk, nodesource,
  pgdg, tailscale.
- Refreshes the apt cache so later roles (`base`, `packages`, `docker`) can install from them.

## Why verbatim
The files are copied byte-for-byte from the live box, so applying to prod is a **no-op** (they
already match) and a rebuild reproduces the exact repos. Runs **first** in phase1.

## Safe to re-run
Idempotent — unchanged files = 0 changes, and `apt update` only runs if a repo/key changed.
