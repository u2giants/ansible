# Disaster Recovery — the whole purpose of this Ansible project

> **This is the north star. Every decision in this repo serves this goal. Read it before
> arguing about scope.**

## The mission

The owner is **not a sysadmin or devops engineer** and does not — and should not have to —
remember or know anything about how this server is built. The entire reason this Ansible project
exists is **catastrophic-failure recovery with near-zero downtime and zero tribal knowledge.**

The success test is one sentence:

> The owner can open a fresh Claude session and say **"rebuild everything,"** and the entire
> `hetz` environment is reconstructed exactly as it was — from GitHub repos, app-data backups,
> 1Password, and this Ansible repo — with the owner only ever having to **log in / authenticate**
> to the services that get installed. Nothing depends on the owner knowing or recalling anything.

If a piece of software, config, service, or glue exists on the box and is **not** reproducible
from code/backups, that is a **bug in the recovery plan** — not an acceptable state.

## The five pillars of recovery

Everything that makes up the running environment must live in exactly one of these, and together
they must cover **100%** of it:

| Pillar | Owns | Recovery source |
|---|---|---|
| **1. Ansible** (this repo) | The **entire host**: OS, **every installed package and CLI/tool**, language runtimes, Docker engine, firewall, DNS, users, SSH, systemd units, cron, glue scripts, **and the Coolify install itself** | `u2giants/ansible` + CI pipeline |
| **2. Coolify** | Orchestration of the ~20 **application containers** | Installed by Ansible; redeploys apps from their GitHub repos |
| **3. GitHub** | All **application source code** | The app repos (Coolify pulls from them) |
| **4. backrest backups** | All **application data** (databases, volumes) **and Coolify's own state** (`coolify-db` + `/data/coolify`) | restic/S3 backups (3-2-1) |
| **5. 1Password** | All **secrets** | vault `vibe_coding` (+ the owner's personal vault) |

**The hard rule:** *every piece of software on the Hetzner box must be reproducible from Pillar 1
(Ansible, for the host) or Pillar 2+3 (Coolify+GitHub, for the apps).* Host tooling that only
exists because someone once ran an install command by hand is exactly the gap this project closes.

## The "rebuild everything" runbook (target end state)

A future session, told "rebuild everything," executes:

1. **Provision** a fresh Ubuntu box (Hetzner) — same size/region.
2. **Bootstrap** (cloud-init): create the `ai` user + keys, install Python + Tailscale so the box
   is reachable by the pipeline (§5.4).
3. **Run Ansible** (the host pillar): installs **all** apt repos + packages, all third-party CLIs
   (`gcloud`, `az`, `gh`, `op`, `supabase`, the AI CLIs, …), language runtimes, the Docker engine,
   firewall, DNS, SSH policy, systemd units, cron, glue scripts — **and installs Coolify.**
4. **Restore data** from backrest: Coolify's own state (so it knows the ~20 apps) and every app's
   database/volumes.
5. **Coolify redeploys** the apps from their GitHub repos, wired to the restored data + 1Password
   secrets.
6. **Authenticate** — the owner logs in to the CLIs/services that need it (`gcloud auth`, `az
   login`, `gh auth`, `op signin`, etc.). This is the *only* manual step, and it's expected.
7. **Verify** — diff the rebuilt box against the recovery definition; chase every difference to zero.

## What "done" means for this project

This project is **not** done when the host is partly managed. It is done when:
- **No software** runs on the box that isn't installed by Ansible (host) or Coolify (apps).
- A **rebuild-and-diff** against a throwaway box shows only expected differences.
- The owner needs to **know nothing** — only to authenticate when prompted.

See [`RECOVERY-GAP-PLAN.md`](RECOVERY-GAP-PLAN.md) for the concrete plan to get from today's state
to this end state, and [`AGENTS.md`](../AGENTS.md) for the operating rules.
