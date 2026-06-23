# Project status — phased execution (plan §9)

The golden rule: **no CI auto-apply until idempotency is clean AND the risky roles are proven on a
throwaway host.** Each phase ends with a GATE that must pass before the next begins.

| Phase | What | State |
|---|---|---|
| **0** | Observe & scaffold (zero host changes) | ✅ **done** — scaffold + live discovery reconciled (DISCOVERY-2026-06-23) |
| **1** | Non-disruptive roles: `motd` → `base` → `users` → `dns_hardening` → `backrest_watchdog` | ✅ **APPLIED to prod 2026-06-23; gate passed** (2nd run = 0 changes) |
| **2** | Risky roles: `firewall` → `docker` → `cloudflared_coolify` (+`cron_glue`) | ⏳ roles authored & gated (`enable_phase2`), not applied |
| **3** | Secrets migration to 1Password, one at a time (table in plan §5.2) | ⛔ not started |
| **4** | CI auto-apply (`ENABLE_AUTO_APPLY`), drift detection on, fold in DO droplet | ⛔ not started |

## What's done (Phase 0 scaffold)
- Repo structure, `ansible.cfg`, `.gitignore` (secret patterns), `.ansible-lint`, `requirements.yml`.
- `bin/discover.sh` to capture live host state (run it on the box; changes nothing).
- All roles authored with READMEs and the §4a safety rails baked in.
- CI: `check.yml` (PR dry-run), `apply.yml` (gated off via `ENABLE_AUTO_APPLY`), `drift.yml` (daily check-only).
- Cloud-init bootstrap template (§5.4).
- **Agent governance:** `AGENTS.md` + `CLAUDE.md` (repo-side rules for AI sessions) and the
  `motd` role (on-box login banner) — so every agent/human is told to route changes through this repo.
  Rolled out the rule beyond this repo (2026-06-23): global `~/.claude/CLAUDE.md` + `~/.codex/AGENTS.md`,
  and an `AGENTS.md` policy section in all 12 u2giants repos (3 direct-to-main where a ruleset blocks
  branches; 9 as PRs awaiting merge).
- **Local validation passed (2026-06-23):** `ansible-lint` clean (2 intentional warnings) and
  `ansible-playbook --syntax-check` green, run from WSL.

## Immediate next steps
1. ~~Run discovery; reconcile vars.~~ ✅ done (DISCOVERY-2026-06-23).
2. ~~Apply Phase 1 to prod; prove idempotency.~~ ✅ done — applied as root over Tailscale from
   WSL; second run = 0 changes. Governance banner live in `/etc/motd`.
3. **Phase 2 (risky):** stand up a scratch host, prove `firewall`/`docker`/`cloudflared_coolify`
   there (rebuild-and-diff), then prod in a maintenance window. `docker`/`cloudflared` daemon.json
   + units already captured verbatim; firewall needs the live `iptables-save` captured into mode A.
4. **CI access (Phase 4 enabler):** Tailscale `tag:ci` ephemeral auth + 1Password SA token as
   GitHub secrets, so the pipeline runs instead of local WSL.
5. Merge the 9 governance PRs in the app repos when ready (each may trigger a Coolify redeploy).

## Open questions for the owner (plan §10)
- CI runner network path: Tailscale (recommended) vs public-IP SSH.
- Confirm this box is **Hetzner Cloud** (cloud-init `user-data`) vs **Robot/dedicated** (`installimage`).
- Pushing to this repo / enabling auto-apply both need explicit owner approval.
