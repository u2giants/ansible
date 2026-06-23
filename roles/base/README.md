# Role: `base`  — [non-disruptive · phase1]

Brings the OS to a known baseline: explicitly-installed apt packages, timezone,
automatic security updates, and a cap on journald disk usage.

## What it does
- Installs `base_packages` (defined in `group_vars/all.yml`) — reconcile this list with
  `discovery/.../packages-manual.txt` from `bin/discover.sh`. **Do not** add Coolify/app
  dependencies here; those belong to the app layer.
- Sets the system timezone (`host_timezone`).
- Enables `unattended-upgrades` for security patches.
- Caps `journald` to `base_journald_max_use` so logs can't fill the disk.

## Why it's safe
Purely additive. Installing packages and writing two drop-in config files does not touch
Docker, Coolify, the firewall, or any running container. The only restart it triggers is
`systemd-journald`, which has no effect on the app layer.

## Verify (definition of done, plan §8)
```bash
ansible-playbook playbooks/site.yml --tags base            # apply
ansible-playbook playbooks/site.yml --tags base --check    # second run shows 0 changes
```
