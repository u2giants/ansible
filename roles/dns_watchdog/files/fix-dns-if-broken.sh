#!/usr/bin/env bash
set -euo pipefail

IFACE="$(ip route | awk '/default/ {print $5; exit}')"

if getent ahosts google.com >/dev/null 2>&1 || \
   getent ahosts cloudflare.com >/dev/null 2>&1; then
  exit 0
fi

logger -t dns-watchdog "DNS broken. Reapplying settings."

systemctl restart systemd-resolved
resolvectl flush-caches || true

if getent ahosts google.com >/dev/null 2>&1; then
  logger -t dns-watchdog "DNS repaired."
else
  logger -t dns-watchdog "DNS repair failed — manual intervention needed."
  exit 1
fi
