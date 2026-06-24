# Architecture

System design of the host-layer Ansible project. For the operating rules and the
documentation map, see [`AGENTS.md`](../AGENTS.md). For the full original brief and every server
landmine, see [`ANSIBLE-IMPLEMENTATION-PLAN.md`](ANSIBLE-IMPLEMENTATION-PLAN.md).

## The two layers (the core mental model)

The server has two layers in very different shape. This repo owns exactly one of them.

- **App layer = Coolify.** ~20 application containers (Pop apps, HiClaw, MCPs, oauth2-proxy,
  etc.) deploy from their own GitHub repos via Coolify, which stores state in `coolify-db` +
  `/data/coolify`. **Out of scope. Ansible must not manage app containers** — fighting Coolify
  causes reconcile loops.
- **Host/glue layer = this repo.** Everything Coolify does not manage: the OS, packages, Docker
  *engine* install/config, firewall, system cron, host-managed systemd units (Cloudflare Tunnel
  1, the backup watchdog), `/etc` config, users/SSH.

Where they meet (the Docker daemon Coolify runs on; the Traefik config Coolify generates) the
rule is "manage the install, leave the runtime to Coolify."

## Components

```
control node (WSL today; GitHub Actions runner in Phase 4)
   │  ssh over Tailscale (100.66.37.58), become root
   ▼
playbooks/site.yml ──> roles (phase-tagged)
   ├─ Phase 1 (non-disruptive, APPLIED):
   │    motd, base, users, dns_hardening, backrest_watchdog
   └─ Phase 2 (risky, GATED behind enable_phase2):
        firewall, docker, cron_glue, cloudflared_coolify
inventory/hosts.ini ── [hetzner] (live), [scratch], [do_backup_wiz]
inventory/group_vars/all.yml ── non-secret vars
secrets ── 1Password (vibe_coding), injected at apply time
```

## Control flow / data flow

1. A change is made by editing this repo (roles/vars), not the box.
2. `check.yml` (on PR) runs `ansible-lint` + `ansible-playbook --check --diff` and posts the diff.
3. On merge to `main`, `apply.yml` runs — serialized by `concurrency: apply-hetzner` so two
   applies never overlap. Real apply is gated by `ENABLE_AUTO_APPLY` (currently unset → check-only).
4. `drift.yml` runs daily `--check` and alerts if the live host has drifted from the repo.

The serialization (one apply path) is the mechanism that lets ~7 concurrent AI sessions share one
server without drift: host changes can only land through this pipeline.

## Constraints that shape the design

- **Idempotency is mandatory.** Every role must be safe to re-run; second run = 0 changes.
- **`ansible.builtin` first** (plus `ansible.posix`) so any stock Ansible install can run it.
- **Risky roles are gated** (`enable_phase2`) and must be proven on a scratch host before prod
  (plan §9). `--check` is not fully reliable for command/shell tasks (plan §4a), so risky roles
  are proven by rebuild-and-diff, not trusted prod `--check`.
- **No secrets in git** — 1Password at apply time.
- **Reproduce reality, don't impose an ideal.** Roles are reconciled against live discovery
  (`DISCOVERY-2026-06-23.md`); some files (`daemon.json`, the backrest units) are vendored
  verbatim from the box for byte-idempotency.

## Roles (one concern each)

| Role | Phase | Concern |
|---|---|---|
| `motd` | 1 | Login banner announcing Ansible governance |
| `base` | 1 | apt packages, timezone, unattended-upgrades, journald cap |
| `users` | 1 | `ai` user, passwordless sudo, authorized public keys |
| `dns_hardening` | 1 | `resolved` FallbackDNS (May 2026 outage fix) |
| `backrest_watchdog` | 1 | docker.sock self-heal timer (June 2026 outage fix) |
| `firewall` | 2 | declarative `iptables` SSH lockdown only (host-owned INPUT rules), netfilter-persistent, fail2ban |
| `docker` | 2 | `daemon.json` only, pinned engine, never auto-restart |
| `cron_glue` | 2 | host cron entries only (not the keeper scripts) |
| `cloudflared_coolify` | 2 | Cloudflare Tunnel 1 systemd unit + token |
