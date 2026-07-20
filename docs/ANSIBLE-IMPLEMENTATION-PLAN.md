# Implementation Plan — Host-Layer Ansible + GitHub Actions Apply Pipeline

> **You are a fresh AI session with no prior context. Read this entire document before doing
> anything.** It is the complete brief for turning a hand-built production server into a
> reproducible, code-managed system. It was written by a previous session that audited the server
> in depth; every non-obvious detail here was learned the hard way. Do not skip sections because
> they "look like background" — the background is where the landmines are.

---

## 0. TL;DR of what you are building

1. An **Ansible** project (this repo, `u2giants/Ansible`) that declaratively manages the
   **host/OS layer** of one Hetzner VPS — packages, users, firewall, systemd units, cron,
   Docker, and the "glue" scripts — so the box can be rebuilt from code.
2. A **GitHub Actions workflow** that is the **single, serialized apply point**: changes land as
   pull requests; merging to `main` runs `ansible-playbook` against the server. No human and no
   other AI session applies host changes by hand, ever.
3. **Secrets sourced from 1Password** (`op` CLI) at apply time — never committed, never in plaintext
   `.env` on disk where avoidable.

The end state: if the server is destroyed, a new Ubuntu box + this repo + the 1Password vault +
the data backups = full recovery, with no tribal knowledge required.

---

## 1. Who this is for and why (do not lose this nuance)

The owner is a **"vibe-coder": not a sysadmin or devops engineer.** They drive everything through
AI (Claude Code, Codex) and act as approver/operator, not implementer. Consequences that must
shape every decision you make:

- **Favor boring, well-documented tooling.** Ansible (plain YAML, huge corpus) over NixOS/Salt.
  The owner cannot debug a clever solution when it breaks; neither can the next AI session reliably.
- **Explain, don't just emit.** Every role and workflow needs a README a non-engineer can follow.
- **Optimize for "AI authors, human approves."** The human reads diffs and clicks merge. The
  pipeline must make the safe path the easy path.
- **The owner runs ~7 concurrent AI sessions across ~5 apps.** The single most important property
  of this system is preventing those sessions from making conflicting, drift-inducing changes to
  one shared server. See §6.

The mental model the owner has bought into: **"pets vs. cattle."** The server is currently a
hand-raised *pet* (a snowflake nobody fully understands). The goal is *cattle*: rebuildable from
code, where every change that ever made it special is written down as runnable code, not done by
hand. **A descriptive `.md` of the server is NOT the goal — runnable code that rebuilds it is.**

---

## 2. The server you are managing

- **Provider/OS:** Hetzner VPS, **Ubuntu 24.04.4 LTS** ("noble"), 16 GB. Hostname `hetz`.
- **Public IP:** `178.156.180.212`. **Tailscale IP:** `100.66.37.58`. Domain: `designflow.app`
  (DNS on Cloudflare).
- **Primary user:** `ai` (has **passwordless sudo**). Also `root`. SSH in as `ai` or `root`.
- **This is a single server today.** Design the Ansible inventory to scale to N hosts (there is
  also a DigitalOcean droplet running the backup monitor — see §2.3 — and a "compshop" server
  referenced in backup configs), but only this one host is in scope for the first iteration.

### 2.1 The two layers (critical mental model)

**Do not try to capture everything equally.** The server has two layers in very different shape:

- **App layer = Coolify.** Coolify (`coolify`, `coolify-db`, `coolify-redis`, `coolify-realtime`,
  `coolify-sentinel`, `coolify-proxy`) manages ~20 application containers (the Pop apps, HiClaw,
  DevOps MCP/ContextForge, Synology Monitor, EmailCleanup, etc.). **This layer is already codified**
  — Coolify deploys from GitHub repos/images and stores its state in `coolify-db` + `/data/coolify`.
  **Ansible must NOT try to manage application containers.** That is Coolify's job; fighting it
  causes reconcile loops.
- **Host/glue layer = your job.** Everything Coolify does *not* manage: the OS, packages, Docker
  engine install, the firewall, system cron jobs, manually-managed systemd units (tunnels, the
  backup watchdog), `/etc` config, users/SSH. **This is what your Ansible encodes.**

