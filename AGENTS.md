# AGENTS.md — canonical operating guide for `u2giants/ansible`

> Read this file first. It is the single source of truth for working in this repo. Load other
> docs only when the **Documentation map** below says you need them — do **not** ingest every
> `.md` file.

## 1. Project summary

This repo manages the **host/OS layer** of one Hetzner VPS (`hetz`) as code, using **Ansible**
plus a **GitHub Actions apply pipeline**. It turns a hand-built "pet" server into something
rebuildable from code: packages, users, firewall, DNS hardening, the Docker *engine* config,
system cron, host systemd units (Cloudflare Tunnel 1, the backup watchdog), and glue scripts.

- **Who uses it:** a solo "vibe-coder" owner who drives changes through AI sessions and approves
  diffs, plus any AI session (Claude Code, Codex) that might touch the server.
- **Key moving parts:** `roles/` (one role per host concern), `playbooks/site.yml` (entrypoint,
  phase-gated), `inventory/` (hosts + non-secret vars), `.github/workflows/` (check / apply /
  drift), secrets from **1Password** at apply time.
- **Outcome that matters:** if `hetz` is destroyed, a new Ubuntu box + this repo + the 1Password
  vault + data backups = full recovery, and ~7 concurrent AI sessions can't cause conflicting
  drift because every host change goes through one serialized apply path.

**Scope boundary (the most important rule): Ansible owns the host. Coolify owns the apps.**
Never manage application containers or Coolify-owned resources here — it causes reconcile loops.

## Multi-model AI note

There is no universal ignore-file standard across AI coding tools.

`.claudeignore` works for Claude Code.

When using any other AI tool, paste this file as your first message and follow the instructions in the "What to ignore" section.

## 2. Documentation map: what to read for each task

Always start with:

- `AGENTS.md`

Then load additional docs only when relevant:

| Task / question | Read these docs | Usually do not need |
|---|---|---|
| Quick repo orientation | `README.md`, `AGENTS.md` | `docs/ANSIBLE-IMPLEMENTATION-PLAN.md` (long); role READMEs |
| Modify a host role's behavior | `AGENTS.md`, the relevant `roles/<role>/README.md`, `docs/architecture.md` | `docs/deployment.md` unless the apply flow changes |
| Add/change config, vars, secrets, runtime settings | `AGENTS.md`, `docs/configuration.md`, `docs/deployment.md` if CI/runtime is affected | unrelated role READMEs |
| Change local setup / how to run, lint, test, apply | `AGENTS.md`, `docs/development.md`, `ansible.cfg`, `requirements.yml` | `docs/deployment.md` unless CI changes |
| Change deployment, CI/CD, the apply pipeline, rollback | `AGENTS.md`, `docs/deployment.md`, `.github/workflows/*`, `docs/configuration.md` | `docs/development.md` unless local flow changes |
| Change firewall / docker / cloudflared (risky roles) | `AGENTS.md`, `docs/architecture.md`, that role's README, `docs/ANSIBLE-IMPLEMENTATION-PLAN.md` §4a | unrelated roles |
| Investigate an incident or breakage | `AGENTS.md` (Critical incidents §14), `HANDOFF.md` if present, `docs/DISCOVERY-2026-06-23.md` | unrelated role READMEs |
| Continue unfinished work | `AGENTS.md`, **`HANDOFF.md`**, docs named inside it | docs unrelated to the handoff scope |
| Understand the full original brief / rationale | `docs/ANSIBLE-IMPLEMENTATION-PLAN.md` | everything else until you need it |
| Claude Code session | `CLAUDE.md`, then `AGENTS.md` | other docs unless the task needs them |
| Documentation-only cleanup | `AGENTS.md`, `README.md`, affected `docs/*`, role READMEs only where relevant | role source except to verify accuracy |

If `HANDOFF.md` exists, it is **required reading** for any continuation work.

## 3. Repository structure

| Path | What it is | Category |
|---|---|---|
| `playbooks/site.yml` | The only entrypoint; applies roles, phase-tagged (`phase1`/`phase2`) | project-owned |
| `roles/<name>/` | One role per host concern (tasks/handlers/defaults/files/templates + README) | project-owned |
| `inventory/hosts.ini` | Hosts: `[hetzner]`, `[scratch]` (placeholder), `[do_backup_wiz]` (placeholder) | project-owned |
| `inventory/group_vars/all.yml` | Non-secret vars; reconciled with live state | project-owned |
| `.github/workflows/` | `check.yml`, `apply.yml`, `drift.yml` | project-owned |
| `files/cloud-init/` | First-boot bootstrap template (`user-data.yaml.j2`) | project-owned |
| `bin/discover.sh` | Read-only live-state capture script (run on the box) | project-owned (script) |
| `docs/` | Plan, discovery report, status, and topic docs | docs |
| `ansible.cfg`, `requirements.yml`, `.ansible-lint`, `.gitattributes`, `.gitignore` | Tooling/config | project-owned |
| `discovery/` | Local output of `bin/discover.sh` (host internals) | **gitignored, not in repo** |

