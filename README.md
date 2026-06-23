# Host-Layer Ansible — `hetz` (and friends)

This repo turns the hand-built Hetzner production server into **code you can rebuild from**.
It manages the **host/OS layer only** — packages, users, firewall, systemd units, cron, the
Docker *engine*, DNS hardening, and glue scripts. It does **not** manage the apps.

> **Golden rule — read this first.**
> **To change the server, change this repo.** Open a pull request, get the `--check` diff,
> merge it. **Never** SSH in and `apt install`, `crontab -e`, or edit `/etc` by hand.
> Manual changes will be detected by drift-detection and silently reverted by the next apply.

This README is written for a **non-engineer operator** ("vibe-coder") who drives everything
through AI and approves diffs. If a section reads like background, read it anyway — the
background is where the landmines are. The full brief lives in
[`docs/ANSIBLE-IMPLEMENTATION-PLAN.md`](docs/ANSIBLE-IMPLEMENTATION-PLAN.md).

---

## What is and isn't managed here

| Layer | Owner | Examples |
|---|---|---|
| **Apps** (~20 containers) | **Coolify** — NOT this repo | Pop apps, HiClaw, DevOps MCP, oauth2-proxy, Tunnels 2 & 3 |
| **Host / glue** | **This repo (Ansible)** | OS packages, `ai` user, firewall, DNS config, Docker `daemon.json`, Tunnel 1 systemd unit, backup watchdog, cron *entries* |

**Ansible owns the host and the glue. Coolify owns the apps.** Fighting Coolify causes
reconcile loops — see the landmines in the plan (§3).

---

## Repository layout

```
ansible.cfg                 inventory path, no host-key prompt in CI, passwordless sudo
inventory/
  hosts.ini                 [hetzner] now; [do_backup_wiz] later
  group_vars/all.yml        non-secret vars (secrets come from 1Password at apply time)
playbooks/site.yml          the entrypoint; roles tagged phase1 / phase2
roles/
  base/                     apt packages, timezone, unattended-upgrades, journald   [non-disruptive]
  users/                    the `ai` user, sudo, authorized_keys (public keys only) [non-disruptive]
  dns_hardening/            resolved fallback-dns + docker live-restore (§3.3)       [non-disruptive]
  backrest_watchdog/        backup self-heal systemd timer (§3.4)                    [non-disruptive]
  firewall/                 iptables + netfilter-persistent + fail2ban     ⚠️ RISKY — can lock out SSH
  docker/                   daemon.json ONLY; pinned, NEVER auto-restart   ⚠️ RISKY — hits Coolify
  cron_glue/                cron ENTRIES only (keeper scripts stay in HiClaw repo)
  cloudflared_coolify/      Tunnel 1 systemd unit + env file               ⚠️ RISKY — live tunnel
.github/workflows/
  check.yml                 on PR: ansible-lint + --check --diff, posts the diff
  apply.yml                 on merge to main: real apply, serialized (GATED OFF by default)
  drift.yml                 daily --check --diff; alerts on drift, never applies
files/cloud-init/           first-boot bootstrap (user-data) so the box is code-defined from zero
bin/discover.sh             Phase 0: capture live host state to compare against the roles
docs/                       the implementation plan + this project's status
```

---

## How to make a change (the only supported path)

1. Edit the relevant role/var in this repo on a branch.
2. Open a pull request. CI runs `ansible-lint` + `ansible-playbook --check --diff` and posts
   **exactly what would change** on the server.
3. A human reads the diff and merges. On merge, CI applies it **once, serialized** (no two
   applies ever run at the same time — that's the guarantee against 7 AI sessions colliding).

You never touch the server directly. That's the whole point.

---

## Safety model (why the risky roles won't take the box down)

These rules are enforced in code, not just documented:

- **Phase gating.** `playbooks/site.yml` splits roles into `phase1` (non-disruptive) and
  `phase2` (risky). Phase 2 roles only run when `enable_phase2: true` is set, so they can't be
  applied to prod before they've been proven on a throwaway scratch host (plan §9).
- **Firewall keeps your lifeline open.** The role *asserts* that the templated ruleset keeps the
  `tailscale0` interface and SSH reachable before it will apply, and applies behind an
  **auto-revert timer** so a wrong rule un-does itself in 60s. Tailscale (`100.66.37.58`) is the
  out-of-band way back in.
- **Docker never auto-restarts.** The `docker` role manages `daemon.json` only, pins the
  `docker-ce` version, and a config change merely **prints "restart required in a maintenance
  window"** — Ansible will not bounce the daemon (a restart hits Coolify + ~20 containers and
  causes docker.sock staleness — the June 2026 outage).
- **CI auto-apply is OFF until earned.** `apply.yml`'s real-apply step is guarded by the
  `ENABLE_AUTO_APPLY` repository variable. Until Phases 1–3 pass, CI is **check / PR-diff only**.

---

## Secrets

Nothing secret is committed. Secrets live in **1Password** (vault `vibe_coding`) and are injected
at apply time via the `1password/load-secrets-action`, referenced as
`op://vibe_coding/<item>/<field>`. The **only** secret stored in GitHub is the 1Password Service
Account token. See the migration table and gating in the plan (§5.2, §9, Phase 3) — secrets are
**not yet migrated**; that is its own gated phase.

⚠️ The 1Password Service-Account token can **expire** and will silently break the whole pipeline.
When it's created, note the expiry and set a rotation reminder a week before.

---

## Where things stand

This repo is currently at **Phase 0 — scaffold complete, nothing applied to any host.** See
[`docs/STATUS.md`](docs/STATUS.md) for the phase checklist and what's next.

To capture the live host state before proving roles:

```bash
ssh ai@hetz 'sudo bash -s' < bin/discover.sh   # writes discovery/, changes nothing
```
