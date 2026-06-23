# Deployment

How changes reach the live host. This describes the **real, current** process, which is part
manual today (Phase 4 CI not yet enabled). For variables/secrets see
[`configuration.md`](configuration.md).

## What "deploy" means here

This project deploys **configuration to a host**, not images or packages. "Deploying" = running
`ansible-playbook` against `hetz` so the live OS matches the repo.

## Pipeline (GitHub Actions)

| Workflow | Trigger | What it does | Applies changes? |
|---|---|---|---|
| `.github/workflows/check.yml` | pull request to `main` | `ansible-lint` + `ansible-playbook --check --diff` (phase1) against `hetz`; posts the diff as a PR comment | no (read-only) |
| `.github/workflows/apply.yml` | push to `main`; manual dispatch | serialized by `concurrency: apply-hetzner`; runs the real apply **only if repo variable `ENABLE_AUTO_APPLY == 'true'`**, otherwise `--check` only | gated |
| `.github/workflows/drift.yml` | daily cron 03:00 UTC; manual | `--check --diff` (phase1); fails/alerts on drift | no (never applies) |

All three reach the host over **Tailscale** using the `tailscale/github-action` with an
**ephemeral `tag:ci`** node, and pull secrets via `1password/load-secrets-action`.

## Current reality (important)

- **CI auto-apply is NOT enabled.** `ENABLE_AUTO_APPLY` is unset, and the Tailscale/1Password
  GitHub secrets do not exist yet (Phase 4). So `apply.yml` is effectively check-only.
- **Applies are currently manual.** The owner / an AI session runs `ansible-playbook` from WSL
  against `hetz`. Phase 1 was applied this way on 2026-06-23 (idempotency gate passed). Phase 2
  is not applied.

Manual apply command (Phase 1):

```bash
ANSIBLE_CONFIG=/mnt/c/repos/ansible/ansible/ansible.cfg \
ansible-playbook playbooks/site.yml -l hetzner --tags phase1 \
  --user root --private-key ~/.ssh/916-alien -e ansible_user=root
```

## SSH

- **Path:** `ssh vps` → root@`100.66.37.58` over Tailscale, key `916-alien`. Public SSH (port 22
  from the internet) is firewalled off — Tailscale only.
- **Is SSH routine?** **Yes, currently** — applies are run manually over SSH during this phase.
  The target model (Phase 4) moves applies into CI, after which direct SSH should become
  **exceptional** (debugging/maintenance), not the deploy path. We are not there yet.

## Rollback

- **Config rollback:** revert the offending commit and re-apply the playbook; the host converges
  back. There is no image/version artifact to roll back.
- **Firewall:** the `firewall` role arms a systemd auto-revert timer (default 60s) that restores
  the last-known-good ruleset if a change makes the host unreachable.
- **Docker:** `daemon.json` changes do not auto-restart Docker; reverting the file + a deliberate
  restart in a maintenance window is the rollback.

## First-boot bootstrap (rebuild path)

`files/cloud-init/user-data.yaml.j2` (Hetzner Cloud `user-data`) creates the `ai` user + key,
installs Python and Tailscale (`tag:ci`, `--ssh`) so a fresh box is reachable by the pipeline
with zero manual steps. Render it injecting secrets at provision time; never commit the rendered
file. Caveat: Hetzner **dedicated/Robot** servers use `installimage` instead (plan §5.4).

## Where runtime env lives

The host's runtime config is what the roles manage (`/etc/...`, systemd units, `daemon.json`).
Application runtime env is Coolify's, not this repo's. CI secrets live in 1Password + (planned)
GitHub Actions secrets.