There is **no** vendored/third-party/generated code and **no** build artifacts in this repo —
everything is project-owned Ansible/YAML/Markdown. `roles/backrest_watchdog/files/*` are vendored
**verbatim from the live box** (canonical source: the `backrest-wiz` repo) — see quirks §11.

## 4. Prime Directive: custom-code boundary

Project-owned code lives here (edit freely, with care):

- `roles/` — all host configuration logic
- `playbooks/`
- `inventory/`
- `files/`, `bin/`
- `.github/workflows/`
- `docs/`

**The harder boundary is operational, not just paths:** this repo manages the **host/glue layer
only**. Everything Coolify manages (the ~20 app containers, the Traefik/`coolify-proxy` dynamic
config, Cloudflare Tunnels 2 & 3) is **off-limits** — do not add roles that touch it. When in
doubt, see `docs/architecture.md` and `docs/ANSIBLE-IMPLEMENTATION-PLAN.md` §2–§3.

## 5. Core modification inventory

This repo does not modify any files outside its own project-owned areas — it is a standalone
Ansible project with no vendored/framework code to patch. **There are no out-of-boundary
modifications.** (Ansible *applies* changes to the live host's `/etc`, systemd, etc., but those
are managed declaratively by roles, not source files in this repo.)

## 6. Task-to-file navigation: what to edit for common changes

| Task | Files to touch | Files NOT to touch |
|---|---|---|
| Add/remove an apt package or base setting | `inventory/group_vars/all.yml` (`base_packages`), `roles/base/` | role files for unrelated concerns |
| Change DNS fallback servers | `inventory/group_vars/all.yml` (`dns_fallback_servers`), `roles/dns_hardening/` | `roles/docker/` (separate DNS concern) |
| Change Docker daemon config | `roles/docker/files/daemon.json` (verbatim), `roles/docker/` | anything that restarts Docker automatically |
| Change firewall (SSH) rules | `roles/firewall/` + `firewall_ssh_trusted_v4/v6`, `firewall_ssh_public_ports` in defaults | Docker/Tailscale/fail2ban chains; never a full-table capture |
| Add/change a cron entry | `inventory/group_vars/all.yml` (`cron_glue_entries`), `roles/cron_glue/` | the keeper scripts under `/worksp/hiclaw/` (owned by HiClaw repo) |
| Manage Cloudflare Tunnel 1 | `roles/cloudflared_coolify/` | Tunnels 2 & 3 (Coolify-managed) |
| Add an SSH public key for `ai` | `inventory/group_vars/all.yml` (`users_authorized_keys`) | private keys (never commit) |
| Change the apply/CI flow | `.github/workflows/apply.yml` / `check.yml` / `drift.yml` | the `concurrency: apply-hetzner` guard (serialization) |
| Add a new host concern | new `roles/<name>/`, wire into `playbooks/site.yml` with a phase tag | existing roles unless related |

## 7. Data model and external identifiers

This repo has no database. The "identifiers" are host/infra facts (non-secret) that must not be
casually changed:

| Entity/System | Identifier | Where defined | Notes |
|---|---|---|---|
| Managed host | `hetz` | `inventory/hosts.ini`, live | Ubuntu 24.04.4, kernel 6.8, tz `America/New_York` |
| Host public IP | `178.156.180.212` | live / docs | Hetzner VPS |
| Host Tailscale IP | `100.66.37.58` | `inventory/hosts.ini` | preferred connection path; SSH lifeline |
| Domain | `designflow.app` | docs / Cloudflare | DNS on Cloudflare |
| Docker engine | pinned `5:29.6.0-1~ubuntu.24.04~noble` | `group_vars` / `roles/docker/defaults` | held; never auto-upgraded |
| Cloudflare Tunnel 1 | `cloudflared-coolify.service` | `roles/cloudflared_coolify/` | host systemd unit; token in 1Password |
| 1Password vault | `vibe_coding` | `docs/*`, workflows | all secrets live here; injected at apply time |
| Phase gates | `enable_phase1` (true), `enable_phase2` (false), `ENABLE_AUTO_APPLY` (GH repo var, unset) | `group_vars`, `apply.yml` | control what runs/applies |

