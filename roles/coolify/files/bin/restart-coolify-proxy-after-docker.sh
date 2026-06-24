#!/usr/bin/env bash
# Runs after docker.service (re)starts (e.g. a docker auto-upgrade). Restarts
# coolify-proxy so Traefik re-reads the current docker socket — fixes the
# stale-socket-after-daemon-restart issue and lets docker update freely.
LOG=/var/log/coolify-proxy-watchdog.log
for i in $(seq 1 30); do docker info >/dev/null 2>&1 && docker inspect coolify-proxy >/dev/null 2>&1 && break; sleep 2; done
if docker restart coolify-proxy >/dev/null 2>&1; then
  echo "$(date -u +%FT%TZ) reconnect: coolify-proxy restarted after docker (re)start" >> "$LOG"
else
  echo "$(date -u +%FT%TZ) reconnect: FAILED to restart coolify-proxy" >> "$LOG"
fi
