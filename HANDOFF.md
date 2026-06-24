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

**Phase 2 risky roles were PROVEN on a throwaway DigitalOcean scratch box on 2026-06-24**
(Ubuntu 24.04, Docker 29.6.0). Results:
- **`firewall`** — applied mode B (generic default-DROP) with the auto-revert armed: box stayed
  reachable, SSH/80/443/loopback/established/tailscale0 allowed, auto-revert timer armed then
  disarmed cleanly. The risky lockout/auto-revert mechanics work. (Note: the role is intentionally
  **not** "0 changes on re-run" — its staged snapshot/arm/apply/disarm are imperative command
  tasks; the end state is stable.) Prod uses **mode A** (the captured hetz ruleset), which passed
  `iptables-restore --test` but has NOT been applied to prod.
- **`docker`** — deployed `daemon.json` verbatim, held the package, did **not** restart the
  daemon; **idempotent** (2nd run = 0 changes). **APPLIED TO PROD 2026-06-24**: only change was
  the package hold (`daemon.json` already matched); Docker not restarted (27 containers stayed
  up); re-run = 0 changes.
- **`cloudflared_coolify`** — added `cloudflared_deploy_only` (default false) to deploy the
  unit+env+reload without bringing the tunnel up; proven on scratch (secure env `600 root`, valid
  unit); **idempotent**. Prod still needs the real token (1Password) + a careful tunnel restart.
- **CI workflows** — written and lint-clean, but **not active**: no GitHub secrets exist and
  `ENABLE_AUTO_APPLY` is unset, so `apply.yml` is check-only. Applies are manual from WSL for now.

The scratch box (`165.227.208.178`) is to be **destroyed** by the owner once results are reviewed.

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

Phase 2 is proven on scratch. Remaining, in order of safety:

1. ~~**Apply `docker` to prod**~~ ✅ done 2026-06-24 (no-op + package hold; no restart).
2. **Apply `firewall` to prod** in a maintenance window — uses mode A (captured hetz ruleset);
   the auto-revert (proven on scratch) is the safety net. Watch SSH/Tailscale + Docker networking.
3. **Apply `cloudflared_coolify` to prod** — needs the real Tunnel 1 token from 1Password
   (`op://vibe_coding/cf-tunnel-coolify`); restarts the live tunnel, so validate reconnect.
   Overlaps with Phase 3 (secrets).

Then Phase 3 (secrets) and Phase 4 (CI auto-apply). Other options if not continuing Phase 2:
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
