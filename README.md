# u2giants/ansible — host-layer Ansible for `hetz`

Manages the **host/OS layer** of one Hetzner VPS (`hetz`) as code — packages, users, firewall,
DNS hardening, the Docker *engine* config, system cron, host systemd units, and glue scripts —
plus a serialized GitHub Actions apply pipeline. It does **not** manage the apps (Coolify owns
those).

> **To change the server, change this repo** — never SSH in and hand-edit `/etc`, `apt install`,
> or `crontab -e`. Manual changes are drift and get reverted by the next apply.

Developer-computer management is a separate, opt-in path. It is not part of
the Hetz production `site.yml`/auto-apply pipeline. A new Windows machine first
runs the minimum-touch bootstrap from `u2giants/ai-devops`; that establishes
Tailscale/OpenSSH and a WSL Ansible controller before this repository manages
Windows and Ubuntu computers through `playbooks/dev-computers.yml`.

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
| [`docs/dev-computers.md`](docs/dev-computers.md) | Windows/Ubuntu developer-computer desired state |
| [`docs/DISCOVERY-2026-06-23.md`](docs/DISCOVERY-2026-06-23.md) | live host state captured + reconciled |
| [`docs/ANSIBLE-IMPLEMENTATION-PLAN.md`](docs/ANSIBLE-IMPLEMENTATION-PLAN.md) | the full original brief (long) |

## Status (short)

The Hetz host pipeline is applied and operational; see `HANDOFF.md` for its
detailed history. The developer-computer roles are source-complete but have not
yet passed disposable Windows/Ubuntu live proof or second-run idempotency.
Real developer hosts remain commented out and are not wired into production CI.
