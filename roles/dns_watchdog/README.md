# dns_watchdog

Host-side DNS self-heal. Installs a systemd timer (`dns-watchdog.timer`, every 5 min) that runs
a oneshot service (`dns-watchdog.service`) which tests real external resolution
(`google.com`/`cloudflare.com` via `getent ahosts`) and, if it's broken, restarts
`systemd-resolved` and flushes caches — logging the outcome to the journal (`-t dns-watchdog`).

This is the active counterpart to [`dns_hardening`](../dns_hardening/README.md) (which sets the
**static** `FallbackDNS`). Both exist because of the **May 2026 DNS cascade outage** (AGENTS §13),
where host `systemd-resolved` broke and took every tunnel/oauth2-proxy container down.

## Why it's a role now

The script + units were running on `hetz` but had only ever been set up by hand — they were **not
in any role**, so a "rebuild everything" would have silently dropped the watchdog. The gap
re-audit on **2026-06-25** caught it (it hid in `/usr/local/sbin`, which the software-drift check
didn't scan until that audit also fixed `bin/discover-software.sh`). The files here are vendored
**verbatim from the live box** for byte-idempotency — do not edit them to "improve" behaviour;
update them only to track what's actually deployed.

## What it manages

| Path | Purpose |
|---|---|
| `/usr/local/sbin/fix-dns-if-broken.sh` | the repair script (test → restart resolved → flush) |
| `/etc/systemd/system/dns-watchdog.service` | oneshot that runs the script |
| `/etc/systemd/system/dns-watchdog.timer` | fires it `OnBootSec=2min`, then every 5 min |

Phase 1 (non-disruptive): only restarts `systemd-resolved` when DNS is **already broken**, so a
routine apply is a no-op on a healthy box.
