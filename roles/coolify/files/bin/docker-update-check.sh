#!/usr/bin/env bash
# Reports when a newer docker/containerd is available (they're apt-mark hold'd, so
# normal apt upgrade skips them). Logs to a status file. See deploy/vps/README.md.
LOG=/var/log/docker-update-check.log
apt-get update -qq 2>/dev/null
UP=$(apt list --upgradable 2>/dev/null | grep -iE '^(docker-ce|docker-ce-cli|containerd\.io|docker-buildx-plugin|docker-compose-plugin)/' || true)
ts=$(date -u +%FT%TZ)
if [ -n "$UP" ]; then
  { echo "[$ts] DOCKER UPDATE AVAILABLE:"; echo "$UP"; echo "To apply: sudo apt-mark unhold docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras docker-model-plugin && sudo apt install -y --only-upgrade docker-ce docker-ce-cli containerd.io && sudo apt-mark hold docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras docker-model-plugin && docker restart coolify-proxy"; echo; } >> "$LOG"
else
  echo "[$ts] docker up to date (held)" >> "$LOG"
fi
