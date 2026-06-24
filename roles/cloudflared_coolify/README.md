# Role: `cloudflared_coolify`  — ⚠️ RISKY · phase2 · touches a live tunnel

Manages **only Tunnel 1** (`coolify.designflow.app`): its systemd unit and (optionally) its
root-only env file holding the tunnel token. Never touches Coolify-managed Tunnels 2 & 3.

## ⚠️ Token blocker (2026-06-24) — not fully applied
The live token in `/etc/cloudflared/coolify-tunnel.env` (180 chars) does **not** match the
1Password values (`cloudflare-tunnel-tokens` → `cloudflare_tunnel_token` / `cf_gw_tunnel_token`,
both 240 chars). Until the owner reconciles which token is correct:
- `cloudflared_manage_token: false` (default) — the role **does not** write the env/token, so it
  can never overwrite the live, working token (which would restart and possibly break the tunnel).
- The role manages **only the systemd unit**, deployed **verbatim** from `files/cloudflared-coolify.service`
  (captured from the live box), so applying it is a no-op.

### To finish this role
1. Owner decides the source of truth: almost certainly the **live** token is correct (it's
   serving traffic). Update 1Password to store the live token in a dedicated field/item.
2. Point `cloudflared_tunnel_token` at that 1Password reference (injected at apply time).
3. Set `cloudflared_manage_token: true`. The env will then match live → still a no-op.

## Boundaries
- **Tunnel 1 only.** Tunnels 2 & 3 are Coolify-managed — never referenced here.
- **Routing config is remote** (in Cloudflare), not a local file — the role manages unit + token only.
- The real unit runs `/usr/local/bin/cloudflared tunnel --no-autoupdate run --token …` (the
  earlier scaffolded template had the wrong binary path/args and was replaced by the verbatim file).