## 8. Container and service inventory

**This repo does not own any containers.** The ~20 application containers and the
`coolify-proxy` (Traefik) are owned by **Coolify** and are out of scope — do not manage them
here. See `docs/ANSIBLE-IMPLEMENTATION-PLAN.md` §2.1.

Host-level systemd services/units that **this repo manages or relies on**:

| Service/unit | Purpose | Managed by | Notes |
|---|---|---|---|
| `cloudflared-coolify.service` | Cloudflare Tunnel 1 (`coolify.designflow.app`) | `roles/cloudflared_coolify` (Phase 2, gated) | Tunnels 2/3 are Coolify's — never touch |
| `backrest-dump-watchdog.timer` + `.service` | Self-heal backrest backup agent after docker.sock staleness | `roles/backrest_watchdog` (Phase 1, applied) | units vendored verbatim from `backrest-wiz` |
| `systemd-resolved` | Host DNS; fallback-dns drop-in | `roles/dns_hardening` (Phase 1, applied) | restarted by the role on change |
| `systemd-journald` | Logs; size cap drop-in | `roles/base` (Phase 1, applied) | restarted by the role on change |
| `docker.service` | Engine; `daemon.json` only | `roles/docker` (Phase 2, gated) | **never auto-restarted** by Ansible |
| `fail2ban`, `netfilter-persistent` | Firewall/ban persistence | `roles/firewall` (Phase 2, gated) | enabled/ensured running |

## 9. What to ignore

These exist (or are produced locally) but should not consume AI context:

- `discovery/` — local output of `bin/discover.sh` (host ports/iptables/config dumps); gitignored.
- `.ansible/`, `fact_cache/`, `*.retry`, `*.log` — Ansible runtime cruft.
- `.git/`
- `docs/ANSIBLE-IMPLEMENTATION-PLAN.md` is **long (480+ lines)** — read it only when you need the
  full original rationale/landmines, not for routine edits.

This matches `.claudeignore` / `.cursorignore`.

## 10. Intentional quirks and non-obvious decisions

### daemon.json contains a `dns` key

Looks like: a violation of "no dns key in daemon.json" from the original plan §3.3.

Actually: the live, working file has `"dns": ["1.1.1.1","8.8.8.8"]` (public resolvers) plus
`log-opts` and `default-address-pools`. The `docker` role deploys it verbatim.

Why: the real landmine is narrower than first written — DNS must never point at `127.0.0.53`
(the host resolver stub, unreachable from containers). Public resolvers are correct.

Do not change because: stripping the dns/log-opts/address-pools keys would break container DNS and
networking. The role asserts `127.0.0.53` never appears; keep that, keep the rest.

### Firewall default policy is ACCEPT, not DROP

Looks like: the host firewall is wide open.

Actually: INPUT policy is ACCEPT but SSH (port 22) is allowed **only** from Tailscale
(`100.64.0.0/10`), localhost, and `10.0.1.0/24`, then dropped for everyone else. Public SSH is closed.

Why: Tailscale is the single SSH path and the firewall lifeline; Docker also manages its own
chains in this table.

Do not change because: a naive default-DROP rewrite would wipe Docker's chains (killing all
container networking) and/or lock out SSH. The `firewall` role manages **only the host-owned
`filter INPUT` SSH rules** declaratively (`ansible.builtin.iptables`) and leaves Docker's chains
alone — never reintroduce a full-`iptables-save` capture (it drifts daily as Docker rewrites nat).

### The `docker` role never restarts Docker

Looks like: an incomplete role — it changes `daemon.json` but doesn't apply it.

Actually: a `daemon.json` change only prints "restart required in a maintenance window"; the
handler is manual-gated.

Why: a Docker restart hits Coolify + ~20 containers and causes docker.sock staleness (June 2026
outage). Restarts must be deliberate and human-timed.

Do not change because: auto-restarting on apply would risk a production outage from a routine CI run.

### Risky roles do nothing unless `enable_phase2=true`

Looks like: `firewall`, `docker`, `cron_glue`, `cloudflared_coolify` are wired up but "don't run."

Actually: they are gated behind `enable_phase2` (default false) and a pre-task assertion, so they
cannot reach prod until proven on a scratch host.

