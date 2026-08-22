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
| `enable_ai_devops_toolkit_deploy` | `false` | default-off maintenance gate; the exact manual toolkit dispatch opens it for one run |
| `firewall_lock_ipv6` | `true` | also lock down IPv6 port 22 (closes the live v6 gap) |
| `ssh_trusted_root_password` | `true` | allow root password login from trusted sources (Tailscale) — no-key break-glass |
| `docker_auto_restart` | `false` | MUST stay false — Ansible never restarts Docker |
| `ENABLE_AUTO_APPLY` | `true` | GitHub repo variable; enables real serialized apply-on-push in `apply.yml` |

## Key non-secret variables (`group_vars/all.yml`)

| Variable | Current value | Notes |
|---|---|---|
| `host_timezone` | `America/New_York` | confirmed live 2026-06-23 |
| `managed_user` | `ai` | passwordless sudo user |
| `ai_devops_toolkit_version` | `dde60a90a6acbf60507c6943932894d644826a4c` | exact reviewed toolkit release |
| `ai_devops_toolkit_backup_path` | `/worksp/ai-devops-pre-rewrite-20260822` | fixed recoverable predecessor checkout |
| `dns_fallback_servers` | `1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4` | resolved FallbackDNS |
| `docker_ce_version` | `5:29.6.0-1~ubuntu.24.04~noble` | pinned/held |
| `users_authorized_keys` | 916-alien public key | installed for `ai`; PUBLIC keys only (never strips keys) |
| `cron_glue_entries` | tailscale keepalive (root, */4), sync-infra-docs (ai, */15) | hiclaw keepers intentionally NOT adopted |
| `firewall_ssh_trusted_v4` | `100.64.0.0/10`, `127.0.0.1/32`, `10.0.1.0/24` | sources allowed to reach port 22 (else dropped) |
| `firewall_ssh_public_ports` | `[1904]` | SSH ports left open to the public (ai only, via ssh_hardening) |

### AI DevOps toolkit release evidence

The `dde60a90a6acbf60507c6943932894d644826a4c` pin is the reviewed canonical
AI DevOps remediation release for every supported platform, including the
production Linux checkout on `hetz`. It repairs the production-discovered
privilege boundary for root-owned configuration artifacts and the Windows
Git-Bash-to-PowerShell protected-path boundary. The first cutover attempt safely
stopped at candidate `768186c05abc1f85848210f163e7ec9609fc36d6`: the new
checkout was clean, the original backup was intact, and no completion marker was
written. The one-time in-place recovery from that candidate completed on
2026-08-22, and the temporary upgrade allowlist is now empty. The candidate is
not a history-rewrite predecessor and can no longer be selected as an installed
source revision.

Claude Opus 5 reviewed exact release `dde60a90a6acbf60507c6943932894d644826a4c`
read-only and returned `APPROVE` in provider session
`0c978767-de80-4e87-a8a8-8b43107e321f` on 2026-08-22. The hosted Linux and
Windows jobs passed, the governed recovery dispatch installed the release, and
a second exact tagged run completed successfully without changing the server.

Before the first toolkit dispatch, a read-only check on 2026-08-22 confirmed
`/worksp/ai-devops` was clean at
`2daa757268fa825407ec2ae7a62e24da29b4e652`, with no rewrite backup or
completion marker. That is historical pre-dispatch evidence; the later partial
cutover state is recorded above. Candidate
`a9b38c232962ecb936d88283c5c484ab8aa77f99` was pinned temporarily but was
never dispatched to `hetz`, so it is deliberately not an approved installed
predecessor.

## Secrets (1Password vault `vibe_coding`)

Never committed; injected at apply time via `1password/load-secrets-action` (CI) or the `op`
CLI (already installed on the box). Values are **not** recorded here — only in 1Password.

| Secret (1Password item) | Purpose | Consumed by | Status |
|---|---|---|---|
| `ci-deploy-ssh` (private key) | CI → host SSH | CI runner | active |
| `cf-tunnel-hetz` | Cloudflare Tunnel 1 token | `cloudflared_coolify` role | in 1Password (per plan); not yet wired by Ansible |
| `github-pat` | git/GitHub | git, MCP | migrated (per plan) |
| `restic-hetzner`, `do-spaces`, `cf-dns-token`, `ghcr-pat`, `oauth2-proxy`, app secrets | backups, certs, image pulls, app | various | **Phase 3, not yet migrated** |

Full migration table and order: `ANSIBLE-IMPLEMENTATION-PLAN.md` §5.2.

## GitHub secrets/variables for CI

| Name | Type | Purpose |
|---|---|---|
| `OP_SERVICE_ACCOUNT_TOKEN` | secret | 1Password access in CI (the only secret stored in GitHub) |
| `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET` | secret | Tailscale `tag:ci` ephemeral node |
| `ENABLE_AUTO_APPLY` | variable | set to `true`; enables apply-on-push |

Verify what exists: `gh secret list -R u2giants/ansible` and `gh variable list -R u2giants/ansible`.
Verified active on 2026-08-22: all three secrets are configured and
`ENABLE_AUTO_APPLY=true`. Re-check names and the non-secret variable value with the commands
above; secret values are never printed.
