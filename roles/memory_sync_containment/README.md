# Role: `memory_sync_containment` — non-disruptive phase 1

Contains the 2026-08-21 public-memory incident on `hetz` without hand-editing
the production host.

The role first makes an owner-only backup of every Claude project `memory/`
directory, including a SHA-256 manifest. It then removes the exact cron entry
named `sync claude memory across machines`. The backup path is fixed in
`defaults/main.yml`, so repeated applies are idempotent and never overwrite a
newer snapshot.

This role does not remove memory files, application data, Coolify resources, or
the `ai-devops` checkout. A governed private-memory schedule can be introduced
later as a separate change after its credentials and recovery path are proven.

## Verification

```bash
ansible-playbook playbooks/site.yml -l hetzner \
  --tags memory_sync_containment --check --diff
```

After the production apply, the `ai` crontab must not contain
`ai-memory-sync`, the backup manifest must exist with owner-only permissions,
and a second tagged apply must report zero changes.
