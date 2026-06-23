# Role: `cloudflared_coolify`  — ⚠️ RISKY · phase2 · touches a live tunnel

Manages **only Tunnel 1** (`coolify.designflow.app`): its systemd unit and its root-only env
file holding the tunnel token. Read plan §3.1 / §4a.

## Hard boundaries
- **Tunnel 1 only.** Tunnels 2 & 3 (`mcp.designflow.app`, `mcpgw.designflow.app`) are
  **Coolify-managed containers** — never start/stop/recreate them, and this role never
  references them. Do not generalize this into a "cloudflared" role that would fight Coolify.
- **Routing config is remote.** Tunnel 1's path routing (the anchored `^/app(/|$)` regexes,
  etc.) lives in Cloudflare, not a local file — so this role manages the unit + token only,
  not routing. Don't move the routing into a local config.

## Secret
The tunnel token (`cloudflared_tunnel_token`) is injected at apply time from
`op://vibe_coding/cf-tunnel-coolify`. The env file is written `0600 root:root` with `no_log`.
The role refuses to run if the token is empty.

## Safety
A change restarts **only Tunnel 1**, then the role validates `systemctl is-active` returns
`active` (with retries) so a broken tunnel is caught immediately.
