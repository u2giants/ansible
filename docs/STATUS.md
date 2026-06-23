# Project status — phased execution (plan §9)

The golden rule: **no CI auto-apply until idempotency is clean AND the risky roles are proven on a
throwaway host.** Each phase ends with a GATE that must pass before the next begins.

| Phase | What | State |
|---|---|---|
| **0** | Observe & scaffold (zero host changes) | 🟡 **scaffold done; live discovery + scratch host pending** |
| **1** | Non-disruptive roles: `base` → `users` → `dns_hardening` → `backrest_watchdog` | ⏳ roles authored, not applied |
| **2** | Risky roles: `firewall` → `docker` → `cloudflared_coolify` (+`cron_glue`) | ⏳ roles authored & gated (`enable_phase2`), not applied |
| **3** | Secrets migration to 1Password, one at a time (table in plan §5.2) | ⛔ not started |
| **4** | CI auto-apply (`ENABLE_AUTO_APPLY`), drift detection on, fold in DO droplet | ⛔ not started |

## What's done (Phase 0 scaffold)
- Repo structure, `ansible.cfg`, `.gitignore` (secret patterns), `.ansible-lint`, `requirements.yml`.
- `bin/discover.sh` to capture live host state (run it on the box; changes nothing).
- All roles authored with READMEs and the §4a safety rails baked in.
- CI: `check.yml` (PR dry-run), `apply.yml` (gated off via `ENABLE_AUTO_APPLY`), `drift.yml` (daily check-only).
- Cloud-init bootstrap template (§5.4).

## Immediate next steps (require the live box + owner)
1. Run `bin/discover.sh` on `hetz`; reconcile `inventory/group_vars/all.yml` and role vars with reality.
2. Stand up a cheap throwaway scratch host; add it to `inventory/hosts.ini` under `[scratch]`.
3. Provision CI access: Tailscale `tag:ci` ephemeral auth + 1Password Service-Account token.
4. Prove Phase 1 roles on scratch, then prod (`--check` then real). **GATE:** second run = 0 changes.

## Open questions for the owner (plan §10)
- CI runner network path: Tailscale (recommended) vs public-IP SSH.
- Confirm this box is **Hetzner Cloud** (cloud-init `user-data`) vs **Robot/dedicated** (`installimage`).
- Pushing to this repo / enabling auto-apply both need explicit owner approval.
