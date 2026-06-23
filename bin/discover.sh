#!/usr/bin/env bash
# discover.sh — Phase 0 state capture (plan §7).
#
# Run this ON THE BOX (you have sudo) to inventory the live host BEFORE writing or
# trusting any role. Do NOT guess what's installed — capture it, then make the roles
# reproduce it. Output is written to ./discovery/<hostname>-<utc-ish>/ as plain text
# files you can diff against what the roles assert.
#
# This script makes ZERO changes to the host. It is safe to run any number of times.
#
# Usage:  ssh ai@hetz 'sudo bash -s' < bin/discover.sh
#    or:  scp bin/discover.sh ai@hetz: && ssh ai@hetz 'sudo bash discover.sh'
set -euo pipefail

OUT="discovery/$(hostname)-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUT"
echo "Writing discovery output to: $OUT"

run() { # run <outfile> <command...>
  local f="$OUT/$1"; shift
  echo "  -> $f"
  { echo "# \$ $*"; eval "$@"; } >"$f" 2>&1 || echo "  (command exited non-zero; see $f)"
}

# Packages explicitly installed (not pulled in as deps)
run packages-manual.txt \
  "comm -23 <(apt-mark showmanual | sort) <(gzip -dc /var/log/installer/initial-status.gz 2>/dev/null | sed -n 's/^Package: //p' | sort)"

# Enabled services + timers
run services-enabled.txt "systemctl list-unit-files --state=enabled --type=service"
run timers.txt           "systemctl list-timers --all"

# Cron
run cron-root.txt        "crontab -l 2>/dev/null; echo '--- /etc/cron.d ---'; ls -la /etc/cron.d; echo '--- spool ---'; cat /var/spool/cron/crontabs/* 2>/dev/null"

# Firewall
run iptables-save.txt    "iptables-save"
run iptables-rules-files.txt "cat /etc/iptables/rules.v4 /etc/iptables/rules.v6 2>/dev/null"
run fail2ban.txt         "fail2ban-client status 2>/dev/null || echo 'fail2ban not queryable'"

# Users with login + sudo
run users-login.txt      "getent passwd | awk -F: '\$7!~/nologin|false/'"
run sudoers.txt          "cat /etc/sudoers.d/* 2>/dev/null"

# Managed /etc files of interest
run etc-managed.txt      "ls -la /etc/systemd/resolved.conf.d/ /etc/cloudflared/ 2>/dev/null; echo '--- daemon.json ---'; cat /etc/docker/daemon.json 2>/dev/null; echo '--- fallback-dns ---'; cat /etc/systemd/resolved.conf.d/fallback-dns.conf 2>/dev/null"

# Glue scripts
run glue-scripts.txt     "ls -la /usr/local/bin/ /home/ai/bin/ 2>/dev/null; ls -la /worksp/hiclaw/*.sh 2>/dev/null"

# Docker engine + compose versions (for pinning, plan §4a)
run docker-version.txt   "docker version; echo '---'; docker compose version; echo '---'; apt-cache policy docker-ce"

# Listening ports (for the rebuild-and-diff, plan §8.3)
run listening-ports.txt  "ss -tulpn 2>/dev/null || netstat -tulpn"

echo
echo "Done. Review $OUT/, then fill in inventory/group_vars/all.yml and role vars to match."
echo "Anything Coolify-owned (app containers, Traefik dynamic config) is OUT of scope — skip it."
