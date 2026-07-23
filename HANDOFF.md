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
- **Retired-platform host cleanup — applied 2026-07-23 and idempotent.** PR
  [#8](https://github.com/u2giants/ansible/pull/8), merge commit
  `4c56488f398afee7f4ff342b81836afee3cd07af`, added the narrow phase-one
  `retired_platform_cleanup` role. Its first serialized auto-apply
  ([run 30043128914](https://github.com/u2giants/ansible/actions/runs/30043128914))
  removed the obsolete `/home/ai/.directus-deploy.env` file; a direct read-only
  host check returned `FILE_ABSENT`. The final credential verification
  ([run 30043687253](https://github.com/u2giants/ansible/actions/runs/30043687253))
  ran only `--tags retired_platform_cleanup` and reported `changed=0`,
  `failed=0`. This file belonged to the retired legacy data platform and has no
  relationship to DB Data Admin, the current application at
  `https://data.designflow.app`.
- **Agent governance rollout.** The "route host changes through Ansible" rule is in global
  Claude (`~/.claude/CLAUDE.md`) and Codex (`~/.codex/AGENTS.md`) memories, and in `AGENTS.md`
  of all 12 u2giants repos (popdam3, theoracle, compshop, popcrm-web, poppim-web,
  synology-monitor, albert-standards, backrest-wiz, seafile, hiclaw, devops-mcp, authentik).
- **Local validation:** `ansible-lint` clean (2 accepted warnings) + `--syntax-check` green in WSL.
- **Gap re-audit — 2026-06-25.** Software inventory (0 drift) and phase1 config `--check` (0
  changes) both clean. Closed the remaining host-layer gaps the audit surfaced: new
  **`dns_watchdog`** role (the live DNS self-heal timer/script in `/usr/local/sbin`, previously
  un-roled — captured verbatim, no-op on prod); removed the deprecated **`socks5-home-tunnel`**
  service (owner-confirmed unused; was enabled + crash-looping, exposed `0.0.0.0:1080`); removed
  the un-owned login users **`nova`** (orphan) and **`nasbridge`** (accidental global-install
  identity — its `supabase`/`gemini-cli` tools re-homed to root by `dev_tools` first). Also fixed
  the audit blind spot that hid the watchdog: `bin/discover-software.sh` now scans
  `/usr/local/sbin` and the baseline was regenerated. **Applied to prod 2026-06-25** via CI
  auto-apply (`changed=4`); idempotency gate passed (re-run `--check` = `changed=0`); live box
  verified (users gone, socks5 unit gone, tools `root`-owned, `dns-watchdog.timer` active).

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
- **CI pipeline — WORKING end-to-end as of 2026-06-24; 1Password credential
  replaced and reverified 2026-07-23.** GitHub secrets set
  (`OP_SERVICE_ACCOUNT_TOKEN` is the token for the 1Password service account
  `GitHub Ansible CI Final`; `TS_OAUTH_CLIENT_ID`/`SECRET` come from
  `tailscale oauth for github for ansible`). `GitHub Ansible CI Final` is
  deliberately restricted to **read-only access to the single `vibe_coding`
  vault**, cannot create vaults, and has no 1Password Environment access. Only
  the `u2giants/ansible` repository secret was updated. A dedicated CI key
  (`op://vibe_coding/ci-deploy-ssh`)
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

### What's next — remaining work (none urgent; ranked by real value)

> ⚠️ **FIRST, RE-CHECK FOR GAPS between what Ansible records and what's actually on the server.**
> The recovery mission only holds if *every* piece of software/config on `hetz` is captured in code.
> We closed the known gaps (R1–R7), but new things get installed/changed over time. On any handoff,
> **re-audit**:
> - `ssh vps 'sudo bash -s' < bin/discover-software.sh` and diff vs `docs/baseline-software.txt`
>   (the daily `drift.yml` software step already does this — check it's green and investigate any
>   additions). If something new is legit, add it to a role + regenerate the baseline/`apt-manual.txt`.
> - `ssh vps 'sudo bash -s' < bin/discover.sh` and compare enabled services, cron, `/etc` configs,
>   systemd units, listening ports, and `/usr/local/bin` against what the roles declare. Anything the
>   roles don't reproduce is a recovery gap — capture it (same "vendor-verbatim, no-op-on-prod" pattern).
> - Confirm the config `drift.yml` check is green (phase1 `--check` = 0 changes).
> Treat "is the repo still a complete description of the box?" as a standing question, not a one-time task.

**Higher value, small effort**
- **Wire drift alerts to a channel the owner actually watches.** `drift.yml` (config + software
  drift) *fails the workflow* on drift, which only emails on Actions failure. Route it to Slack/
  Telegram/etc. so detection becomes *noticed*. This is the highest-value small item for the
  "catch changes I don't know about" goal.
- **Exact-path polish (R7 finding).** A rebuild puts `codex`/`gemini`/`supabase` in `/usr/bin` (via
  npm/.deb) but prod has them in `/usr/local/bin`. They work either way; add symlinks in `dev_tools`
  for byte-exact reproduction.

**The one bigger thing — the second server + the backup system**
- **`backrest-wiz` / backrest — cleanup, upgrade, 3-2-1, restore-test, and Ansible integration.**
  This is the only substantial remaining work and it's the mission's "Pillar 4" (data restore). A
  full **comprehensive plan lives in that repo's `HANDOFF.md`** (`u2giants/backrest-wiz`) — read it.
  In short: the DigitalOcean backup-monitor **droplet** is a whole second server NOT yet under this
  pipeline (fold it in as the `[do_backup_wiz]` inventory group — already stubbed in `hosts.ini`);
  the **backrest producer** on `hetz` (`/opt/backrest`) is set up imperatively and **not in a role**
  (only its watchdog is — `backrest_watchdog`), so a `hetz` rebuild would NOT restore the backup
  producer; and the backups themselves have **never been restore-tested** (the biggest risk). When
  you do the Ansible-integration phase there, you're extending *this* pipeline to cover both servers.

**Quick cleanups (safe, do anytime)**
- **Clean the stale `--dport 18790` firewall rule** (nothing listens there) — confirm then remove
  from the `firewall` role's allowed sources.
- **Replace the owner's `916-alien` private-key copy left in WSL `~/.ssh/`** — no longer needed now
  that CI has its own key (`op://vibe_coding/ci-deploy-ssh`).
- **CI Node-20 deprecation warnings** — `1password/load-secrets-action`, `actions/checkout`,
  `actions/setup-python` warn about Node 20→24; cosmetic, bump action versions when convenient.

**Needs the owner's knowledge (can't be done blind)**
- **Phase 3 app-layer secrets** — restic/Spaces/oauth2-proxy/CF-DNS live in app/Coolify configs;
  cleaning those belongs in their own repos (owner confirmed restic/Spaces are in a personal vault).

**Optional / by-design**
- **`cloudflared_manage_token`** stays `false` (manual). Flip true only for a rebuild/CI run that
  must (re)write the tunnel env from `op://vibe_coding/cf-tunnel-hetz`.
- **`coolify` install** is proven on a fresh box (R7), but the **backrest data-restore** into a
  rebuilt Coolify is the one un-rehearsed recovery step — drill it on a sized box before a real
  disaster (it's `backrest-wiz`'s domain).

## Decisions made (and why)

- **Reproduce reality, don't impose an ideal** — `daemon.json` and the backrest units are
  vendored verbatim from the box for byte-idempotency.
- **`docker` never auto-restarts; firewall has auto-revert; risky roles gated by `enable_phase2`**
  — safety against the documented outages (AGENTS §13).
- **Main-only git workflow**; commits use the owner's GitHub noreply email (privacy enabled).
- **GitHub Actions is the canonical apply path** — merges to `main` serialize
  through `apply.yml`; do not replace this with routine manual WSL or SSH
  changes. `ENABLE_AUTO_APPLY=true` is verified.

## Dead ends / corrections

- The `docker` role's first version rebuilt `daemon.json` from a dict (would have dropped real
  keys) — replaced with a verbatim file + a narrow `127.0.0.53` assertion.
- The `backrest_watchdog` first version invented a simpler script — replaced with the real
  3-condition script/units from the box.
- `roles/base` wrote a journald drop-in without creating the parent dir — fixed.
- PR #8's first check run failed before Ansible with `403 Forbidden (Service
  Account Deleted)`: the old `OP_SERVICE_ACCOUNT_TOKEN` referred to a deleted
  1Password service account. The 1Password MCP could not bootstrap the repair
  because it used the same deleted credential and cannot administer service
  accounts. Recovery therefore used the authenticated POP Creations 1Password
  web administration console.
- The first replacement token was rendered by browser inspection while the
  one-time token page was open. It was immediately treated as compromised:
  GitHub was updated again with a clean no-output transfer to
  `GitHub Ansible CI Final`, and the exposed `GitHub Ansible CI` token was
  revoked. Final run 30043687253 proves the non-revoked credential works.
- A browser “Copy token” action writes to the browser's protected clipboard,
  not the Windows clipboard. The attempted `Get-Clipboard | gh secret set`
  correctly rejected the non-token clipboard content and changed nothing. The
  successful path kept the clean token in browser process memory and passed it
  to `gh secret set OP_SERVICE_ACCOUNT_TOKEN --repo u2giants/ansible` on
  standard input, without writing it to disk, command arguments, or output.

## Exact next action

Phases 0–4 and recovery gaps R1–R7 are **done and applied to prod** (the whole host + Coolify
install rebuild is validated). There is **no required next step** — pick from "What's next" above.
On any handoff, **start by re-checking for gaps** (the boxed directive at the top of that section):
re-run `bin/discover-software.sh` + `bin/discover.sh` against `hetz` and confirm the repo still
fully describes the box. The single biggest *outstanding* piece of real work is the
**`backrest-wiz` cleanup + Ansible integration** (its repo's `HANDOFF.md` has the full plan).

## Known risks / unknowns

- **`--check` is not fully reliable for command/shell tasks** — prove risky roles on scratch, don't
  trust prod `--check` (plan §4a).
- **A copy of the owner's `916-alien` private key lives in WSL `~/.ssh/`** to enable manual applies;
  remove it now that CI has its own key.
- **The recovery is only as good as a re-checked inventory** — software/config installed outside the
  pipeline silently breaks the "rebuild everything" guarantee. The daily `drift.yml` (config +
  software) is the guard; keep it green and act on any failure.
- **`backrest` data-restore has never been rehearsed** — a host rebuild can stand up Coolify but the
  actual app-state restore from backups is unproven (see `backrest-wiz`).

---

# Session addendum — retired data-platform file and Ansible CI credential (2026-07-23)

## 1. What this application is

`u2giants/ansible` is the source of truth for the host/operating-system layer of
the Hetzner server named `hetz` (SSH aliases `vps` and `coolify`). It manages
packages, users, firewall and SSH policy, system services, Cloudflare Tunnel 1,
watchdogs, and other host files. GitHub Actions performs serialized production
applies. Coolify—not this repo—owns application containers and application
domain bindings. `https://data.designflow.app` is DB Data Admin; the retired
legacy data platform must never be inferred from that hostname.

## 2. What we set out to do this session, and why

An earlier retirement sweep found the obsolete host file
`/home/ai/.directus-deploy.env`. The goal was to remove it through the managed
Ansible workflow, not by editing the server, and prove the result was
idempotent. PR #8 initially could not run because the repository's 1Password
service-account token referred to a deleted account. The credential objective
therefore became: replace only `u2giants/ansible`'s
`OP_SERVICE_ACCOUNT_TOKEN` with a least-privilege account restricted to
read-only `vibe_coding`, then complete the PR/apply/verification sequence.

## 3. Current state — what is true right now

- PR [#8](https://github.com/u2giants/ansible/pull/8) is merged to `main` as
  `4c56488f398afee7f4ff342b81836afee3cd07af`.
- The implementation is
  `roles/retired_platform_cleanup/{defaults,tasks}/main.yml`, wired into
  `playbooks/site.yml` with tags `phase1` and `retired_platform_cleanup`.
- The first real serialized apply, [run
  30043128914](https://github.com/u2giants/ansible/actions/runs/30043128914),
  reported exactly one change: removing `/home/ai/.directus-deploy.env`.
- A direct read-only host test returned `FILE_ABSENT`.
- The final verification, [run
  30043687253](https://github.com/u2giants/ansible/actions/runs/30043687253),
  authenticated with the final credential and reported `changed=0`,
  `failed=0`.
- GitHub secret `OP_SERVICE_ACCOUNT_TOKEN` points to the active 1Password
  service account `GitHub Ansible CI Final`. It has read-only access to only
  `vibe_coding`, cannot create vaults, and has no Environment access.
- No production application, Coolify binding, DNS record, or shared database
  was changed by this Ansible PR.

## 4. Everything we tried that did NOT work

1. PR #8's original `check-diff` failed before Ansible because 1Password
   returned `403 Forbidden (Service Account Deleted)`. The old GitHub secret
   was syntactically present but operationally dead.
2. The 1Password MCP could not repair this because it was backed by the same
   deleted token and exposes no service-account administration function.
3. The first browser-created replacement token appeared in browser inspection
   output. It was treated as compromised, replaced, and revoked rather than
   accepted as “probably safe.”
4. The browser's Copy button used a protected browser clipboard. Windows
   `Get-Clipboard` did not contain the token; the guarded command rejected it
   and made no GitHub change. The final transfer kept the token in browser
   process memory and supplied it to `gh secret set` over standard input.
5. Direct URL navigation to the 1Password service-account list sometimes
   redirected to the Environments tab. Selecting the visible “Service
   accounts” tab was the reliable route.

## 5. Root causes and key findings

- Credential presence is not credential capability. Always exercise the real
  1Password action; `gh secret list` only proves a secret name exists.
- The Ansible workflow needs two existing `op://vibe_coding/...` references
  (`ci-deploy-ssh/private_key` and `cf-tunnel-hetz/password`), so read access to
  the `vibe_coding` vault is the narrow compatible 1Password boundary.
- The retired file was inert host residue: the PR check showed no other drift,
  the apply removed only that file, and the second/final runs were no-ops.
- 1Password service-account permissions are immutable after creation. A wrong
  scope must be revoked and recreated, not “fixed later.”

## 6. Exact next steps

No action is required for this workstream.

If the credential is ever replaced again:

1. Create a new service account in the POP Creations 1Password account with
   read-only access to `vibe_coding`, vault creation disabled, and zero
   Environment access. You will know it is correct when its detail page shows
   `Vaults (1): vibe_coding — Read` and `Environments (0)`.
2. Pass the one-time token to
   `gh secret set OP_SERVICE_ACCOUNT_TOKEN --repo u2giants/ansible` through
   standard input without printing or writing it. You will know GitHub accepted
   it when `gh secret list --repo u2giants/ansible` shows a new `updatedAt`.
3. Run `gh workflow run apply.yml --repo u2giants/ansible -f
   tags=retired_platform_cleanup`. You will know the account works and the host
   is converged when “Load secrets from 1Password” succeeds and the recap says
   `changed=0 failed=0`.
4. Only after step 3 succeeds, revoke the superseded service account. You will
   know revocation completed when it disappears from Active service accounts.

## 7. Constraints and gotchas in force

- Host changes must go repo → PR check/diff → merge → serialized GitHub Actions
  apply. Never hand-edit `/home`, `/etc`, systemd, firewall, or Docker host
  configuration.
- App containers and domains belong to Coolify/application repos, not Ansible.
- Restrict Ansible's 1Password account to `vibe_coding`; never grant Personal or
  broad vault access.
- Never display, log, paste into chat, save to disk, or place a token in process
  arguments. A one-time token exposed to inspection must be revoked.
- The GitHub Actions Node 20 deprecation notice is currently a warning, not a
  failed deployment; track it as existing pipeline maintenance.

## 8. Access and environment

- Repository: `https://github.com/u2giants/ansible`, canonical branch `main`.
- Production host: `hetz`; read-only verification may use SSH alias `coolify`.
- GitHub CLI `gh` is authenticated for `u2giants`.
- Production workflow secrets are repository-scoped GitHub Actions secrets.
- 1Password account: POP Creations; permitted vault: `vibe_coding` only.
- Never record service-account token values in this file or any repository.

## 9. Open questions and risks

- No open question remains for the retired file or Ansible credential.
- Existing broader repository risks remain documented above, especially the
  unrehearsed Backrest data-restore and periodic host-inventory re-audit.
- The workflow emitted GitHub's Node 20 action-runtime deprecation warning on
  2026-07-23. It did not affect this apply, but action versions should be
  upgraded before GitHub removes compatibility.

## Handoff self-audit

1. **Could a street-newcomer continue without asking a question? Yes.** Sections
   1–3 define the repo, host/app boundary, goal, files, credential scope, commit,
   and verified runtime state; section 6 gives the complete future rotation
   procedure.
2. **Could they continue as effectively as this session? Yes.** Sections 4–5
   preserve every material dead end and the non-obvious clipboard,
   least-privilege, immutability, and capability-testing findings.
3. **Are failed attempts and reasons included? Yes.** Section 4 records the
   deleted account, MCP bootstrapping limit, exposed intermediate token,
   protected clipboard mismatch, and 1Password navigation redirect.
4. **Is every next step concrete and verifiable? Yes.** Section 6 numbers every
   future credential-rotation action and gives an observable success gate.
5. **Are terms, paths, URLs, and identifiers explained? Yes.** Sections 1, 3,
   and 8 define `hetz`, Coolify ownership, the repository, branch, role paths,
   workflow runs, secret name, vault, and hostname meaning.

Final synthesis:

1. **Is `HANDOFF.md` comprehensive enough for a brand-new developer? Yes.**
   Sections 1–9 cover all required dimensions and the exact completed state.
2. **Can they continue with all relevant knowledge from this session? Yes.**
   Sections 3–6 contain the evidence, failures, findings, and reproducible
   recovery/verification sequence.
3. **Is every relevant detail present for flawless execution? Yes.** Sections
   2–9 cover background, goal, outcome, failures, decisions, constraints,
   risks, access, and exact verification evidence without including any secret
   value.
