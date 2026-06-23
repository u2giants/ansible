# HANDOFF

Continuation doc for a new developer or AI session with no prior chat context. When the work
below is fully complete, **delete this file** (and remove its mentions from `README.md` and
`AGENTS.md`). Canonical rules: [`AGENTS.md`](AGENTS.md).

## What is being built and why

Turn the hand-built Hetzner host `hetz` into a code-managed, rebuildable system (host/OS layer
only — Coolify owns the apps), with one serialized apply path so concurrent AI sessions can't
cause drift. Phased plan with hard gates: [`docs/ANSIBLE-IMPLEMENTATION-PLAN.md`](docs/ANSIBLE-IMPLEMENTATION-PLAN.md) §9.

## Fully done

- **Phase 0 — scaffold + discovery.** Full repo structure; live state captured and reconciled
  into the roles ([`docs/DISCOVERY-2026-06-23.md`](docs/DISCOVERY-2026-06-23.md)). Corrected a
  near-miss where the `docker` role would have wiped the real `daemon.json` (see AGENTS §13).
- **Phase 1 — applied to prod (2026-06-23).** `motd`, `base`, `users`, `dns_hardening`,
  `backrest_watchdog` applied to `hetz` from WSL over Tailscale; **idempotency gate passed**
  (second run = 0 changes). Governance banner live in `/etc/motd`.
- **Agent governance rollout.** The "route host changes through Ansible" rule is in global
  Claude (`~/.claude/CLAUDE.md`) and Codex (`~/.codex/AGENTS.md`) memories, and in `AGENTS.md`
  of all 12 u2giants repos (popdam3, theoracle, compshop, popcrm-web, poppim-web,
  synology-monitor, albert-standards, backrest-wiz, seafile, hiclaw, devops-mcp, authentik).
- **Local validation:** `ansible-lint` clean (2 accepted warnings) + `--syntax-check` green in WSL.

## Partially done / current state

- **`firewall` role** — authored with mode A (verbatim `iptables-save` capture) and mode B
  (scratch). The live ruleset **is now captured** to `roles/firewall/files/hetz.rules.v4`/`.v6`
  (2026-06-23, counters zeroed, timestamps stripped; both pass `iptables-restore --test`). The
  role auto-loads them when `firewall_use_captured: true` (default). INPUT policy is ACCEPT with
  SSH locked to Tailscale (see AGENTS quirks). **Captured but UNPROVEN — not applied; must be
  validated on the scratch host first (do NOT run against prod even in `--check`).**
- **`docker` role** — `daemon.json` captured verbatim; engine pinned. Gated, not applied.
- **`cloudflared_coolify` role** — manages Tunnel 1 unit + token (from 1Password). Gated, not applied.
- **CI workflows** — written and lint-clean, but **not active**: no GitHub secrets exist and
  `ENABLE_AUTO_APPLY` is unset, so `apply.yml` is check-only. Applies are manual from WSL for now.

## Not started

- **Phase 3 — secrets migration to 1Password**, one at a time (table in plan §5.2). Needs vault access.
- **Phase 4 — enable CI auto-apply + drift alerts.** Needs `OP_SERVICE_ACCOUNT_TOKEN`, Tailscale
  `tag:ci` (`TS_OAUTH_CLIENT_ID`/`TS_OAUTH_SECRET`), and `ENABLE_AUTO_APPLY=true` as GitHub
  secrets/variables; then fold the DigitalOcean `backrest-wiz` droplet into the inventory.

## Decisions made (and why)

- **Reproduce reality, don't impose an ideal** — `daemon.json` and the backrest units are
  vendored verbatim from the box for byte-idempotency.
- **`docker` never auto-restarts; firewall has auto-revert; risky roles gated by `enable_phase2`**
  — safety against the documented outages (AGENTS §13).
- **Main-only git workflow**; commits use the owner's GitHub noreply email (privacy enabled).
- **Manual WSL applies for now** — CI secrets not yet provisioned; Phase 1 is non-disruptive.

## Dead ends / corrections

- The `docker` role's first version rebuilt `daemon.json` from a dict (would have dropped real
  keys) — replaced with a verbatim file + a narrow `127.0.0.53` assertion.
- The `backrest_watchdog` first version invented a simpler script — replaced with the real
  3-condition script/units from the box.
- `roles/base` wrote a journald drop-in without creating the parent dir — fixed.

## Exact next action

Pick one (each needs an owner-provided resource):

1. **Phase 2 (recommended):** owner spins up a cheap throwaway box (Hetzner/DO) → add it under
   `[scratch]` in `inventory/hosts.ini` → prove `firewall`/`docker`/`cloudflared_coolify` on
   scratch with a rebuild-and-diff (firewall ruleset already captured) → apply to prod in a
   maintenance window (`-e enable_phase2=true`). On scratch, set `firewall_use_captured=false`
   and `firewall_allow_no_docker=true` (the captured rules are hetz-specific).
2. **Phase 4:** create the GitHub secrets + `ENABLE_AUTO_APPLY`, then the pipeline runs applies
   instead of manual WSL.
3. **Phase 3:** migrate secrets into 1Password one at a time with validation/rollback (plan §5.2).

## Known risks / unknowns

- **`socks5-home-tunnel.service` is enabled** on the box but the plan says it should stay
  disabled — confirm intent with the owner (not touched).
- **Extra login users `nova`, `nasbridge`** exist; purpose unknown; `users` role manages only
  `ai`. Verify purpose before encoding (`getent passwd` on the box).
- `--check` is not fully reliable for command/shell tasks — prove risky roles on scratch, don't
  trust prod `--check` (plan §4a).
- A copy of the owner's `916-alien` SSH **private key** lives in WSL `~/.ssh/` to enable applies;
  replace with a dedicated CI key in Phase 4.
