# CLAUDE.md

This file orients Claude Code (and other AI agents) working in this repository.

## ⛔ The rule that overrides everything

**To change the `hetz` server, change this repo — never the box by hand.**
Host changes go through a pull request to `u2giants/ansible` → CI `--check` diff → merge →
serialized apply. Do **not** SSH in and `apt install` / `crontab -e` / edit `/etc` / change
firewall or systemd by hand. Manual changes are drift and get reverted by the next apply.

The complete operating rules for any agent are in **[`AGENTS.md`](AGENTS.md)** — read it.

## What this repo is

Host-layer Ansible for one Hetzner VPS plus a serialized GitHub Actions apply pipeline. It
manages the **host/OS/glue layer only** (packages, users, firewall, DNS, Docker *engine*
config, system cron, systemd units, Tunnel 1, the backup watchdog). **Coolify owns the apps —
never manage application containers here.**

## Layout & status

- [`README.md`](README.md) — non-engineer operating manual + repo layout.
- [`docs/ANSIBLE-IMPLEMENTATION-PLAN.md`](docs/ANSIBLE-IMPLEMENTATION-PLAN.md) — the full brief; every server landmine (§3) and the phased plan with gates (§9).
- [`docs/STATUS.md`](docs/STATUS.md) — where the project is and what's next.
- `roles/` — one small, single-purpose, idempotent role per host concern. Phase 1 = non-disruptive; Phase 2 = risky (gated behind `enable_phase2`).

## Working conventions

- `ansible.builtin` modules first; keep every task idempotent and safe to re-run.
- Risky roles (`firewall`, `docker`, `cloudflared_coolify`) must be proven on the scratch host
  before prod, and follow the safety rules in plan §4a. Don't loosen those guards.
- Secrets never land in git — they come from 1Password at apply time.
- Local runs from WSL on `/mnt/c` need `export ANSIBLE_CONFIG=$PWD/ansible.cfg` (the drive is
  world-writable so Ansible otherwise ignores `ansible.cfg`).

## Git workflow for this repo

Work on `main`, no feature branches. Commits use the owner's GitHub noreply identity (email
privacy is enabled on the account).
