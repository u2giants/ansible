# Role: `packages`  — [non-disruptive · phase1]

Installs the **full set of manually-installed apt packages** so a rebuilt box has the exact same
package footprint as `hetz` — every CLI and tool the owner relies on, not just a curated few.
Recovery mission gaps **R1 + R6** ([`docs/RECOVERY-GAP-PLAN.md`](../../docs/RECOVERY-GAP-PLAN.md)).

## What it does
Reads `files/apt-manual.txt` (202 packages, captured verbatim by `bin/discover-software.sh`) and
ensures every one is present. Includes the key CLIs (`gcloud`, `az`, `gh`, `op`, Node, `psql`,
`restic`, `rg`, Tailscale, `cloudflared`, Chrome, Docker) plus everything else manually installed
(vim, tmux, build-essential, …). Requires `apt_repos` to have configured the vendor repos first.

## Keeping it current
When you intentionally add/remove a package, regenerate the list and the baseline:
```bash
ssh vps 'sudo bash -s' < bin/discover-software.sh | grep '^APT ' | sed 's/^APT  //' \
  | sort -u > roles/packages/files/apt-manual.txt
ssh vps 'sudo bash -s' < bin/discover-software.sh > docs/baseline-software.txt
```
The **software-drift** CI check (in `drift.yml`) flags anything installed on the box that isn't in
the baseline — i.e. software added outside Ansible.

## Boundaries / notes
- Non-apt tools (`go`, `supabase`, `codex`, npm CLIs) → `dev_tools` role.
- Additive + idempotent: on the live box all packages are present → 0 changes.
- **Authenticating** the CLIs after a rebuild stays a manual step, by design.
