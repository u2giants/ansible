# headroom_proxy

Host Headroom AI proxies used by the AI coding tools (added 2026-10-20, issue #17):

| Unit | Port | Purpose |
|---|---|---|
| `headroom.service` (+ `unauth-bind.conf` drop-in) | 8787 | Claude lane |
| `headroom-zcode.service` | 8788 | Z.ai / ZCode lane (isolated HOME) |
| `zcode-headroom-tls.service` | 8443 | TLS front for the ZCode lane |

Plus the hourly `headroom-perf/record.py` cron entry. Files in `files/` are verbatim copies
of the live box — keep them byte-identical. `headroom-ai` is installed with pipx at the pinned
`headroom_version`. The self-signed TLS CA is generated only if absent (it is not backed up);
after a rebuild, tailnet clients must trust the new `ca.crt`.

Security: both proxies run with `HEADROOM_ALLOW_UNAUTHENTICATED_BIND=1` on the tailnet address and
the TLS front has no auth — the Tailscale ACL is the only access control.

Defects found by the 2026-10-20 audit, fixed 2026-10-21 (issue #17): `record.py` now tolerates the
extra headroom 0.41 PERF fields; the TLS front streams responses as they arrive, sends no body or
chunk framing for HEAD/1xx/204/304, and de-chunks chunked request bodies; `StartLimit*` moved to
`[Unit]`.
