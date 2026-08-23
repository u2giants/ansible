# restore_test

Installs the monthly **restore test** on `hetz` — the thing that turns "the backup ran" into
"the backup restores".

## Why it exists

Backrest reporting success proves a snapshot was written. It does not prove the snapshot can be
read back and turned into a working database. Before 2026-08-23 nobody had ever checked, across
the entire life of the backup system. The first run passed (snapshot `7dcea44a`, 87.3 MB, 134
seconds, real rows in `users` / `servers` / `applications`) — but a one-off pass decays, so the
check is scheduled rather than remembered.

## What it installs

| Path | What |
|---|---|
| `/opt/backrest/scripts/test-restore.sh` | the test, vendored verbatim from `u2giants/backrest-wiz` |
| `/etc/systemd/system/backrest-restore-test.service` | oneshot, 45 min timeout, `idle` I/O |
| `/etc/systemd/system/backrest-restore-test.timer` | 1st of the month 05:00, persistent, 15 min jitter |
| `/opt/backrest/restore-tests/` | `latest.json` verdict + `latest.log`, mode 0700 |

## What the test does

Restores the newest `coolify-db-latest.sql` **from the offsite restic repo** — not the local
copy, which would prove nothing — into a throwaway PostgreSQL 15 container on a `none` network
with a tmpfs data directory, asserts the expected tables came back with plausible row counts,
then removes everything. It never touches `coolify-db`, the live volumes, or the repo's
contents. Credentials move through a 0600 `--env-file`, never argv.

Exit `0` verified · `1` **the restore failed** · `2` the test could not run. All three write a
verdict, so "never ran" can never be mistaken for "passed".

## Where the result shows up

The Restore Wizard dashboard (`backup.designflow.app`) reads `latest.json` over SSH and shows
PASSED / FAILED / NEVER TESTED, with an overdue flag once a pass is more than five weeks old.

## Keeping it in sync

Canonical source: `u2giants/backrest-wiz` → `hetzner-producer/scripts/test-restore.sh`.
Fix it there, then re-vendor into `files/`. Do not edit the copy here.

## Known coverage limit

Proves the **Coolify Postgres dump** path only. The `docker-volumes` and `coolify-config`
plans, and the SQLite and Redis dumps, are not yet restore-tested.
