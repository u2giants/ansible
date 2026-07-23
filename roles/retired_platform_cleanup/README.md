# Role: `retired_platform_cleanup` — non-disruptive phase 1

Removes exact host-level files left behind by retired application platforms.
It is intentionally narrow and idempotent.

## Current cleanup

- `/home/ai/.directus-deploy.env` — obsolete deployment/API credential file
  from the retired legacy backend. The retired application has no runtime,
  import, rollback, or recovery role. Current application credentials belong in
  1Password and Coolify, not this host file.

## Boundary

This role may remove explicitly listed host files only. It must not manage
Coolify applications, containers, proxy configuration, certificates, volumes,
or domain bindings. Those remain Coolify-owned.

## Verification

```bash
ansible-playbook playbooks/site.yml -l hetzner \
  --tags retired_platform_cleanup --check --diff
```

After the managed apply, the path must be absent. A second check must report
zero changes.
