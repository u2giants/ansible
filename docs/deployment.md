# Deployment

How changes reach the live host. This describes the **real, current** automated process. For
variables/secrets see
[`configuration.md`](configuration.md).

## What "deploy" means here

This project deploys **configuration to a host**, not images or packages. "Deploying" = running
`ansible-playbook` against `hetz` so the live OS matches the repo.

## Pipeline (GitHub Actions)

| Workflow | Trigger | What it does | Applies changes? |
|---|---|---|---|
| `.github/workflows/check.yml` | pull request to `main`; manual dispatch | `ansible-lint` + `ansible-playbook --check --diff` (phase1) against `hetz`; posts the diff to the PR or the manual run summary | no (read-only) |
| `.github/workflows/apply.yml` | push to `main`; manual dispatch | serialized by `concurrency: apply-hetzner`; runs the real apply **only if repo variable `ENABLE_AUTO_APPLY == 'true'`**, otherwise `--check` only | gated |
| `.github/workflows/drift.yml` | daily cron 03:00 UTC; manual | `--check --diff` (phase1); fails/alerts on drift | no (never applies) |

All three reach the host over **Tailscale** using the `tailscale/github-action` with an
**ephemeral `tag:ci`** node, and pull secrets via `1password/load-secrets-action`.

The `ai_devops_toolkit` role is not part of routine Phase 1. Its recoverability
test gates the exact maintenance dispatch, and the role runs only through a manual `apply.yml` dispatch with
`tags=ai_devops_toolkit`; that exact workflow path opens the otherwise
default-off maintenance gate for one run.

## Current reality (important)

- **CI auto-apply is enabled.** `ENABLE_AUTO_APPLY=true`, and pushes to `main` run the serialized
  Phase 1 apply through the authenticated Tailscale/1Password path.
- **Routine applies are automated.** Direct SSH is for read-only verification and exceptional
  recovery only. Phase 2 remains gated and is not applied.

Emergency manual fallback command (Phase 1; connects as the managed `ai` user):

```bash
ANSIBLE_CONFIG=/mnt/c/repos/ansible/ansible/ansible.cfg \
ansible-playbook playbooks/site.yml -l hetzner --tags phase1 \
  --private-key ~/.ssh/916-alien
```

## SSH

- **Path:** `ssh vps` → root@`100.66.37.58` over Tailscale, key `916-alien`. Public SSH (port 22
  from the internet) is firewalled off — Tailscale only.
- **Is SSH routine?** **No.** The CI apply workflow is the deployment path. Direct SSH is
  exceptional and does not replace an Ansible source change.

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
