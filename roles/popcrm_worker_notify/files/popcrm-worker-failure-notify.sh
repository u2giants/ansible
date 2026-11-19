#!/usr/bin/env bash
# popcrm-worker-failure-notify — send one email when a POP CRM worker unit fails.
#
# Fired by systemd via the OnFailure= drop-in each POP CRM worker unit carries:
#   OnFailure=popcrm-worker-failure-notify@%n.service
# so the template instance (%i, passed here as $1) is the FAILED unit's full
# name, e.g. "popcrm-reroute.service". Host layer: u2giants/ansible role
# popcrm_worker_notify (popcrm-web issue #64).
#
# Configuration arrives through the environment from the root-only
# /etc/popcrm-worker-notify.env (read by systemd as PID 1, mode 0600):
#   BREVO_API_KEY                required — 1Password vault vibe_coding item
#                                "Sendinblue (Brevo) API Key - designflow-backend"
#   POP_CRM_WORKER_NOTIFY_TO     optional — default u2giants@gmail.com
#                                (owner decision 2026-11-19)
#   POP_CRM_WORKER_NOTIFY_FROM   optional — default noreply@designflow.app
#                                (must be a Brevo-verified sender)
set -euo pipefail

unit="${1:?usage: popcrm-worker-failure-notify <failed unit name>}"

: "${BREVO_API_KEY:?BREVO_API_KEY is not set — populate /etc/popcrm-worker-notify.env (1Password vault vibe_coding, item 'Sendinblue (Brevo) API Key - designflow-backend')}"
to="${POP_CRM_WORKER_NOTIFY_TO:-u2giants@gmail.com}"
from="${POP_CRM_WORKER_NOTIFY_FROM:-noreply@designflow.app}"

when="$(TZ=America/New_York date '+%Y-%m-%d %I:%M:%S %p %Z')"

# JSON built by expansion: every substituted value is either fixed here or a
# systemd unit name ([A-Za-z0-9:._-] and escape sequences only), so no quoting
# pitfalls. Literal \n pairs are intentional — JSON needs them escaped.
payload="{\"sender\":{\"name\":\"POP CRM workers (hetz)\",\"email\":\"${from}\"},\"to\":[{\"email\":\"${to}\"}],\"subject\":\"POP CRM worker failed: ${unit}\",\"textContent\":\"A POP CRM background worker failed on host hetz.\n\nFailed unit: ${unit}\nFailed at: ${when} (America/New_York)\n\nInspect the last 50 journal lines on hetz with:\n\n    journalctl -u ${unit} -n 50\n\nAutomatic systemd OnFailure notification (u2giants/ansible role popcrm_worker_notify).\"}"

# Brevo (Sendinblue) transactional-email relay API. The API key travels in a
# request header, never in the URL or the logs; on failure curl's non-zero exit
# fails this oneshot unit so the attempt is visible in the journal.
if curl --fail --silent --show-error \
    --max-time 60 \
    -H "api-key: ${BREVO_API_KEY}" \
    -H 'content-type: application/json' \
    --data "${payload}" \
    https://api.brevo.com/v3/smtp/email; then
  logger -t popcrm-worker-failure-notify "failure notification for ${unit} mailed to ${to}"
else
  status=$?
  logger -t popcrm-worker-failure-notify "FAILURE: could not mail failure notification for ${unit} to ${to} (curl exit ${status})"
  exit "${status}"
fi