So the scope boundary is: **Ansible owns the host and the glue; Coolify owns the apps.** Where they
meet (e.g. the Docker daemon Coolify runs on, the Traefik proxy config Coolify generates) is
documented in §3 as "manage the install, leave the runtime to Coolify."

### 2.2 What actually runs at the host level (encode these)

Discover the live truth on the box (commands in §7), but here is what the audit found so you know
what to expect:

- **Docker** (engine + compose plugin), **containerd**. Coolify and all apps run on this.
- **Enabled systemd services** (non-default highlights): `docker`, `containerd`, `fail2ban`,
  `netfilter-persistent` (persists iptables), `cloudflared-coolify.service` (Cloudflare tunnel,
  systemd-managed, NOT a container), `coolify-autostart.service`, `snapd`, and
  `backrest-dump-watchdog.timer` (added 2026-06-22, self-heals the backup agent).
- **Disabled but present:** `socks5-home-tunnel.service` (SSH SOCKS proxy to a home machine via
  Tailscale; intentionally disabled — do NOT enable).
- **Cron (root):** several `/worksp/hiclaw/*.sh` "keeper" scripts run every minute (config
  reconciliation for HiClaw/OpenClaw); `/home/ai/bin/sync-infra-docs.sh` every 15 min
  (auto-commits infra docs to git). `/etc/cron.d`: `e2scrub_all`, `sysstat`.
- **Firewall:** iptables rules persisted at `/etc/iptables/rules.v4` and `rules.v6` via
  `netfilter-persistent`. `fail2ban` enabled.
- **DNS hardening (already applied, see §3.3):** `/etc/systemd/resolved.conf.d/fallback-dns.conf`,
  `/etc/docker/daemon.json` with `"live-restore": true`.
- **Glue scripts:** `/usr/local/bin/backrest-dump-watchdog.sh`,
  historically a `docker-rename-containers.sh` (a rename service no longer present — verify).

### 2.3 Related machines (context, not first-iteration scope)

- **DigitalOcean droplet** running `restore-wizard` / `backrest-wiz` (the backup monitor UI at
  `backup.designflow.app`). It already has an **Ansible playbook** authored in the `restore-wizard`
  repo under `ansible/` (idempotent: Docker, the compose stack, `.env` from vaulted vars). Fold
  this droplet into the same inventory/pipeline eventually so both servers are managed from one
  place. **This Hetzner box has no SSH path to the droplet** (the droplet deploys via its own
  GitHub Actions using `DEPLOY_HOST`/`DEPLOY_SSH_KEY` secrets) — so manage it from the CI runner.

---

## 3. Server-specific landmines (this is the section that prevents outages)

These are real incidents and gotchas from this exact server. Your Ansible must respect every one.
The authoritative live reference is `/worksp/infra/CLAUDE.md` and `/home/ai/CLAUDE.md` on the box —
**read both before writing roles.** Summary of what must not be broken:

### 3.1 Cloudflare Tunnels — three independent tunnels, do not consolidate
- **Tunnel 1** `coolify.designflow.app`: **systemd-managed** `cloudflared-coolify.service`, token in
  `/etc/cloudflared/coolify-tunnel.env` (root-only, not in git). Routes by **anchored regex** paths
  (`^/app(/|$)` → Soketi `:6001`, `^/terminal/ws(/|$)` → `:6002`, else Coolify `:8000`).
  **The regexes MUST stay anchored** — an unanchored `/app` matches asset filenames like
  `app-C9Z.js` and misroutes them (404s, then Cloudflare caches the 404 for 4h). Config lives
  remotely in Cloudflare, not in a local file.
- **Tunnels 2 & 3** (`mcp.designflow.app`, `mcpgw.designflow.app`): **Coolify-managed containers**
  (`cloudflared-vj5...`, `cf-cloudflared-vj5...`). **Coolify owns their lifecycle — never
  start/stop/recreate them by hand.**
- **Ansible implication:** you may manage Tunnel 1's systemd unit + its env file (root-only secret
  via 1Password), but **must not** touch Tunnels 2/3. Do not create a generic "cloudflared" role
  that would fight Coolify.

