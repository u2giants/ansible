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
| `ai_devops_toolkit_version` | `3c34bb0785db0a9f1ab548885af279391b196871` | exact reviewed toolkit release |
| `ai_devops_toolkit_backup_path` | `/worksp/ai-devops-pre-rewrite-20260822` | fixed recoverable predecessor checkout |
| `dns_fallback_servers` | `1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4` | resolved FallbackDNS |
| `docker_ce_version` | `5:29.6.0-1~ubuntu.24.04~noble` | pinned/held |
| `users_authorized_keys` | 916-alien public key | installed for `ai`; PUBLIC keys only (never strips keys) |
| `cron_glue_entries` | tailscale keepalive (root, */4), sync-infra-docs (ai, */15) | hiclaw keepers intentionally NOT adopted |
| `firewall_ssh_trusted_v4` | `100.64.0.0/10`, `127.0.0.1/32`, `10.0.1.0/24` | sources allowed to reach port 22 (else dropped) |
| `firewall_ssh_public_ports` | `[1904]` | SSH ports left open to the public (ai only, via ssh_hardening) |

### AI DevOps toolkit release evidence

The `3c34bb0785db0a9f1ab548885af279391b196871` pin is the reviewed canonical
AI DevOps remediation release for every supported platform. It retains the
production-discovered privilege-boundary and seven-stage workflow repairs,
prevents Windows CRLF memory indexes from creating duplicate union commits and
merges existing duplicate-storm indexes in linear time,
accepts only proven first-party Haiku helper identities alongside the required
canonical Claude Opus 5 reviewer model, and isolates paid Grok turns from
ambient user plugins.
The first cutover attempt safely
stopped at candidate `768186c05abc1f85848210f163e7ec9609fc36d6`: the new
checkout was clean, the original backup was intact, and no completion marker was
written. The one-time in-place recovery from that candidate completed on
2026-08-22. The candidate is
not a history-rewrite predecessor and can no longer be selected as an installed
source revision.

Claude Opus 5 reviewed exact successor `d24884fd073081bb2eb43ce6880ba8714fdd6e17`
read-only and returned `APPROVE` in provider session
`97858f87-dc0e-418f-b490-780f8054c6b0` on 2026-08-22. The temporary upgrade
allowlist permitted only the installed reviewed predecessor
`dde60a90a6acbf60507c6943932894d644826a4c`. Governed dispatch `32583326484`
installed the successor, live doctor checks passed, the original backup remained
at `2daa757268fa825407ec2ae7a62e24da29b4e652`, and exact tagged rerun
`32583852811` completed successfully. That rollout's one-time allowlist was
then emptied.

Claude Opus 5 reviewed exact release `82697a8f07fe50338606c4f4b11d3bbf5e90e1cc`
read-only and returned `APPROVE` in provider session
`5cc80ce8-8ba2-4331-a57a-3c5a4f0c1c9a` on 2026-08-23. Fresh read-only SSH
evidence at `2026-08-23T06:23:51Z` showed `/worksp/ai-devops` was clean on
`main` at predecessor `d80f468fbf8e7f98c73f9798e0e1de59e2759e01`, the install
manifest recorded that same source SHA, and no completion marker existed for it.
The last governed rollout recorded before this investigation ended at
`d24884fd073081bb2eb43ce6880ba8714fdd6e17`;
no governed dispatch establishing the later transition to `d80f468` has been
found, so that drift remains an explicit audit item rather than being attributed
to this role. The exact live revision was allowlisted only for the governed
in-place upgrade; no history cutover or backup replacement was permitted.
Gated dispatch `32624619860` installed the reviewed release, the live checkout
and install manifest both matched `82697a8`, the completion marker was present,
and every required doctor check passed. Exact tagged rerun `32625017742`
reported `changed=0`, `unreachable=0`, and `failed=0`. The temporary upgrade
allowlist is now empty. The completed 2026-08-22 history-cutover predecessor
allowlist is also empty, so no historical revision retains standing deployment
authority.

Claude Opus 5 reviewed exact final release
`3c34bb0785db0a9f1ab548885af279391b196871` read-only and returned `APPROVE` in
provider session `e6fd46aa-338e-48b9-bbe2-48034a3239bf` on 2026-08-23. This
release makes CRLF memory-index union linear and fail-closed after the governed
4837 rollout exposed quadratic work on a 19.9 MB incident index. The required
read-only production preflight found the clean live checkout at
`3fdc87c4502758545373da540b84c77827b49fb0`, a direct ancestor of the fully
gated target, rather than the last governed release. Only that exact observed
revision was temporarily allowlisted for the in-place promotion.
At `2026-08-23T12:16:51Z`, `/worksp/ai-devops` was clean at that SHA, the
owner-only manifest recorded `source_sha` at the same SHA, and its versioned
completion marker was absent. In the canonical public checkout,
`git merge-base --is-ancestor 3fdc87c... 3c34bb0...` returned zero and
`origin/main` contained `3fdc87c...`, proving the predecessor is published and
lies on the fully gated target's direct history. No governed dispatch explains
the transition, so it remains a separate open audit item rather than being
normalized by this promotion.

Governed dispatch `32639239500` installed the final release. The live checkout,
owner-only manifest, versioned completion marker, and `ai-devops doctor` all
passed at the exact target SHA. Tagged rerun `32639412554` reported `changed=0`,
`unreachable=0`, and `failed=0`; the temporary predecessor exception is now
empty, so the observed drift revision retains no standing deployment authority.

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
