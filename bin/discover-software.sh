#!/usr/bin/env bash
# discover-software.sh — print a NORMALIZED inventory of every piece of software on the host,
# for the recovery software-coverage check (gap R6). Run on the box; makes ZERO changes.
#
# The output is a sorted, stable list with one-line "CATEGORY  name[=version]" entries. It is
# compared against the committed baseline (docs/baseline-software.txt) by the software-drift CI
# job: anything on the box that isn't in the baseline = software installed outside Ansible.
#
#   ssh vps 'sudo bash -s' < bin/discover-software.sh
set -uo pipefail

# Manually-installed apt packages (not pulled in as deps, not part of the base image)
comm -23 <(apt-mark showmanual | sort) \
         <(gzip -dc /var/log/installer/initial-status.gz 2>/dev/null | sed -n 's/^Package: //p' | sort) \
  | sed 's/^/APT  /'

# Binaries / scripts dropped into /usr/local/bin (the non-apt tools + glue scripts)
ls -1 /usr/local/bin 2>/dev/null | sort | sed 's/^/BIN  /'

# Admin scripts dropped into /usr/local/sbin (e.g. the dns watchdog). Scanned because a
# host-side glue script (fix-dns-if-broken.sh) hid here and escaped the drift check until the
# 2026-06-25 gap re-audit added this line.
ls -1 /usr/local/sbin 2>/dev/null | sort | sed 's/^/SBIN /'

# Global npm packages (name@version)
if command -v npm >/dev/null 2>&1; then
  npm ls -g --depth=0 --parseable 2>/dev/null \
    | sed 's#.*/node_modules/##' | grep -v '^/' | grep . | sort \
    | sed 's/^/NPM  /'
fi

# Snap packages
if command -v snap >/dev/null 2>&1; then
  snap list 2>/dev/null | awk 'NR>1{print $1}' | sort | sed 's/^/SNAP /'
fi
