# Development

How to set up, validate, and run this project locally. For operating rules see
[`AGENTS.md`](../AGENTS.md); for the apply/CI flow see [`deployment.md`](deployment.md).

## Prerequisites

Ansible's control node does **not** run on native Windows. On this project's Windows machine,
Ansible runs inside **WSL (Ubuntu)**. Install once:

```bash
sudo apt update && sudo apt install -y ansible-core ansible-lint
ansible-galaxy collection install -r requirements.yml   # ansible.posix
```

Versions confirmed working: `ansible-core 2.20`, `ansible-lint`. Native Python on Windows (via
`winget install Python.Python.3.12`) is only needed for general scripting, not for Ansible.

## The world-writable `/mnt/c` gotcha (important)

The repo lives at `/mnt/c/repos/ansible/ansible`. WSL mounts `C:` world-writable, so Ansible
**ignores `ansible.cfg`** there (security refusal) — which silently drops `roles_path` and the
inventory, causing "role not found" errors. Always export the config path explicitly:

```bash
export ANSIBLE_CONFIG=/mnt/c/repos/ansible/ansible/ansible.cfg
```

(Or, faster long-term: clone the repo into the WSL filesystem, e.g. `~/ansible`.)

## Validate (no host contact)

```bash
cd /mnt/c/repos/ansible/ansible
export ANSIBLE_CONFIG=$PWD/ansible.cfg
ansible-lint
ansible-playbook playbooks/site.yml --syntax-check
```

`ansible-lint` reports 2 expected warnings (`command-instead-of-module` for deliberate
`systemctl` reads in `firewall`/`cloudflared_coolify`); these are downgraded to warnings in
`.ansible-lint` and do not fail.

## Connect to the host

`ssh vps` (alias in the owner's `~/.ssh/config`) → root@`100.66.37.58` over Tailscale, key
`~/.ssh/916-alien`. `ssh ai@...` does **not** work (the `ai` user doesn't trust that key, and
public SSH is firewalled to Tailscale-only).

To run Ansible from WSL as root, copy the key into WSL with correct perms (ssh rejects 0777 keys
on `/mnt/c`):

```bash
cp /mnt/c/Users/<you>/.ssh/916-alien ~/.ssh/916-alien && chmod 600 ~/.ssh/916-alien
```

## Capture live host state (read-only)

```bash
ssh vps 'sudo bash -s' < bin/discover.sh   # writes discovery/ on the box; changes nothing
```

`discovery/` is gitignored. Reconcile findings into `inventory/group_vars/all.yml` and roles.
The latest reconciliation is documented in [`DISCOVERY-2026-06-23.md`](DISCOVERY-2026-06-23.md).

## Read-only check against the host

```bash
ANSIBLE_CONFIG=/mnt/c/repos/ansible/ansible/ansible.cfg \
ansible-playbook playbooks/site.yml -l hetzner --tags phase1 --check --diff \
  --user root --private-key ~/.ssh/916-alien -e ansible_user=root
```

This makes **no changes** — it shows what would change. Use it as the PR dry-run until CI runs it.

## Apply (changes the host)

Drop `--check` to apply. Phase 1 is non-disruptive. Phase 2 roles are gated and require
`-e enable_phase2=true` (and, for firewall, `-e firewall_apply=true`) and should be proven on a
scratch host first. After any apply, **re-run to confirm 0 changes** (idempotency).

## Run a single role

```bash
ansible-playbook playbooks/site.yml -l hetzner --tags base --check --diff --user root --private-key ~/.ssh/916-alien -e ansible_user=root
```

Tags: `phase1`, `phase2`, or any role name (`base`, `docker`, …).
