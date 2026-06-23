# AI Agent Operating Rules — this server is managed by Ansible

**Read this before changing anything on the `hetz` Hetzner server.** It applies to every AI
coding agent (Claude Code, Codex, and any other) and every human. It is short on purpose.

---

## The one rule

> **To change the server, change this repo.**
> Open a pull request to `u2giants/ansible`, let CI show the `--check` diff, merge it.
> CI applies the change once, serialized.
>
> **Never** SSH into the box and `apt install`, `crontab -e`, edit `/etc`, change firewall
> rules, or hand-edit a systemd unit. Manual changes are **undocumented drift** and will be
> detected by daily drift-detection and **silently reverted** by the next apply.

If you are an AI agent and you find yourself about to run a command that changes host state
over SSH — **stop**. That work belongs in a pull request to this repo instead.

---

## Why (the 30-second version)

The owner runs ~7 concurrent AI sessions across ~5 apps against shared infrastructure. If each
session hot-fixes the live box, the server becomes an un-rebuildable "pet" that nobody
understands — which is exactly the problem this repo exists to end. The single serialized
apply pipeline is what stops those sessions from colliding. Honor it.

---

## Scope — what goes where

| If your change is to… | Then… |
|---|---|
| **The host / OS / glue** — packages, users, firewall, DNS, Docker *engine* config, system cron, systemd units, the backup watchdog, Tunnel 1 | **A PR to this repo** (a role under `roles/`) |
| **An application** — any of the ~20 containers (Pop apps, HiClaw, MCPs, oauth2-proxy, etc.) | **The app's own repo → deploys via Coolify.** NOT here. |

**Ansible owns the host. Coolify owns the apps.** Do not manage application containers,
Coolify-owned resources, or Tunnels 2 & 3 with Ansible — it causes reconcile loops.

---

## Hard "do NOT" list (these have caused outages — see `docs/ANSIBLE-IMPLEMENTATION-PLAN.md` §3)

- Do **not** manage app containers / Coolify resources with Ansible.
- Do **not** add a `dns` key to `/etc/docker/daemon.json` (breaks every container).
- Do **not** auto-restart Docker (hits Coolify + ~20 containers; causes docker.sock staleness).
- Do **not** apply firewall changes without the Tailscale lifeline + auto-revert (locks out SSH).
- Do **not** touch Cloudflare Tunnels 2 & 3 (Coolify-managed).
- Do **not** set `HTTP_PROXY`/`HTTPS_PROXY`/`ALL_PROXY`, or enable `socks5-home-tunnel.service`.
- Do **not** commit secrets — they live in 1Password (vault `vibe_coding`), injected at apply time.

---

## How to make a host change (the supported path)

1. Edit or add the relevant **role** under `roles/` in this repo.
2. Open a pull request. CI runs `ansible-lint` + `ansible-playbook --check --diff` and posts the
   exact diff of what would change on the server.
3. A human reviews the diff and merges. CI applies it, serialized.

New to the layout? Start with [`README.md`](README.md). The full rationale and every server
landmine is in [`docs/ANSIBLE-IMPLEMENTATION-PLAN.md`](docs/ANSIBLE-IMPLEMENTATION-PLAN.md).
