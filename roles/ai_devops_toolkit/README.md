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

The 2026-08-22 public-history rewrite used a one-time recoverable cutover. For
that cutover, the role accepted only the declared predecessor commit, required
a clean checkout, moved the complete old checkout to the fixed backup path,
and then cloned the pinned release. It refused unknown revisions, dirty
worktrees, or an existing backup rather than overwriting evidence.

Installation completion is separate from Git revision. The role writes an
owner-only marker only after `install.sh --skip-secrets`,
`ai-install-skills --adopt-globals`, and `ai-devops doctor` all succeed. If any
step fails after cloning, the marker remains absent and the next serialized
apply retries the installation instead of leaving a false-success checkout. A
separate, explicit in-place-upgrade allowlist can handle a reviewed successor
without moving or replacing the original history backup. For the 2026-08-23
`82697a8f07fe50338606c4f4b11d3bbf5e90e1cc` promotion, read-only SSH evidence
first proved the clean live predecessor and matching install manifest at
`d80f468fbf8e7f98c73f9798e0e1de59e2759e01`; the unexplained transition after
the last governed `d24884fd` rollout remains recorded separately in
`AGENTS.md`. Governed dispatch `32624619860` then ran the complete installer,
doctor, schedule check, and completion-marker path. Exact tagged rerun
`32625017742` reported `changed=0`, `unreachable=0`, and `failed=0`. The
one-release predecessor exception is now removed.

The subsequent final release
`3c34bb0785db0a9f1ab548885af279391b196871` replaces the quadratic memory-index
merge exposed while converging 4837. Governed dispatch `32639239500` installed
it from the clean live preflight revision
`3fdc87c4502758545373da540b84c77827b49fb0`; live verification passed and exact
tagged rerun `32639412554` reported zero changes or failures. The temporary
predecessor exception is removed.

Exact reviewed successor `3e252bcae2b1890a8ca0d00dc11dc0d210e91e0f`
contains the final Windows Muse installer invocation, deterministic
cross-platform interruption proof, a bounded Windows CI budget with measured
headroom, later fail-closed reviewer/topology repairs, and stable physical
review-snapshot identity across equivalent Windows path spellings. It also
normalizes dynamic reviewer quarantine to the shared warning status, isolates
Kimi's artifact-worker fixture, and makes Windows reviewer process-tree cleanup
native, bounded, and fail-closed. No predecessor is
allowlisted now. Governed dispatch `32674373667` established its completion
marker and exact tagged rerun `32674548896` was a zero-change success. The
preflight found the checkout already at that target through an unexplained
fast-forward, which remains recorded as a separate audit item in `AGENTS.md`.

Reviewed successor `8435f7938d9865158975c2a4dbd7e43a3c3bde97` replaces cross-product
machine/hub memory matching with one-time indexes while preserving duplicate,
CRLF, no-final-newline, and multi-checkout behavior. Its predecessor allowlist
remains empty. Hosted source gate `32676734390` passed Linux, focused Windows
reviewer safety, and the complete Windows matrix; a fresh live preflight must
still identify the exact predecessor before any deployment authority is opened.

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

After every apply, the checkout must equal `ai_devops_toolkit_version`,
`ai-devops doctor` must pass, and a second tagged run must report zero changes.
After a history cutover, the fixed backup must also contain the predecessor
commit. Before writing its completion marker, the role proves the installer did
not recreate the retired `ai-memory-sync` schedule.

Every pinned release and any explicitly temporary predecessor must be a
verified public commit in `u2giants/ai-devops`. Both one-time predecessor lists
are empty after a successful rollout; any unexpected or concurrent checkout
therefore fails closed and is never overwritten silently.
