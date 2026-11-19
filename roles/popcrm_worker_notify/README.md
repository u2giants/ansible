# popcrm_worker_notify

Emails the owner when a POP CRM background worker unit fails on `hetz`. This is
the host-side half of [popcrm-web issue #64](https://github.com/u2giants/popcrm-web/issues/64):
the workers themselves (popcrm-web repo) now exit non-zero when their work fails,
and this role makes that failure reach a human — one email to `u2giants@gmail.com`
(owner decision 2026-11-19) via Brevo's transactional-email relay API.

## Why a role

Before this, a failed or timed-out worker left nothing but a journal line on the
box; a dead ingest/reroute/summarize schedule could go unnoticed for days. The
notifier is host wiring (a systemd template unit + a script), so it belongs to
the Ansible layer — a "rebuild everything" must reproduce it, not lose it.

## What it installs

| Path | What |
|---|---|
| `/usr/local/bin/popcrm-worker-failure-notify` | the mailer script (curl → `https://api.brevo.com/v3/smtp/email`) |
| `/etc/systemd/system/popcrm-worker-failure-notify@.service` | oneshot template unit; instance = failed unit's full name; `DynamicUser`, `NoNewPrivileges`, `ProtectSystem=strict` — no privileges beyond sending the mail |
| `/etc/systemd/system/<worker>.service.d/failure-notify.conf` | `OnFailure=popcrm-worker-failure-notify@%n.service` drop-in for each of the five worker units |

Worker units covered (list in `defaults/main.yml`): `popcrm-outlook-ingest`,
`popcrm-reroute`, `popcrm-contact-sync`, `popcrm-summarize`,
`popcrm-apply-ignore-rules`.

## Scope boundary

The worker `.service`/`.timer` units themselves are owned by the **popcrm-web**
repo (installed per its `docs/deployment.md`). This role never copies or edits
them — it only adds the least-invasive systemd drop-in per unit, so the two
repos cannot drift. The notifier unit deliberately has no `OnFailure` of its
own: a broken notifier must fail visibly in the journal, not loop.

## The env file (one manual deploy step)

`/etc/popcrm-worker-notify.env` — root:root, mode `0600` — is read by systemd
(PID 1) when the notifier starts; the `DynamicUser` process never reads the
file itself. **It is not managed by this role and no key value is committed
here.** Populate it once on `hetz` from 1Password vault `vibe_coding`, item
`Sendinblue (Brevo) API Key - designflow-backend`:

```ini
BREVO_API_KEY=<the key value>
# optional overrides (defaults shown):
# POP_CRM_WORKER_NOTIFY_TO=u2giants@gmail.com
# POP_CRM_WORKER_NOTIFY_FROM=noreply@designflow.app
```

`POP_CRM_WORKER_NOTIFY_FROM` must be a sender Brevo has verified for that key's
account; adjust it when populating the file if `noreply@designflow.app` is not.

## What the email looks like

Subject: `POP CRM worker failed: <unit>`. Body: the failed unit name, the
failure time in America/New_York, and the hint to run
`journalctl -u <unit> -n 50` on `hetz` for the tail of the log.

## Why it's safe (phase 1)

Purely additive: one script, one template unit, one drop-in directory + file
per worker. It reloads systemd only; it never restarts, edits, or disables the
worker units or their timers, and never touches Docker, Coolify, or the
firewall. Idempotent: a second apply changes nothing.
