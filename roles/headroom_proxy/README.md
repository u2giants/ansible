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

Known live defects (preserved verbatim, tracked on issue #17): `record.py` regex no longer matches
headroom 0.41 PERF lines; TLS front buffers streamed responses; `StartLimit*` keys sit in `[Service]`.
