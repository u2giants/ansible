# Recovery gap plan — getting to 100% rebuildable

Concrete plan to close the gap between today's state and the mission in
[`DISASTER-RECOVERY.md`](DISASTER-RECOVERY.md): **every piece of software on `hetz` reproducible
from code.** Based on a full software audit of the live box (2026-06-24).

## What's captured today vs. the gap

| Category | On the box | In Ansible today |
|---|---|---|
| Base packages (12) | ✅ | ✅ |
| Host config (firewall, DNS, SSH, Docker daemon.json, users, cron, motd, backrest watchdog, Tunnel 1 unit) | ✅ | ✅ |
| **10 third-party apt repos** (1password, azure-cli, cloudflared, docker, google-chrome, google-cloud-sdk, nodesource, pgdg, tailscale) | ✅ | ❌ |
| **Third-party CLIs** (`gcloud`, `az`, `gh`, `op`, `psql`, `restic`, `rg`, node/npm) | ✅ | ❌ |
| **Non-apt binaries** (`go`, `supabase`, `codex`, `cloudflared` binary) | ✅ | ❌ |
| **Global npm tools** (`@anthropic-ai/claude-code`, `@google/gemini-cli`, corepack, ncu) | ✅ | ❌ |
| **Docker engine install** (repo + package) | ✅ | ⚠️ pinned only — repo/install not managed |
| **Coolify** install + glue scripts (`coolify-autostart.sh`, `coolify-proxy-socket-watchdog.sh`, `restart-coolify-proxy-after-docker.sh`, `docker-update-check.sh`) | ✅ | ❌ |
| ~202 manual apt packages (full set) | ✅ | ⚠️ only 12 curated |
| App containers + code + data | ✅ | N/A — Coolify + GitHub + backrest (correct) |

## Guiding principle that makes this safe
Almost all of this is **additive and idempotent on the live box**: declaring "install `gcloud`"
when `gcloud` is already installed is a **no-op**. So we can encode it against prod with near-zero
risk, and the *real* proof is a **rebuild-and-diff on a throwaway box** (R7).

## The plan (recovery phases R1–R7)

### R1 — Vendor apt repos + their packages  ✅ DONE (2026-06-24)
Built `apt_repos` (10 repos + 9 keys, verbatim) and `packages` (gcloud, az, gh, op, nodejs,
postgresql-client, restic, ripgrep, tailscale, google-chrome-stable) roles; applied to prod via
the live CI pipeline as a clean no-op (keys/sources matched byte-for-byte). Original plan below:
- New role **`apt_repos`**: declare all 10 vendor repos + GPG keys (`ansible.builtin.deb822_repository`).
- New role **`packages`** (or extend `base`): install everything from them — `google-cloud-cli`,
  `azure-cli`, `gh`, `1password-cli`, `nodejs`, `postgresql-client`, `restic`, `ripgrep`,
  `tailscale`, `cloudflared`, `google-chrome-stable`, plus the curated remainder of the 202 manual
  packages.
- Verify: `apt install` of already-present packages = 0 changes (idempotent) on prod.

### R2 — Non-apt CLIs (binaries / scripts / npm)  ✅ DONE (2026-06-24)
Built `dev_tools` role: Go 1.26.4 (tarball), supabase 2.98.2 (.deb), global npm CLIs
(`claude-code` 2.1.160, `gemini-cli` 0.44.1, `corepack`, `npm-check-updates`), codex 0.141.0
(`@openai/codex`), and the `cloudflared` symlink. All version-guarded → no-op on prod (verified).
Original plan below:
- New role **`dev_tools`**: install `go` (Go toolchain), `supabase`, `codex`, the global npm tools
  (`@anthropic-ai/claude-code`, `@google/gemini-cli`) — each from its official binary/script,
  **version-pinned** to what's live now (captured during the work).
- Verify: versions match; re-run = 0 changes.

### R3 — Docker engine install (not just config)  ✅ DONE (2026-06-24)
Extended the `docker` role to install `docker-ce`/`-cli`/`containerd.io`/buildx/compose from the
Docker apt repo (configured by `apt_repos`), ahead of the pin. No-op on prod (verified). Original
plan below:
- Extend the **`docker`** role: add the Docker apt repo + `docker-ce` install ahead of the pin, so
  a **bare** box gets the engine (today the role assumes it's already there). Keep the version pin
  and never-auto-restart guards.

### R4 — Coolify
- New role **`coolify`**: reproduce the Coolify install (its installer), and vendor the host-level
  Coolify glue scripts (the four in `/usr/local/bin`). Document that Coolify's *state* (which apps,
  their env) is **data**, restored from backrest (Pillar 4), not code.
- This is the most involved role — Coolify owns a lot; we manage its **install + host glue**, not
  its internal app state.

### R5 — The "rebuild everything" runbook
- New doc **`RUNBOOK-REBUILD.md`**: the exact ordered procedure (provision → cloud-init bootstrap →
  Ansible host+tools+Coolify → backrest restore → Coolify redeploys from GitHub → authenticate →
  verify), with the commands a future session runs. Include the **app-repo inventory** and the
  **backrest restore** steps.

### R6 — Software-inventory drift (so the gap can't silently reopen)
- New `bin/discover-software.sh` (full inventory) + a CI check that compares the box's installed
  apt packages / `/usr/local/bin` / global npm against what Ansible declares, and **flags anything
  not captured.** This makes "someone installed a tool by hand" a loud signal, extending drift
  detection from config to *software inventory*.

### R7 — Rebuild-and-diff validation (the real proof)
- Provision a throwaway box, run bootstrap + the full pipeline + a restore, and **diff** it against
  prod: package lists, binaries, enabled services, listening ports, Coolify apps. Every difference
  is a bug to chase to zero. This is what *proves* the mission is met (§8.3 of the plan).

## Order & dependencies
R1 → R2 → R3 can proceed immediately (additive, low-risk, mostly no-op on prod). R4 (Coolify) is
the big one and benefits from R7's scratch box. R5/R6 are docs+CI. R7 needs a throwaway box and is
the final gate.

## Honest caveats
- The AI CLIs (`codex`, `gemini`, `claude-code`) and `supabase` move fast — pinning a version makes
  rebuilds reproducible, but the pins need occasional bumping.
- Coolify recovery is **install (code) + state (data)**; a clean rebuild depends on the backrest
  backups of `coolify-db` + `/data/coolify` being current and restorable (a backrest concern).
- "Authenticate everything" stays a manual step by design — the owner logs in; nothing stores those
  interactive logins.