Why: these can take the box down; the plan (§9) requires a hard gate.

Do not change because: removing the gate lets an unproven risky role apply to prod.

### `roles/backrest_watchdog/files/*` look duplicated from another repo

Looks like: copies of files that belong in `backrest-wiz`.

Actually: they are vendored **verbatim** so a rebuild reproduces the exact watchdog; their
canonical home is the `backrest-wiz` repo.

Why: byte-for-byte reproduction keeps re-applies idempotent and avoids regressing the real
3-condition self-heal (an earlier "improved" scaffold version was caught regressing it).

Do not change because: editing them here diverges from prod. Update only to track `backrest-wiz`.

### `.gitattributes` forces LF; local WSL runs need `ANSIBLE_CONFIG`

Looks like: odd line-ending config and an env var requirement.

Actually: files are authored on Windows but run on Ubuntu (CRLF breaks shell scripts), and the
`/mnt/c` mount is world-writable so Ansible ignores `ansible.cfg` unless `ANSIBLE_CONFIG` points
at it explicitly. See `docs/development.md`.

Why: cross-platform authoring.

Do not change because: removing LF enforcement breaks scripts on the host; without the env var,
local runs silently lose `roles_path`/inventory.

## 11. Credentials and environment

No secret values are stored in this repo. Secrets live in **1Password** (vault `vibe_coding`) and
are injected at apply time. See `docs/configuration.md` for the full table.

