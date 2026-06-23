# Role: `users`  — [non-disruptive · phase1]

Ensures the `ai` operator user exists with passwordless sudo and the CI deploy
**public** key installed.

## What it does
- Creates the `managed_user` (`ai`) with a home dir and bash shell (idempotent if it
  already exists).
- Writes `/etc/sudoers.d/90-ai` granting `NOPASSWD:ALL`, validated with `visudo -cf` so a
  malformed file can never be written.
- Adds each key in `users_authorized_keys` with `exclusive: false` — it **adds** keys, never
  removes ones it doesn't know about, so it cannot lock you out.

## Why it's safe
No services touched. `exclusive: false` + `visudo` validation are the two guards against the
classic "Ansible locked me out of SSH" failure.

## Configure
Put the CI deploy **public** key in `group_vars/all.yml` under `users_authorized_keys`. The
matching private key lives in 1Password and is provided to the CI runner — never committed.
