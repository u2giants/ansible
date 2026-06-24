# Role: `cloudflared_coolify`  — ⚠️ RISKY · phase2 · touches a live tunnel

Manages **only Tunnel 1** (`coolify.designflow.app`): its systemd unit and (optionally) its
root-only env file holding the tunnel token. Never touches Coolify-managed Tunnels 2 & 3.

## Token — reconciled (2026-06-24)
The live tunnel token (180 chars) didn't match the older `cloudflare-tunnel-tokens` 1Password
fields (240 chars). Resolved by storing the **live, working** token in a dedicated item
**`op://vibe_coding/cf-tunnel-hetz/password`** (hash-verified to equal the live token). The
older fields were left untouched.

- `cloudflared_manage_token: false` (default) — routine runs manage only the unit and leave the
  already-correct live env alone, so a full apply never needs the token and never restarts the
  tunnel.
- The unit is deployed **verbatim** from `files/cloudflared-coolify.service` (captured from the
  live box) → applying it is a no-op.
- For a **rebuild / CI** run that must recreate the env: inject the token
  (`export CLOUDFLARED_TUNNEL_TOKEN="$(op read op://vibe_coding/cf-tunnel-hetz/password)"`,
  or via `1password/load-secrets-action`) and set `cloudflared_manage_token: true`. It writes the
  same token → still a no-op on the existing box.

## Boundaries
- **Tunnel 1 only.** Tunnels 2 & 3 are Coolify-managed — never referenced here.
- **Routing config is remote** (in Cloudflare), not a local file — the role manages unit + token only.
- The real unit runs `/usr/local/bin/cloudflared tunnel --no-autoupdate run --token …` (the
  earlier scaffolded template had the wrong binary path/args and was replaced by the verbatim file).
