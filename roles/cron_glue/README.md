# Role: `cron_glue`  — phase2

Manages host cron **entries** — that a job exists, for which user, on what schedule. It does
**not** manage the scripts those jobs run.

## Ownership boundary (plan §4a, decided)
- **Ansible owns:** the cron entry (`ansible.builtin.cron`).
- **Source repos own:** the keeper scripts themselves — e.g. `/worksp/hiclaw/*.sh` belong to
  the HiClaw repo, `/home/ai/bin/sync-infra-docs.sh` to its own repo.

The minute-by-minute HiClaw reconciliation loops are an app-layer smell; **do not adopt them**
into host Ansible. Only put genuine host-glue schedules in `cron_glue_entries`.

## Configure
Edit `cron_glue_entries` in `group_vars/all.yml`. Each entry takes `name`, `job`, `user`, and
standard cron fields (`minute`/`hour`/…), plus optional `state`/`disabled`.
