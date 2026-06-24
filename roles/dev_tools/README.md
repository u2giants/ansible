# Role: `dev_tools`  — [non-disruptive · phase1]

Installs the **non-apt host tools** (those not available from an apt repo), version-pinned to
what's live, so a rebuild reproduces them. Recovery gap **R2**
([`docs/RECOVERY-GAP-PLAN.md`](../../docs/RECOVERY-GAP-PLAN.md)).

| Tool | How | Version (default) |
|---|---|---|
| `go` / `gofmt` | tarball from go.dev → `/usr/local/go`, symlinked into `/usr/local/bin` | `go_version` 1.26.4 |
| `supabase` | official `.deb` from GitHub releases | `supabase_version` 2.98.2 |
| `claude-code`, `gemini-cli`, `corepack`, `npm-check-updates` | global npm (`community.general.npm`) | pinned in `dev_tools_npm` |
| `codex` | `@openai/codex` global npm (standalone → `/opt/codex`) | `codex_version` 0.141.0 |
| `cloudflared` symlink | `/usr/local/bin/cloudflared` → `/usr/bin/cloudflared` (binary is apt, installed by `packages`) | — |

## Safe / idempotent
Every install is guarded by a version check (or an idempotent module), so applying to the live
box is a **no-op**. **Bump the version vars** when you upgrade a tool, so a rebuild matches.

## Notes
- The live box also has a second, older `gemini` at `/usr/local/bin/gemini` (0.35.2); this role
  installs only the npm `@google/gemini-cli` (0.44.1) — the newer one — and does not reproduce the
  duplicate.
- **Authenticating** these tools after a rebuild (`gcloud auth`, `supabase login`, `codex` login,
  etc.) stays a manual step, by design.
