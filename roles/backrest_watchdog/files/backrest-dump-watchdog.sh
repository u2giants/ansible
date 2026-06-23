#!/bin/bash
# Backrest DB-dump self-heal watchdog (runs on the HOST via systemd timer, every 15 min).
#
# Why this exists: the backrest container dumps databases by talking to the Docker daemon
# through a bind-mounted /var/run/docker.sock. When the host's Docker daemon restarts, that
# socket is recreated and the container holds a STALE handle -> every `docker exec` fails ->
# dumps silently freeze. In June 2026 this went unnoticed for 4 days. The host can always
# reach Docker, so the host watchdog detects the wedged state and restarts the container.
#
# It heals three conditions:
#   1. backrest container not running        -> bring it up
#   2. backrest cannot reach docker.sock      -> restart it, then trigger a dump
#   3. freshest dump is stale (any cause)     -> trigger a dump
set -uo pipefail

LATEST=/opt/backrest/db-dumps/coolify-db-latest.sql
STALE_MIN=45            # coolify-db dumps every 15 min; >45 min = 3 missed cycles
LOG() { logger -t backrest-watchdog "$*" 2>/dev/null; echo "$(date '+%F %T') $*"; }

# 1. container running?
if ! docker ps --format '{{.Names}}' | grep -q '^backrest$'; then
    LOG "backrest not running -> compose up"
    (cd /opt/backrest && docker compose up -d) || LOG "compose up FAILED"
    exit 0
fi

# 2. container can reach Docker?
if ! docker exec backrest docker ps >/dev/null 2>&1; then
    LOG "backrest cannot reach docker.sock (stale mount) -> restarting backrest"
    docker restart backrest >/dev/null 2>&1 || LOG "restart FAILED"
    sleep 5
    if docker exec backrest /scripts/pre-backup.sh >/dev/null 2>&1; then
        LOG "post-restart dump OK"
    else
        LOG "post-restart dump STILL FAILING - needs a human"
    fi
    exit 0
fi

# 3. dump fresh?
if [ ! -f "$LATEST" ] || [ -n "$(find "$LATEST" -mmin +"${STALE_MIN}" 2>/dev/null)" ]; then
    LOG "coolify-db dump stale (>${STALE_MIN} min) despite Docker reachable -> triggering dump"
    if docker exec backrest /scripts/pre-backup.sh >/dev/null 2>&1; then
        LOG "recovery dump OK"
    else
        LOG "recovery dump FAILED - needs a human"
    fi
fi
exit 0