| Variable / reference | Purpose | Stored where | Required (local apply) | Required (CI) |
|---|---|---|---|---|
| `op://vibe_coding/ci-deploy-ssh/private_key` | SSH to the host | 1Password | no (uses owner's key today) | yes (Phase 4) |
| `op://vibe_coding/cf-tunnel-hetz` | Cloudflare Tunnel 1 token | 1Password | only for `cloudflared_coolify` | yes |
| `OP_SERVICE_ACCOUNT_TOKEN` | 1Password access in CI | **GitHub secret (planned)** | no | yes (Phase 4) |
| `TS_OAUTH_CLIENT_ID` / `TS_OAUTH_SECRET` | Tailscale `tag:ci` ephemeral node | **GitHub secret (planned)** | no | yes (Phase 4) |
| `ENABLE_AUTO_APPLY` | GH repo variable gating real applies | **GitHub repo variable (unset)** | n/a | yes to enable apply-on-merge |

**Unknown / not yet created:** the GitHub secrets and `ENABLE_AUTO_APPLY` do not exist yet
(Phase 4). Verify with `gh secret list -R u2giants/ansible` and `gh variable list -R u2giants/ansible`.

## 12. Deployment

See `docs/deployment.md` for full detail. Summary of the **real, current** state:

- **Pipeline:** GitHub Actions — `check.yml` (PR: `ansible-lint` + `--check --diff`, posts diff),
  `apply.yml` (push to `main`: serialized via `concurrency: apply-hetzner`; real apply **gated by
  the `ENABLE_AUTO_APPLY` repo variable, currently unset → check-only**), `drift.yml` (daily
  `--check`, alerts on drift, never applies).
- **Current reality:** CI auto-apply is **not yet enabled** (Phase 4 pending). Applies are done
  **manually** by the owner/an AI session running `ansible-playbook` from WSL against `hetz` over
  Tailscale. Phase 1 has been applied this way (2026-06-23); Phase 2 is not applied.
- **Connection / SSH:** `ssh vps` (alias in the owner's `~/.ssh/config`) → root@`100.66.37.58`
  over Tailscale, key `916-alien`. **SSH is currently routine** (manual apply phase). The target
  model makes SSH exceptional once CI runs applies; we are not there yet.
- **Rollback:** re-apply the playbook from a previous commit; the `firewall` role additionally
  arms a 60s auto-revert timer. There is no separate release/versioning system.
- **Image/package names:** none — this deploys configuration, not images.

## 13. Critical incidents

### 2026-05 — DNS cascade outage

What happened: host `systemd-resolved` broke; Docker's DNS relay (`127.0.0.11`) broke; every
tunnel/oauth2-proxy container crashed at once.

Impact: widespread container outage.

Root cause: containers can't reach the host stub `127.0.0.53`; no resilient fallback.

Recovery: added `resolved` `FallbackDNS`, kept `daemon.json` `live-restore: true`, per-container
DNS for oauth2-proxy.

Rule added: `dns_hardening` role encodes the fallback; `docker` role asserts dns never points at
`127.0.0.53`.

### 2026-06 — docker.sock staleness (silent backup failure)

What happened: a host Docker restart left the `backrest` container holding a stale
`/var/run/docker.sock`; DB backups silently failed for 4 days.

Impact: 4 days of missed database backups; `coolify-proxy` route discovery also broke.

Root cause: long-running containers bind-mounting docker.sock lose it on daemon restart.

Recovery: `backrest-dump-watchdog.timer` restarts the wedged container.

Rule added: `backrest_watchdog` role (Phase 1, applied); `docker` role never auto-restarts.

### 2026-06-23 — daemon.json near-miss (caught before any harm)

What happened: the initial `docker` role scaffold would have overwritten the real `daemon.json`
down to only `live-restore: true`, dropping `dns`, `log-opts`, `default-address-pools`.

Impact: none — caught during read-only discovery before any apply.

Root cause: the role followed the plan's "no dns key" literally instead of the live file.

Recovery: capture `daemon.json` verbatim; assert the narrow real invariant (no `127.0.0.53`).

Rule added: reconcile risky roles against live state before trusting them (discovery is mandatory).

### 2026-06-23 — journald.conf.d missing dir (real apply failure)

What happened: Phase 1 apply failed because `roles/base` wrote a journald drop-in into a
non-existent `/etc/systemd/journald.conf.d`; `--check` hadn't surfaced it.

Impact: one failed apply; partial Phase 1 (no host damage).

Root cause: the `copy` module doesn't create parent dirs; check mode masked it.

Recovery: added a `file: state=directory` task before the copy; re-applied cleanly.

Rule added: ensure parent dirs explicitly; don't fully trust `--check` for filesystem layout.

## 14. Pending work

See `HANDOFF.md` for the detailed continuation state. Summary:

| Status | Item | Owner / next action |
|---|---|---|
| done | Phase 0 scaffold + live discovery/reconciliation | committed (`docs/DISCOVERY-2026-06-23.md`) |
| done | Phase 1 applied to prod, idempotency gate passed | applied 2026-06-23 from WSL |
| done | Agent governance rolled out (global memories + 12 repos + on-box motd) | merged/committed |
| done | Phase 2 risky roles **proven on a scratch box** (2026-06-24) — firewall lockout/auto-revert mechanics, docker no-restart+idempotent, cloudflared deploy idempotent | see `HANDOFF.md` |
| done | Phase 2 `docker` **applied to prod** (2026-06-24) — package hold only, no restart, 27 containers stayed up, idempotent | — |
| done | `ssh_hardening` **applied to prod** (2026-06-24) — root off the public internet; `ai` on (key/password, in 1Password); idempotent | — |
| done | `firewall` **reworked + applied to prod** (2026-06-24) — declarative SSH lockdown only (no full-table drift); no-op on IPv4, closed an IPv6 gap; idempotent | — |
| done | `cloudflared` applied to prod (2026-06-24) — unit verbatim (no restart); token reconciled into `op://vibe_coding/cf-tunnel-hetz` (no-op verified) | — |
| done | **Phase 2 complete** — firewall, docker, ssh_hardening, cloudflared all live on prod | — |
| done | Phase 3 (host-layer scope) — secrets in 1Password; app-layer secrets out of scope (their repos) | — |
| done | Phase 4 CI **pipeline working** (2026-06-24) — Tailscale tag:ci + 1Password + CI key; **drift detection LIVE** (daily); PR diffs via check.yml | — |
| open | Flip `ENABLE_AUTO_APPLY=true` (auto-apply on merge) + run the self-test — the last switch | owner decision |
| open | Phase 3: migrate secrets into 1Password one at a time | needs 1Password vault access |
| blocked | Phase 4: enable CI auto-apply + drift alerts | needs `OP_SERVICE_ACCOUNT_TOKEN`, Tailscale `tag:ci`, `ENABLE_AUTO_APPLY` as GitHub secrets/vars |

## 15. How to make a change (the supported path)

1. Edit the relevant role/var in this repo (on `main` — this project works main-only).
2. Validate locally: `ansible-lint` and `ansible-playbook playbooks/site.yml --syntax-check`
   (see `docs/development.md`).
3. For host-affecting changes, run a read-only `--check --diff` against `hetz` before applying.
4. Apply (currently manual from WSL; CI once Phase 4 is enabled). Re-run to confirm 0 changes.

**Never** SSH in and `apt install` / `crontab -e` / edit `/etc` by hand. Manual changes are drift
and get reverted by the next apply.