### 3.2 Traefik (`coolify-proxy`) — Coolify overwrites your changes
- Config in `/data/coolify/proxy/`. Two cert resolvers: `letsencrypt` (HTTP-01, direct subdomains)
  and `letsencrypt-dns` (DNS-01 via Cloudflare API token `CF_DNS_API_TOKEN`, for tunnel subdomains).
- **Coolify reverts `certresolver: letsencrypt-dns` back to `letsencrypt` whenever the proxy is
  restarted from the UI**, which breaks `coolify.designflow.app` certs. There is a manual `sed`
  fix documented. **Do not have Ansible manage Traefik's dynamic config** — it's Coolify-owned and
  will fight you. At most, document the gotcha.

### 3.3 DNS cascade (the May 2026 outage) — keep the fixes intact
- The host uses `systemd-resolved` (`127.0.0.53`), which is **unreachable from inside containers.**
  When host DNS broke, Docker's DNS relay (`127.0.0.11`) broke, and **every tunnel/oauth2-proxy
  container crashed simultaneously.** Fixes that are now in place and your Ansible must preserve
  (encode them as managed files so a rebuild reapplies them):
  - `/etc/systemd/resolved.conf.d/fallback-dns.conf` → `FallbackDNS=1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4`
  - `/etc/docker/daemon.json` → keeps `"live-restore": true`. **CORRECTED 2026-06-23 after live
    discovery:** the real file DOES carry a `dns` key — `"dns": ["1.1.1.1","8.8.8.8"]` (public
    resolvers) — alongside `log-opts` and `default-address-pools`, and works fine on Docker
    29.6.0. The actual landmine is narrower than first written: the `dns` key must **never** point
    at `127.0.0.53` (the host resolved stub, unreachable from containers). The `docker` role now
    deploys the file verbatim and asserts `127.0.0.53` never appears.
  - `oauth2-proxy` compose sets per-container `dns: [1.1.1.1, 8.8.8.8]` (it does OIDC discovery on
    every startup and exits code 1 if DNS fails). That file is at
    `/worksp/hiclaw/oauth2-proxy/docker-compose.yml` — manually managed, not Coolify.

### 3.4 The docker.sock staleness lesson (the June 2026 outage)
- Long-running containers that bind-mount `/var/run/docker.sock` (e.g. the `backrest` backup agent)
  **lose access when the host Docker daemon restarts** (the socket is recreated; the container holds
  a stale handle). This silently broke database backups for 4 days. The same event broke
  `coolify-proxy` route discovery. **Fix already deployed:** `backrest-dump-watchdog.timer` restarts
  the affected container when it detects the wedged state. **Lesson for your roles:** anything that
  depends on docker.sock from inside a container needs either a host-side execution path or a
  watchdog. Prefer running host-level scripts (cron/systemd on the host) over in-container
  docker.sock when you have the choice.

### 3.5 Things you must NOT do
- Do **not** manage application containers or Coolify-owned resources with Ansible.
- Do **not** set `HTTP_PROXY`/`HTTPS_PROXY`/`ALL_PROXY` anywhere (the SOCKS tunnel on `:1080` is
  intentionally disabled; proxy env vars silently break tools/containers).
- Do **not** enable `socks5-home-tunnel.service`.
- Do **not** point `daemon.json`'s `dns` key at `127.0.0.53` (the host stub). A `dns` key with
  **public** resolvers is correct and is what's deployed (corrected 2026-06-23 — see §3.3).
- Do **not** commit secrets. Tunnel tokens, the Cloudflare API token, restic/S3 creds, the GHCR
  PAT, OAuth secrets all live in **1Password** (vault `vibe_coding`) and are injected at apply time.
