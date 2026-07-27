# Developer-computer desired state

`playbooks/dev-computers.yml` is the single Ansible entrypoint for Albert's
Windows and Ubuntu coding computers. It installs/updates declared packages,
keeps SSH reachable only through Tailscale, updates `u2giants/ai-devops`, installs
Claude/Codex skills and managed instructions, optionally resolves secrets from
1Password at runtime, configures MCP launchers, and ends with one PASS report per
host.

## One-time bootstrap

Ansible needs a way in before it can manage a computer. On a new Windows
computer, the canonical `u2giants/ai-devops/bin/bootstrap-windows-dev.ps1`
breaks that cycle locally: it installs/detects Tailscale, configures Windows
OpenSSH with the `916-alien` public key and Tailscale-only port 22 rule, disables
WinRM, installs WSL Ubuntu, clones this repo, and installs Ansible plus its
collections. The user does not separately hand-configure these prerequisites.

Ubuntu targets still need Python 3, OpenSSH, Tailscale, the 1Password CLI
(`op`), and the public key before a remote Ansible connection can exist. The
role fails loudly if `tailscale` or `op` is missing rather than importing
production-only vendor repositories. Ansible runs from Ubuntu/WSL, never native
Windows.

This reduces touchpoints but cannot safely bypass GitHub private-repo
authorization, Tailscale enrollment, scoped 1Password authorization, or a
Windows reboot when WSL/servicing requires it.

Add each machine to `inventory/hosts.ini` using only its `100.x` Tailscale IP.
Commented examples intentionally prevent accidental application.

For 4837, preserve the Windows domain identity and control-node key path:

```ini
4837 ansible_host=100.123.87.44 ansible_user='IML\ahazan2' ansible_ssh_private_key_file=~/.ssh/916-alien
```

The private key path is on the Ubuntu/WSL Ansible control node, not on 4837.
Keep it mode `0600` and never commit it.

## Package and configuration ownership

Windows uses three WinGet packages (Git, PowerShell, and `op`) only to bootstrap
the repository. After cloning, the canonical package owner is
`ai-devops/.config/configuration.winget`, applied through the canonical
`ai-devops/bin/bootstrap-windows-dev.ps1` entrypoint. The
role's longer package list is a compatibility fallback only when that file does
not exist. `setup-machine.ps1` may verify Git, `op`, Node/npm, and cloudflared
because it directly depends on them, but the WinGet Configuration owns their
installation once present. The same bootstrap internally reconciles the three
non-WinGet exceptions—Vercel and Trigger.dev through npm, and Supabase CLI
through Scoop—so Ansible still invokes one canonical package entrypoint.

Ubuntu installs only packages available from repositories already configured on
that workstation. It does not apply the production Hetz `apt_repos` role: those
source/key files were captured from Hetz and are not proven portable across
developer-computer Ubuntu releases. Tailscale and `op` are explicit bootstrap
prerequisites.

The AI DevOps installers—not these Ansible roles—own Claude/Codex skill copies,
global instruction files, the scoped service-account token file, MCP references
and launchers, managed shell includes, and restoration of the `916-alien` key
from 1Password. Ansible owns orchestration, transport safety, and verification.

On Windows, the role runs `setup-machine.ps1` explicitly under PowerShell 7,
disables the obsolete WinRM service, and removes the old custom WinRM firewall
rule. OpenSSH over Tailscale is the sole remote-management path managed here.

## Validate without contacting a computer

As of 2026-07-17, YAML parsing and repository structural checks passed on 4837,
but 4837 did not yet provide the new WSL Ansible controller for native
`ansible-lint`/syntax execution. The following commands and live role behavior
remain required gates, not already-completed evidence.

```bash
ansible-galaxy collection install -r requirements.yml
ansible-lint
ansible-playbook playbooks/dev-computers.yml --syntax-check
ansible-playbook playbooks/test-dev-computers.yml
```

## Apply

Package/SSH/repo/skills reconciliation, without secrets:

```bash
ansible-playbook playbooks/dev-computers.yml --limit 4837
```

For the secret-backed step, authenticate the controller with the scoped
`vibe_coding` service account and explicitly opt in. Values are passed only in
process memory, are hidden by `no_log`, and are never committed:

```bash
export OP_SERVICE_ACCOUNT_TOKEN='(load securely; never paste into a prompt)'
op whoami
ansible-playbook playbooks/dev-computers.yml --limit 4837 -e dev_apply_secrets=true
```

The underlying AI DevOps setup intentionally stores the scoped service-account
token in the target user's locked-down config file so MCPs can start after
Ansible exits. SSH private keys and MCP bearer tokens are fetched from
1Password at runtime. The committed files contain only public keys and `op://`
references.

## Safety

- Never add LAN/public addresses to these inventory groups.
- Never put private keys or token values in inventory or `--extra-vars` files.
- Run `--check --diff` first, except WinGet/capability commands whose check-mode
  behavior is limited; use a disposable Windows VM for first-time role proof.
- A dirty AI DevOps checkout makes the fast-forward pull fail loudly instead of
  overwriting local work.

## Required rollout proof

Do not enable a real inventory host until all of these pass:

1. Run the ai-devops bootstrap on a disposable clean Windows 11 machine,
   including any required reboot/rerun.
2. Confirm key-only SSH over Tailscale, disabled WinRM, WSL Ansible, packages,
   skills, managed configuration, and MCP verification.
3. Rerun the bootstrap unchanged and confirm no unintended changes.
4. Run collection install, lint, syntax checks, and the static test playbook.
5. Apply `dev_windows` and `dev_ubuntu` to disposable targets twice. The second
   apply must report zero unintended changes and both final reports must PASS.
6. Only then uncomment a real Tailscale inventory address, run `--check --diff`,
   review the output, and explicitly authorize the real apply.

Windows package/capability tasks do not all model check mode perfectly. A clean
snapshot and second real run are the acceptance evidence; `--check` alone is
not sufficient.
