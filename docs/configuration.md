# Configuration

Variables, config files, gates, and secrets. No secret values appear here. For the apply flow
see [`deployment.md`](deployment.md).

## Config files

| File | Purpose |
|---|---|
| `ansible.cfg` | inventory path, `roles_path`, no host-key prompt, passwordless sudo, YAML output |
| `inventory/hosts.ini` | hosts and connection vars (`ansible_host`, `ansible_user`) |
| `inventory/group_vars/all.yml` | all non-secret tunables (see below) |
| `requirements.yml` | collections (`ansible.posix`) |
| `.ansible-lint` | lint profile + the two accepted `command-instead-of-module` warnings |
| `roles/<role>/defaults/main.yml` | per-role defaults, overridable in `group_vars` |

## Phase / safety gates

| Variable | Default | Effect |
|---|---|---|
| `enable_phase1` | `true` | runs the non-disruptive roles |
| `enable_phase2` | `false` | gates the risky roles (firewall/docker/cron_glue/cloudflared); a pre-task asserts opt-in |
| `firewall_lock_ipv6` | `true` | also lock down IPv6 port 22 (closes the live v6 gap) |
| `ssh_trusted_root_password` | `true` | allow root password login from trusted sources (Tailscale) — no-key break-glass |
| `docker_auto_restart` | `false` | MUST stay false — Ansible never restarts Docker |
| `ENABLE_AUTO_APPLY` | unset | GitHub repo variable; gates real apply-on-merge in `apply.yml` |

## Key non-secret variables (`group_vars/all.yml`)

| Variable | Current value | Notes |
|---|---|---|
| `host_timezone` | `America/New_York` | confirmed live 2026-06-23 |
| `managed_user` | `ai` | passwordless sudo user |
| `dns_fallback_servers` | `1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4` | resolved FallbackDNS |
| `docker_ce_version` | `5:29.6.0-1~ubuntu.24.04~noble` | pinned/held |
| `users_authorized_keys` | 916-alien public key | installed for `ai`; PUBLIC keys only (never strips keys) |
| `cron_glue_entries` | tailscale keepalive (root, */4), sync-infra-docs (ai, */15) | hiclaw keepers intentionally NOT adopted |
| `firewall_ssh_trusted_v4` | `100.64.0.0/10`, `127.0.0.1/32`, `10.0.1.0/24` | sources allowed to reach port 22 (else dropped) |
| `firewall_ssh_public_ports` | `[1904]` | SSH ports left open to the public (ai only, via ssh_hardening) |

## Secrets (1Password vault `vibe_coding`)

Never committed; injected at apply time via `1password/load-secrets-action` (CI) or the `op`
CLI (already installed on the box). Values are **not** recorded here — only in 1Password.

| Secret (1Password item) | Purpose | Consumed by | Status |
|---|---|---|---|
| `ci-deploy-ssh` (private key) | CI → host SSH | CI runner (Phase 4) | planned |
| `cf-tunnel-hetz` | Cloudflare Tunnel 1 token | `cloudflared_coolify` role | in 1Password (per plan); not yet wired by Ansible |
| `github-pat` | git/GitHub | git, MCP | migrated (per plan) |
| `restic-hetzner`, `do-spaces`, `cf-dns-token`, `ghcr-pat`, `oauth2-proxy`, app secrets | backups, certs, image pulls, app | various | **Phase 3, not yet migrated** |

Full migration table and order: `ANSIBLE-IMPLEMENTATION-PLAN.md` §5.2.

## GitHub secrets/variables for CI (Phase 4 — not yet created)

| Name | Type | Purpose |
|---|---|---|
| `OP_SERVICE_ACCOUNT_TOKEN` | secret | 1Password access in CI (the only secret stored in GitHub) |
| `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET` | secret | Tailscale `tag:ci` ephemeral node |
| `ENABLE_AUTO_APPLY` | variable | set to `true` to enable apply-on-merge |

Verify what exists: `gh secret list -R u2giants/ansible` and `gh variable list -R u2giants/ansible`.
**Currently unknown/none** — these are created in Phase 4.
