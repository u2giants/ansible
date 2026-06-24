# Role: `packages`  — [non-disruptive · phase1]

Installs the host **CLIs / tooling** the owner's AI sessions and MCP servers depend on, from the
vendor repos configured by [`apt_repos`](../apt_repos/README.md). Recovery mission gap **R1**
([`docs/RECOVERY-GAP-PLAN.md`](../../docs/RECOVERY-GAP-PLAN.md)).

Installs (`tooling_packages`): `google-cloud-cli` (gcloud), `azure-cli` (az), `gh`, `1password-cli`
(op), `nodejs` (node/npm), `postgresql-client` (psql), `restic`, `ripgrep` (rg), `tailscale`,
`google-chrome-stable`.

## Boundaries
- **Docker engine** → the `docker` role (repo + pin).
- **Non-apt tools** (`go`, `supabase`, `codex`, the `claude-code`/`gemini-cli` npm CLIs,
  `cloudflared` binary) → the `dev_tools` role (gap R2).
- Requires `apt_repos` to have run first (the repos must exist).

## Safe
Additive + idempotent: already-installed packages = 0 changes. **Authenticating** these CLIs
(`gcloud auth`, `az login`, `gh auth`, `op signin`) stays a manual step after a rebuild, by design.
