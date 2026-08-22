# CLAUDE.md

**Read [`AGENTS.md`](AGENTS.md) first** — it is the canonical operating guide for this repo
(scope, rules, documentation map, structure, incidents, pending work). This file holds only
Claude-Code-specific notes that do not belong in `AGENTS.md`.

## Claude-specific

- **Ignore files:** `.claudeignore` controls what Claude Code skips. Keep it aligned with the
  "What to ignore" section of `AGENTS.md`.
- **SSH / applies:** pushes to `main` run the serialized Phase 1 production apply (see
  `docs/deployment.md`). Direct SSH is exceptional and is used for read-only verification or
  recovery, never as a substitute for an Ansible source change.
- **Allowed tooling:** `gh` for GitHub, `ansible*` via WSL, `ssh vps` for the host. The owner's
  1Password (`op`) holds secrets — never print or commit secret values.

## Commit style

- Work on `main`, no feature branches (this repo and the owner's workflow are main-only).
- Commits use the owner's GitHub **noreply** identity (`55610577+u2giants@users.noreply.github.com`)
  because account email privacy is enabled — pushes with the plain email are rejected.
- Keep docs updated in the same commit as the code/config they describe.
