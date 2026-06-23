#!/usr/bin/env bash
# backrest-dump-watchdog.sh — self-heal the backrest backup agent (plan §3.4).
#
# Problem: backrest bind-mounts /var/run/docker.sock. When the host Docker daemon restarts,
# the socket is recreated and backrest keeps a STALE handle — it can no longer exec the
# database dumps. This silently broke backups for 4 days in June 2026.
#
# This watchdog (run by a systemd timer on the HOST, not inside a container) detects the
# wedged state and restarts the backrest container so it re-opens a fresh docker.sock.
#
# It is intentionally conservative: it only acts when it has positive evidence of the wedge,
# and a restart of one backup container is non-disruptive to apps/Coolify.
set -euo pipefail

CONTAINER="${BACKREST_CONTAINER:-backrest}"
LOG_TAG="backrest-watchdog"
log() { logger -t "$LOG_TAG" -- "$*"; echo "[$LOG_TAG] $*"; }

# If the container isn't running at all, let Coolify/restart-policy handle it — not our job.
if ! docker inspect -f '{{.State.Running}}' "$CONTAINER" >/dev/null 2>&1; then
  log "container '$CONTAINER' not present/running; nothing to do"
  exit 0
fi

# Probe the docker.sock from inside the container the way backrest uses it. A healthy agent
# can reach the daemon; a wedged one fails with a stale-handle/connection error.
if docker exec "$CONTAINER" sh -c 'docker version >/dev/null 2>&1 || curl -s --unix-socket /var/run/docker.sock http://localhost/_ping >/dev/null 2>&1'; then
  # Healthy.
  exit 0
fi

log "container '$CONTAINER' cannot reach docker.sock (stale handle suspected) — restarting it"
if docker restart "$CONTAINER" >/dev/null 2>&1; then
  log "restarted '$CONTAINER' successfully"
else
  log "ERROR: failed to restart '$CONTAINER'"
  exit 1
fi
