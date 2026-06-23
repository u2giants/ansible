# u2giants/ansible — host-layer Ansible for `hetz`

Manages the **host/OS layer** of one Hetzner VPS (`hetz`) as code — packages, users, firewall,
DNS hardening, the Docker *engine* config, system cron, host systemd units, and glue scripts —
plus a serialized GitHub Actions apply pipeline. It does **not** manage the apps (Coolify owns
those).

> **To change the server, change this repo** — never SSH in and hand-edit `/etc`, `apt install`,
> or `crontab -e`. Manual changes are drift and get reverted by the next apply.

## Start here

- **[`AGENTS.md`](AGENTS.md)** — the canonical operating guide for developers and AI sessions.
  It has the **documentation map** that tells you which other docs to read for a given task, so
  you don't have to load everything. **Read it first.**
- [`CLAUDE.md`](CLAUDE.md) — Claude-Code-specific notes.
- [`HANDOFF.md`](HANDOFF.md) — current continuation state (present while work is unfinished).

## Docs

| Doc | For |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | system design, the host-vs-Coolify boundary, roles |
| [`docs/development.md`](docs/development.md) | local setup (WSL), validate, check, apply |
| [`docs/configuration.md`](docs/configuration.md) | vars, gates, secrets (no values) |
| [`docs/deployment.md`](docs/deployment.md) | the apply pipeline, SSH, rollback |
| [`docs/DISCOVERY-2026-06-23.md`](docs/DISCOVERY-2026-06-23.md) | live host state captured + reconciled |
| [`docs/ANSIBLE-IMPLEMENTATION-PLAN.md`](docs/ANSIBLE-IMPLEMENTATION-PLAN.md) | the full original brief (long) |

## Status (short)

Phase 0 (scaffold + discovery) and Phase 1 (non-disruptive roles) are **applied to prod and
idempotent**. Phase 2 (risky roles), Phase 3 (secrets → 1Password), and Phase 4 (CI auto-apply)
are pending — see [`HANDOFF.md`](HANDOFF.md) and `AGENTS.md` §14.
