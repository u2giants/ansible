# Runbook — "rebuild everything"

The exact procedure for a future session told **"rebuild everything"** after a catastrophic
failure. Realizes the mission in [`DISASTER-RECOVERY.md`](DISASTER-RECOVERY.md). The owner's only
manual job is **authenticating** the tools at the end.

> ⚠️ This runbook is **authored but not yet end-to-end proven** — that's gap **R7**
> ([`RECOVERY-GAP-PLAN.md`](RECOVERY-GAP-PLAN.md)): run it against a throwaway box and diff before
> trusting it for a real disaster. The Coolify install step especially.

## You need
- This repo, **1Password** access (vault `vibe_coding` + the owner's personal vault for backup
  secrets), the **backrest backups** (restic/S3), and access to **GitHub** (Coolify pulls app code).

## Steps

### 1. Provision
A fresh **Hetzner** box, **Ubuntu 24.04**, same size as the original (16 GB).

### 2. Bootstrap (make it reachable by Ansible)
Pass the cloud-init `user-data` (`files/cloud-init/user-data.yaml.j2`, rendered with the Tailscale
auth key + CI public key from 1Password). It creates the `ai` user + key, installs Python, and
joins Tailscale (`tag:ci`). After first boot the box is reachable; nothing else is manual.

### 3. Point the inventory at the new box
Set the new host's Tailscale IP in `inventory/hosts.ini` (`[hetzner]`).

### 4. Run Ansible — the whole host (phase1 + phase2)
From the CI pipeline (push) or directly, with secrets injected from 1Password:
```bash
export CLOUDFLARED_TUNNEL_TOKEN="$(op read op://vibe_coding/cf-tunnel-hetz/password)"
ansible-playbook playbooks/site.yml -l hetzner \
  -e enable_phase2=true \
  -e cloudflared_manage_token=true
```
This installs: the vendor apt repos + all 202 packages (`apt_repos`, `packages`), all non-apt
tools (`dev_tools`: Go, supabase, codex, npm CLIs), Docker engine (`docker`), the firewall,
DNS hardening, SSH policy, users, cron, the backup watchdog, **Coolify** (`coolify` installs it
since `/data/coolify` is absent), and Tunnel 1.

### 5. Restore data from backrest (Pillar 4)
Restore **Coolify's state** and the **app data** from the backrest/restic backups:
- `coolify-db` (Postgres) and `/data/coolify` (so Coolify knows the ~20 apps + their settings/env),
- each app's databases/volumes.
See the **backrest-wiz** repo for the restore procedure (out of this repo's scope).

### 6. Coolify redeploys the apps (Pillars 2+3)
With its state restored, Coolify redeploys the ~20 application containers from their GitHub repos,
wired to the restored data + 1Password secrets.

### 7. Authenticate (the ONLY manual step)
Reviewer API keys (Muse, StepFun, DeepSeek, GLM/OpenCode) are restored automatically: the apply
workflow loads the hetz `ai` 1Password service-account token
(`op://vibe_coding/yw6o7cwwqn5n6zqliddu5d3w4m/OP_SERVICE_ACCOUNT_TOKEN`) into
`~/.config/ai-devops/op-service-account` (0600, no_log) and runs `install.sh --require-secrets`.

Still log in by hand as `ai` — by design these are not stored:
- `claude` (Claude Code native, Anthropic sign-in) and `codex login` (OpenAI/ChatGPT)
- `gh auth login` (u2giants), `gcloud auth login`, `az login`, `supabase login`
- `kimi` / `grok` / `gemini` / `qwen` CLI sign-ins if those (frozen) reviewers are wanted
- `tailscale up`
Then run `/worksp/ai-devops/bin/ai-devops doctor` and one `ai-review` per rotation reviewer.

Also: the Headroom ZCode TLS front gets a **new self-signed CA** on rebuild (`roles/headroom_proxy`).
Copy `/etc/ai-zcode-headroom/tls/ca.crt` to each tailnet client that uses the ZCode Headroom lane and
re-trust it there.

### 8. Verify (rebuild-and-diff)
Diff the rebuilt box against the recovery definition: `bin/discover-software.sh` vs
`docs/baseline-software.txt`; enabled services; listening ports; Coolify app list. Chase every
difference to zero. The daily `drift.yml` then keeps it honest.

## Order dependencies
`apt_repos` → `packages`/`dev_tools`/`docker` (repos must exist first). Coolify needs Docker.
Data restore (5) must precede Coolify's redeploy (6). Auth (7) is last.
