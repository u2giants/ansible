# HANDOFF

Continuation doc for a new developer or AI session with no prior chat context. When the work
below is fully complete, **delete this file** (and remove its mentions from `README.md` and
`AGENTS.md`). Canonical rules: [`AGENTS.md`](AGENTS.md).

## What is being built and why

Turn the hand-built Hetzner host `hetz` into a code-managed, rebuildable system (host/OS layer
only — Coolify owns the apps), with one serialized apply path so concurrent AI sessions can't
cause drift. Phased plan with hard gates: [`docs/ANSIBLE-IMPLEMENTATION-PLAN.md`](docs/ANSIBLE-IMPLEMENTATION-PLAN.md) §9.

## Fully done

- **`ssh_hardening` — APPLIED TO PROD 2026-06-24, idempotent.** root is refused from the public
  internet (verified with a real refused connection + `sshd -T`); allowed by key **or password**
  from trusted sources (Tailscale + localhost/cloudflared) so a no-key machine can still get in
  (`ssh_trusted_root_password: true`); VPS console is root's break-glass. `ai` is allowed from
  anywhere by key **or** password; only `ai` is permitted from the public net; passwords are off
  to the public internet (on for trusted). The `ai` password is in 1Password
  (`vibe_coding/hetz-ai-ssh`). NOTE: applying this OVERWROTE the pre-existing `ai` password
  (there was no prior 1Password item) — the new generated one is the live value.


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
- **`firewall`** — the original full-capture design was proven on scratch, but then **reworked**
  (the full `iptables-save` approach drifts daily as Docker rewrites nat chains). The role now
  manages only the declarative SSH lockdown and is **applied to prod + idempotent** — see the
  "firewall reworked" item below. The old mode A/B and auto-revert machinery were removed.
- **`docker`** — deployed `daemon.json` verbatim, held the package, did **not** restart the
  daemon; **idempotent** (2nd run = 0 changes). **APPLIED TO PROD 2026-06-24**: only change was
  the package hold (`daemon.json` already matched); Docker not restarted (27 containers stayed
  up); re-run = 0 changes.
- **`cloudflared_coolify`** — DONE 2026-06-24. UNIT applied to prod (verbatim copy of the live
  unit → no-op; tunnel NOT restarted; dir tightened to 0750; idempotent). TOKEN reconciled: the
  live token (180 ch) didn't match the older `cloudflare-tunnel-tokens` fields (240 ch), so the
  live working token was stored in a new item `op://vibe_coding/cf-tunnel-hetz/password`
  (hash-verified == live). Verified that managing the token is a no-op (`--check` with the token
  injected = 0 changes). `cloudflared_manage_token` stays FALSE by default (routine runs manage
  only the unit; rebuild/CI sets it true + injects the token). The earlier scaffolded unit had the
  wrong binary path (`/usr/bin` vs real `/usr/local/bin/cloudflared`) — replaced by the verbatim file.
- **CI pipeline — WORKING end-to-end as of 2026-06-24.** GitHub secrets set
  (`OP_SERVICE_ACCOUNT_TOKEN` from `vibe_coding-service-account`; `TS_OAUTH_CLIENT_ID`/`SECRET`
  from `tailscale oauth for github for ansible`). A dedicated CI key (`op://vibe_coding/ci-deploy-ssh`)
  logs in as `ai` over Tailscale (tag:ci) and sudo-roots. `drift.yml` ran green (joins Tailscale →
  loads secrets → SSH → `--check` → 0 changes). **Drift detection is LIVE** (daily 03:00 UTC).
  `check.yml` posts the dry-run diff on PRs. Fixed along the way: INI inline-comment in inventory
  (broke the SSH username), SSH key trailing newline, and the drift grep (matched loop items).
  **Phase 4 COMPLETE 2026-06-24:** `ENABLE_AUTO_APPLY=true` (GitHub repo variable). Self-test
  passed — pushed a motd line to `main`, `apply.yml` auto-applied it to hetz (serialized), verified
  live. **Push to `main` now auto-applies to prod** (doc-only pushes = no-op applies). Drift
  detection runs daily.

The scratch box (`165.227.208.178`) is to be **destroyed** by the owner once results are reviewed.

## Status: COMPLETE — Phases 0–4 + recovery gaps R1–R7 done and validated.

The full rebuild is **proven on a bare box** (2026-06-24, R7): toolchain (apt repos, 202 packages,
Go/supabase/codex/npm CLIs, Docker) AND Coolify install (4.1.2 pinned, all containers healthy) all
rebuilt from scratch; the inventory diff was clean. The **only** unproven step is the backrest
**data-restore** drill (restoring coolify-db + /data/coolify so Coolify knows the ~20 apps) — that
lives in the `backrest-wiz` repo, not here, and needs the real backups.

### Optional follow-ups remain:

- **Wire drift alerts to a channel** — `drift.yml` fails on drift but the alert is just a GitHub
  Actions failure; route it to where the owner will see it (e.g. the backup-alert channel).
- **cloudflared token management** — `cloudflared_manage_token` is `false` (manual); flip true only
  if you want CI/rebuild to (re)write the env from `op://vibe_coding/cf-tunnel-hetz`.
- **Clean the stale `--dport 18790` firewall rule** (nothing listens there) — confirm then remove.
- **Extra users `nova`/`nasbridge`** — unknown purpose; encode in `users` if wanted.
- **Fold in the DigitalOcean `backrest-wiz` droplet** as a second inventory group (plan §2.3).
- **Phase 3 app-layer secrets** — restic/Spaces/oauth2-proxy/CF-DNS live in app/Coolify configs;
  cleaning those belongs in their own repos, not here (owner said restic/Spaces are in a personal vault).
- **Replace the owner's `916-alien` key copy in WSL** — no longer needed now that CI has its own key.

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
2. ~~**`firewall` role needs a REWORK**~~ ✅ **DONE + applied to prod 2026-06-24.** Reworked from
   full-`iptables-save` capture (which drifted daily — Docker rewrites `nat` chains) to declarative
   `ansible.builtin.iptables` rules managing ONLY the host-owned `filter INPUT` SSH lockdown
   (port-22 trusted-source allow + drop; 1904 left open). Docker/Tailscale/fail2ban chains left
   alone. Applying was a **no-op on IPv4** (rules already matched) and **closed an IPv6 gap** (live
   v6 had no port-22 restriction — now locked to Tailscale-v6/localhost). Idempotent (2nd run = 0
   changes), no drift. `files/hetz.rules.v*` kept only as a disaster-recovery snapshot.
3. **Apply `cloudflared_coolify` to prod** — needs the real Tunnel 1 token from 1Password
   (`op://vibe_coding/cf-tunnel-hetz`); restarts the live tunnel, so validate reconnect.
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