- Do **not** create/push new external repos or relocate infra content without the owner's explicit
  approval (the permission classifier blocks this by design; surface it, don't work around it).

---

## 4. Target repository layout (this is the root of the `u2giants/Ansible` repo)

```
.                                 # repo root of u2giants/Ansible (its own dedicated repo)
├── README.md                     # what this is, how to apply, how to add a change (non-engineer level)
├── ansible.cfg                   # inventory path, ssh settings, no host key prompt in CI
├── inventory/
│   ├── hosts.ini                 # [hetzner] and (later) [do_backup_wiz] groups
│   └── group_vars/
│       └── all.yml               # non-secret vars; secrets pulled from 1Password at runtime
├── playbooks/
│   └── site.yml                  # the entrypoint: applies all roles to hetzner
├── roles/
│   ├── base/                     # apt packages, timezone, unattended-upgrades, journald limits   [non-disruptive]
│   ├── users/                    # the `ai` user, sudo, authorized_keys (public keys only)        [non-disruptive]
│   ├── dns_hardening/            # resolved.conf.d/fallback-dns.conf  (see §3.3)                   [non-disruptive]
│   ├── firewall/                 # iptables rules.v4/v6 + netfilter-persistent + fail2ban    ⚠️ RISKY — see §4a
│   ├── docker/                   # daemon.json ONLY; pinned version, NEVER auto-restart      ⚠️ RISKY — see §4a
│   ├── cron_glue/                # cron ENTRIES only; keeper SCRIPTS stay in the HiClaw repo  (see §4a)
│   ├── backrest_watchdog/        # the backup self-heal timer (already authored, in backrest-wiz/hetzner-producer)
│   └── cloudflared_coolify/      # Tunnel 1 systemd unit + env file (token from 1Password)   ⚠️ RISKY — see §4a
├── files/ , templates/           # static files + jinja templates referenced by roles
└── .github/workflows/
    └── apply.yml                 # the serialized apply pipeline (see §5)
```

Notes:
- Keep roles **small and single-purpose**; each maps to one landmine-free unit of the host.
- Use `ansible.builtin` modules only where possible (no exotic collection dependencies) so any AI
  session can run it with a stock Ansible install.
- Make **every task idempotent** and safe to re-run. Use `--check` (dry-run) in CI on PRs.

### 4a. Safety rules for the risky roles (read before writing `firewall`, `docker`, `cloudflared_coolify`)

These three roles can take the box down. They are **gated to Phase 2** (see §9) and must be proven
on a throwaway host before they ever touch prod.

- **`firewall` — can lock you out of SSH. Highest practical risk.**
  - Your out-of-band lifeline is **Tailscale** (`100.66.37.58`). Every templated ruleset MUST keep
    the `tailscale0` interface and SSH open. Assert this in the role before applying.
  - Staged flow: capture current rules → template them → `--check`/`--diff` → **verify Tailscale +
    SSH reachability** → only then apply.
  - Apply with an **auto-revert timer** (an `at`/systemd one-shot that reloads the last-known-good
    rules in 60s unless you confirm). A wrong rule then un-does itself instead of stranding you.
  - Never apply firewall changes blind from CI before the auto-revert + reachability checks exist.

- **`docker` — a daemon restart hits Coolify + ~20 containers, and restarts cause docker.sock
    staleness (the June 2026 outage).**
  - Manage **`daemon.json` only** (keep `live-restore: true`, no `dns` key). **Pin the `docker-ce`
    package version** — do NOT let the role upgrade Docker.
  - **Ansible must NEVER auto-restart Docker.** A `daemon.json` change should `notify` a handler that
    is **manual-gated** (prints "Docker restart required — do it in a maintenance window"), not one
    that restarts automatically.
  - Any deliberate Docker restart must be followed by bouncing the `backrest` container (docker.sock
    staleness — now also covered by `backrest-dump-watchdog`).

- **`cloudflared_coolify` — touches a live tunnel.** Manage only Tunnel 1's systemd unit + env file.
  Never touch the Coolify-owned Tunnels 2/3 (§3.1). Validate the tunnel reconnects after any change.

- **`cron_glue` — ownership decided:** Ansible owns the **cron entry** (that it exists, on what
  schedule); the **keeper scripts** in `/worksp/hiclaw/*.sh` belong to the HiClaw repo, NOT host
  Ansible. (Those minute-by-minute reconciliation loops are an app-layer smell; don't adopt them.)

- **`--check` mode is not reliably read-only.** `command`/`shell` tasks either skip or actually run
  in check mode, so a PR diff can lie. Therefore: minimize `command`/`shell`; mark genuine reads
  `check_mode: false` deliberately; and **do not trust prod `--check` for the risky roles** — prove
  them on the throwaway host (§8.3) first. Validate check-mode behavior role-by-role.

---

## 5. The GitHub Actions apply pipeline (the serialization point)

This is the heart of the "7 AI sessions can't collide" guarantee. Design:

### 5.1 Flow
1. Any change to the host is made by **editing this repo and opening a PR** — never by SSHing in.
2. **On PR:** CI runs `ansible-lint` + `ansible-playbook --check --diff` against the server (read-only
   dry run) and posts the diff. The human reviews what *would* change.
3. **On merge to `main`:** CI runs `ansible-playbook` for real. **Concurrency is serialized** so two
   merges never apply at once:
   ```yaml
   concurrency:
     group: apply-hetzner
     cancel-in-progress: false   # queue, never run two applies simultaneously
   ```
4. The runner reaches the server over **SSH via Tailscale** (preferred) or public IP. Use the
   official **`tailscale/github-action`** with an **ephemeral, tagged auth key** (e.g. `tag:ci`) or a
   Tailscale OAuth client. **Ephemeral is required** — it auto-removes the runner's node from the
   tailnet when the job ends, so dead CI nodes don't accumulate. Restrict `tag:ci`'s ACLs to only
   the hosts/ports CI needs (SSH to the managed servers).

### 5.2 Secrets (1Password)
- The owner wants secrets in **1Password** (`op` CLI; vault `vibe_coding`). In CI, use the official
  **`1password/load-secrets-action`** with a **1Password Service Account token** (the only secret
  stored directly in GitHub). All other secrets (SSH key, tunnel tokens, CF API token, restic/S3
  creds) are referenced as `op://vibe_coding/<item>/<field>` and injected as env vars at apply time,
  then passed to Ansible via `--extra-vars` or `lookup('env', ...)`.
- ⚠️ **The 1Password Service Account token can EXPIRE.** If it expires silently, the entire apply
  pipeline (and drift detection, §5.5) fails abruptly. When you create it: note its expiry, and set a
  **rotation reminder** a week before. (Don't schedule one yet — the token doesn't exist until the
  pipeline is built; create the reminder at that point.) Also confirm the SA is scoped to *only* the
  `vibe_coding` vault (it already is for the local `op` CLI).
- **This is its own gated phase (Phase 3, §9), not a side task.** Secrets are NOT yet in 1Password —
  they live in plaintext `.env` files and configs, and one was even embedded in a git remote. Migrate
  them **one at a time**, each with a validation and a rollback, working down the inventory below.
  Never delete the plaintext source until the `op`-sourced value is validated working.

#### Secrets inventory (seed — verify and extend on the box; record values ONLY in 1Password)

| Secret | Current location(s) | Target `op` item | Consuming service | Validate | Rollback |
|---|---|---|---|---|---|
| GitHub PAT | `~/.netrc`, `~/.claude.json` (`GITHUB_TOKEN`) | `vibe_coding/github-pat` ✅ *done* | git, curl, GitHub MCP | `curl -H "Authorization: token $T" https://api.github.com/user` → 200 | `.bak-*` files / re-mint |
| Restic repo password | `/opt/backrest/config/config.json` (`repos[0].password`) | `vibe_coding/restic-hetzner` | backrest / restic | `restic snapshots` succeeds | restore `config.json` backup |
| DO Spaces access+secret keys | `config.json` env (`AWS_*`); `restore-wizard/.env` (`DO_SPACES_*`) | `vibe_coding/do-spaces` | backrest→S3, restore-wizard | `restic snapshots` / S3 list | restore config/.env backup |
| Cloudflare DNS API token | `coolify-proxy` env + `/data/coolify/proxy/docker-compose.yml` (`CF_DNS_API_TOKEN`) | `vibe_coding/cf-dns-token` | Traefik DNS-01 certs | cert renew / CF API test | restore compose backup |
| CF Tunnel 1 token | `/etc/cloudflared/coolify-tunnel.env` | `vibe_coding/cf-tunnel-hetz` | `cloudflared-coolify.service` | tunnel reconnects | restore env backup |
| GHCR PAT | GitHub Actions secret + `/root/.docker/config.json` | `vibe_coding/ghcr-pat` | image pulls / deploy | `docker pull` a private image | `docker login` again |
| restore-wizard app secrets (~25: OpenRouter, Google OAuth id/secret, `SESSION_SECRET`, …) | `restore-wizard/.env` (DO droplet) | one `op` item per secret | restore-wizard app | app boots + Google login works | restore `.env` backup |
| oauth2-proxy secrets | `/worksp/hiclaw/oauth2-proxy/.env` | `vibe_coding/oauth2-proxy` | `oauth2-proxy` | OIDC discovery succeeds at startup | restore `.env` backup |

> Out of scope here: **Tunnels 2/3 tokens** (`TUNNEL_TOKEN`, `CF_GW_TUNNEL_TOKEN`) are Coolify-managed
> — leave them with Coolify, don't migrate via host Ansible.

### 5.3 Why CI and not on-box Ansible
The owner explicitly chose a CI runner over installing Ansible on the server because: the control
node is **ephemeral/external** (survives the server dying — critical for rebuild), it **naturally
serializes** applies, it **scales to N servers** via inventory, and it keeps the **truth in git**.
On-box Ansible was rejected (chicken-and-egg on rebuild, no serialization). Honor this choice.

### 5.4 First-boot bootstrap — automate it with Cloud-Init (no manual step)

A brand-new server can't be reached by CI until it has an SSH user + key + Tailscale + Python. On
**Hetzner Cloud**, do this with zero manual steps by passing a **Cloud-Init `user-data`** script at
provision time (Hetzner Cloud console/API/Terraform all accept it). The script, run as root on first
boot, should:
- create the `ai` user with passwordless sudo + install the CI SSH public key,
- `apt install` Python 3 (for Ansible),
- install Tailscale and `tailscale up --authkey <ephemeral tag:ci key> --ssh`.

After first boot the box is reachable by CI and the rest is fully code-driven — **the server is
code-defined from second zero.** Keep the user-data template in the repo (the Tailscale auth key is a
secret → injected at provision time from 1Password, never committed).

> Caveat: this is **Hetzner Cloud** `user-data`. Hetzner **dedicated/Robot** servers use `installimage`
> + a post-install script instead — same idea, different mechanism. Confirm which product this box is.
> Fallback for any provider: a one-shot `bootstrap.sh` run once from a laptop.

### 5.5 Scheduled drift detection (enforce "the repo is the truth")

Serialization (§6) stops *repo* changes from colliding, but it does **not** stop a rogue session or
human from SSHing in and hot-fixing the live server out-of-band. Close that gap with a **scheduled**
GitHub Actions job (e.g. daily 03:00 UTC) that runs `ansible-playbook --check --diff` and **fails +
alerts if it detects any drift** between the code and the live host. This makes undocumented manual
changes loud instead of silent.
- It is **check-only** — it must never apply.
- Trust it most for the non-disruptive roles; `--check` fidelity is weaker for the risky roles (§4a),
  so treat their drift signal as "investigate," not "auto-anything."
- Wire the alert to wherever the owner will actually see it (the same channel as backup alerts).

---

## 6. The 7-concurrent-AI-sessions problem (design requirement, not optional)

The owner runs many AI sessions against shared infrastructure. Without discipline they re-create
the original "pet server" drift. The system must enforce:

- **One apply path.** Host changes happen ONLY through this repo's PR→merge→CI pipeline. The CI
  `concurrency` group serializes them. No session runs `ansible-playbook` locally against prod.
- **App changes stay in app repos** and deploy through Coolify (already the case). Ansible is for
  the host only, so app sessions and infra sessions don't touch the same files.
- **The filesystem/git is the source of truth, not any chat's memory.** A coordinator pattern, if
  built later, must read state from git/files and dispatch scoped workers — never hold everything in
  one context window. (The owner asked about a "single coordinator"; the honest answer is there is
  no cross-tool always-on coordinator, and the real guarantee comes from the serialized pipeline +
  per-project state, not a chat UI.)
- **Document the rule loudly** in the repo README: "To change the server, change this repo. Never
  `apt install` / `crontab -e` / edit `/etc` on the box directly. Manual changes will be silently
  reverted by the next apply."

---

## 7. How to discover the current state to encode (run these first)

Do not guess what's on the box — inventory it, then write roles that reproduce it. Useful commands
(run on the server, you have sudo):

```bash
# Packages explicitly installed (not pulled in as deps):
comm -23 <(apt-mark showmanual | sort) <(gzip -dc /var/log/installer/initial-status.gz 2>/dev/null | sed -n 's/^Package: //p' | sort)
# Enabled services:
systemctl list-unit-files --state=enabled --type=service
systemctl list-timers --all
# Cron:
crontab -l; sudo ls -la /etc/cron.d /etc/cron.daily; sudo cat /var/spool/cron/crontabs/* 2>/dev/null
# Firewall:
sudo iptables-save; sudo cat /etc/iptables/rules.v4 /etc/iptables/rules.v6
# Users with login + sudo:
getent passwd | awk -F: '$7!~/nologin|false/'; sudo cat /etc/sudoers.d/*
# Managed /etc files of interest:
ls -la /etc/systemd/resolved.conf.d/ /etc/docker/daemon.json /etc/cloudflared/
# Glue scripts:
ls -la /usr/local/bin/ /home/ai/bin/ /worksp/hiclaw/*.sh
# Docker engine version + compose:
docker version; docker compose version
```

Encode the **host** outputs of these into roles. Skip anything Coolify-owned (app containers,
Traefik dynamic config, Coolify's own systemd autostart beyond noting it exists).

---

## 8. Verification — definition of done (do NOT skip; this is the whole point)

A backup/rebuild plan you have never tested is a hope, not a plan. Prove it:

1. **Idempotency:** running `ansible-playbook playbooks/site.yml` twice yields **zero changes** on
   the second run. If not, the role isn't truly declarative — fix it.
2. **`--check` cleanliness:** on the real server, `--check --diff` shows no surprise drift after a
   successful apply.
3. **Rebuild-and-diff (the real test):** provision a **throwaway** Hetzner/DO box, run bootstrap +
   the full pipeline against it, and **diff it against the real server**: package lists, enabled
   services, listening ports, firewall rules, key `/etc` files. Every difference is either a bug in
   your roles or an undocumented manual change on prod — chase each to zero. This is how you *prove*
   completeness instead of hoping.
4. **No secrets in git:** `git log -p | grep -iE 'BEGIN.*PRIVATE|ghp_|gho_|aws_secret|password='`
   returns nothing. Confirm `.gitignore` covers vault files, inventories with IPs if sensitive, etc.
5. **Pipeline self-test:** open a trivial PR (e.g. add a managed motd line), confirm the `--check`
   diff posts, merge, confirm it applies and the concurrency group serializes.

---

## 9. Phased execution with hard gates (do them in order; do NOT skip a gate)

Each phase ends with a **GATE** that must pass before the next begins. The golden rule:
**no CI auto-apply until idempotency is clean AND the risky roles are proven on a throwaway host.**
Until then, CI is **check/PR-diff only**.

**Phase 0 — Observe & scaffold (zero changes to the host).**
Inventory the box (§7). Scaffold the repo (§4): `ansible.cfg`, inventory with the one host, empty
`site.yml`, README with the scope/rules (§6). Stand up a **throwaway scratch host** (a cheap
Hetzner/DO box) you'll use to prove roles before prod.
→ **GATE:** repo runs `ansible-playbook --list-tasks` cleanly; scratch host reachable.

**Phase 1 — Non-disruptive roles.** `base` → `users` → `dns_hardening` → `backrest_watchdog`.
These are additive/low-risk. Apply `--check` then for real, on scratch first, then prod.
→ **GATE:** each role is **idempotent** (second run = 0 changes) on both scratch and prod.

**Phase 2 — Risky live-service roles (the ones that can take the box down).**
`firewall` → `docker` → `cloudflared_coolify`, following the §4a safety rules (Tailscale lifeline +
auto-revert for firewall; pinned + never-auto-restart for docker; live-tunnel care for cloudflared).
**Prove every one on the scratch host with a full rebuild-and-diff (§8.3) BEFORE it touches prod.**
Do not trust prod `--check` for these (§4a). Apply to prod only in a maintenance window, one role at
a time, watching for breakage.
→ **GATE:** scratch-host rebuild-and-diff is clean; prod apply caused no Coolify/DNS/tunnel/SSH
disruption; all roles idempotent.

**Phase 3 — Secrets migration (§5.2).** Work down the inventory table **one secret at a time**:
put it in 1Password → switch the consumer to the `op` reference → run its validation → only then
delete the plaintext source. Roll back on any failure.
→ **GATE:** every secret validated from `op`; no plaintext secret remains; `git log -p | grep` for
token/key patterns is empty (§8.4).

**Phase 4 — CI auto-apply enablement (§5).** Until now CI has been **check/PR-diff only**. Only after
Phases 1–3 gates pass, enable apply-on-merge with the `concurrency` guard. Run the pipeline
self-test (§8.5). Turn on **scheduled drift detection** (§5.5) and create the **1Password SA-token
rotation reminder** (§5.2). Then fold in the DO droplet (§2.3) as a second inventory group.
→ **GATE (definition of done):** a trivial PR shows a `--check` diff, merges, applies serially; a
fresh throwaway box rebuilt entirely from bootstrap + pipeline **diffs clean** against prod (§8.3).

---

## 10. Things to confirm with the owner before/while building (open questions)

- **CI runner network path** — Tailscale (recommended) vs public-IP SSH. Needs a CI key/auth method
  the owner provisions. (Tailscale is also the firewall out-of-band lifeline — §4a.)
- **Repo push approval** — pushing here requires the owner's explicit OK (the classifier blocks
  agent-initiated repo creation/bulk push). This project lives in its own dedicated repo
  (`u2giants/Ansible`) — commit to its `main` branch, don't create new repos.
- **Legacy-backend teardown** — PopPIM migrated to hosted supabase.com; a scheduled reminder
  (2026-07-22) handles decommission via Coolify (not Ansible). Do not add a legacy-app role.

**Resolved (kept here for the record):**
- ~~`cron_glue` ownership~~ → **decided** (§4a): Ansible owns the cron *entry*; the keeper *scripts*
  stay in the HiClaw repo.
- ~~Secrets migration scope~~ → **defined** as gated Phase 3 with the inventory table (§5.2, §9).

---

## 11. Reference material already on the box (read these)

- `infrastructure/CLAUDE.md` (this repo) — the authoritative live server reference (traffic routing,
  tunnels, DNS, ports, Cloudflare IDs, "things you must not do"). **Read fully.** (A copy is also
  auto-loaded on the box at `/home/ai/CLAUDE.md`.)
- `infrastructure/DECISIONS.md` + `infrastructure/HANDOFF.md` (this repo) — the *why* and the living
  status of this initiative.
- **`backrest-wiz` repo → `hetzner-producer/`** — the backup system: `README.md` (incident record),
  `BACKUP-MANIFEST.md`, `HANDOFF.md` (3-2-1 + restore-test gaps), `bin/` + `systemd/` (the watchdog
  you'll wrap in the `backrest_watchdog` role).
- **`backrest-wiz` repo → `ansible/`** — the existing DO-droplet playbook to model the `do_backup_wiz`
  host on and fold into this inventory.
- `infrastructure/post-mortems/` + `runbooks/` (this repo) — prior incidents (DNS cascade,
  cloudflared/oauth2 recovery) — good context, docs only.

---

*Written 2026-06-22 by an audit session. **Revised 2026-06-22** after two expert review passes —
added the phased gates (§9), role-safety rules for firewall/docker/cloudflared (§4a), the seeded
secrets inventory (§5.2), the `cron_glue` ownership decision, plus the operational hardening from the
second pass: Cloud-Init bootstrap (§5.4), scheduled drift detection (§5.5), ephemeral Tailscale CI
auth (§5.1), and 1Password SA-token expiry handling (§5.2). If anything here conflicts with what you
observe live on the server, trust the live server, update this document, and tell the owner what
changed.*
