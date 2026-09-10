# Phase 4 task-gate rollout evidence

Issue `popcre/ai-devops#335` adds repository-local infrastructure routing and executable refusal evidence. Every repository path remains infrastructure-classed. This change performs no Ansible apply, host write, secret operation, service restart, or production action.

- `bash tests/test-task-gates.sh`: 18 passed / 0 failed. It proves repository-wide infrastructure classification, failed bypasses for shipping, infrastructure mutation, and production, explicit mutation refusal, declared shipping flow, and byte-exact rollback restoration.
- The new pull-request workflow repeats that proof using public repository `popcre/ai-devops` pinned at commit `4d83f9a5dc400f87408663eddac872b9074c18ed`; its public visibility and commit were verified before review.
- Existing `check.yml` remains independent and provides the read-only lint, syntax, toolkit-test, and host check-mode proof.
- Local Windows cannot run `ansible-lint` or `ansible-playbook`, and the existing toolkit shell test stops because Git Bash cannot resolve its numeric group ID. The Linux PR workflow is therefore the required proof for those checks.

## Release boundary

This repository's supported delivery remains main-only. `ENABLE_AUTO_APPLY=true`, and any non-documentation push to `main` runs a real serialized Phase 1 apply. This rollout's source is being reviewed through a temporary pull request, but it does not change that delivery rule or authorize the production action; the pull request must remain unmerged until an exact apply is explicitly authorized and the unconditional refusal is changed through a separate reviewed policy commit.
