# Role: `ai_devops_toolkit` — explicitly gated maintenance

Installs the exact reviewed `u2giants/ai-devops` release on the governed Hetzner
host. It runs as the `ai` user, preserves machine-local configuration under
`/etc/ai-devops`, refreshes shared Claude/Codex skills and instructions, and
finishes with `ai-devops doctor`.

The pinned toolkit's `install.sh` explicitly requires the normal user and uses
that user's passwordless `sudo` only for `/etc`, `/var/log`, and
`/usr/local/bin`; this keeps per-user skills out of `/root`. Its usage contract
supports `--skip-secrets`, and the pinned `ai-install-skills` contract supports
`--adopt-globals`.

The 2026-08-22 public-history rewrite requires a one-time recoverable cutover.
The role accepts only the declared predecessor commit, requires a clean
checkout, moves the complete old checkout to the fixed backup path, and then
clones the pinned release. It refuses unknown revisions, dirty worktrees, or an
existing backup rather than overwriting evidence.

Installation completion is separate from Git revision. The role writes an
owner-only marker only after `install.sh --skip-secrets`,
`ai-install-skills --adopt-globals`, and `ai-devops doctor` all succeed. If any
step fails after cloning, the marker remains absent and the next serialized
apply retries the installation instead of leaving a false-success checkout. A
separate, explicit in-place-upgrade allowlist handles a reviewed successor after
such a partial cutover without moving or replacing the original history backup.

This role is deliberately absent from routine Phase 1. It runs only when the
operator selects `--tags ai_devops_toolkit` and
`enable_ai_devops_toolkit_deploy=true`. The source default is `false`; only the
exact manual `apply.yml` dispatch with `tags=ai_devops_toolkit` opens it for one
run. The role manages only the toolkit checkout and its documented installer.
It does not manage Coolify, application containers, application data, or
secrets.

`/worksp` is a shared workspace parent verified live as owned by `ai`. The role
asserts that owner but never changes the parent, so it cannot take ownership of
sibling application checkouts such as `/worksp/hiclaw`.

## Verification

```bash
bash tests/test-ai-devops-toolkit.sh
ansible-playbook playbooks/site.yml -l hetzner \
  --tags ai_devops_toolkit --check --diff \
  -e enable_ai_devops_toolkit_deploy=true
```

After apply, the checkout must equal `ai_devops_toolkit_version`, the backup
must contain the predecessor commit, `ai-devops doctor` must pass, and a second
tagged run must report zero changes. Before writing its completion marker, the
role also proves the installer did not recreate the retired `ai-memory-sync`
schedule.

The pinned release, history predecessor, and any one-time partial-release
upgrade predecessor are verified public commits in `u2giants/ai-devops`. Any
other revision fails closed so an unexpected or concurrent checkout is never
overwritten silently.
