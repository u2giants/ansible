# Role: `firewall`  — phase2

Manages **only the host-owned SSH lockdown** in the `filter` `INPUT` chain, declaratively
(`ansible.builtin.iptables`). It deliberately does **not** manage the whole ruleset.

## Why only the SSH rules (the rework, 2026-06-24)
The original design captured the entire `iptables-save` and re-stamped it. That fails on this
box: **Docker rewrites its `nat` chains every time a container cycles** (confirmed — the captured
file drifted within a day), so re-applying a saved copy fights Docker and risks breaking container
networking. The `INPUT` chain (where the SSH rules live) is **stable** — Docker doesn't touch it —
so the role manages just those rules and leaves the daemon-owned chains alone:

| Chain / rules | Owner | This role |
|---|---|---|
| `filter INPUT` SSH rules (port 22 lockdown, 1904 open) | host | ✅ manages |
| `ts-input` | Tailscale (`tailscaled`) | ❌ leave |
| `DOCKER-USER` private-port rules | host | ✅ manages (only its own rules) |
| other `DOCKER*`, `nat` PREROUTING | Docker (`dockerd`) | ❌ leave |
| `f2b-*` | fail2ban | ❌ leave (just ensures fail2ban enabled) |

## Policy (matches live hetz)
INPUT policy stays **ACCEPT** (default-allow). The only restriction is SSH:
- **port 22**: allowed from `firewall_ssh_trusted_v4/v6` (Tailscale, localhost/cloudflared, docker
  subnet), **dropped** from everyone else.
- **port 1904** (`firewall_ssh_public_ports`): left open to the public internet — `ssh_hardening`
  restricts that port to the `ai` account.
- **IPv6**: the same port-22 lockdown is applied (`firewall_lock_ipv6: true`). Live v6 currently
  has *no* port-22 restriction — this closes that gap. (Defense-in-depth; `ssh_hardening` already
  gates who may log in on any address.)

Applying to prod is a **no-op on IPv4** (the rules already exist) and **adds the IPv6 lockdown**.

## Private admin ports (2026-11-18)
Coolify publishes `0.0.0.0/[::]:8000->8080` and `6001-6002`; Backrest listens on `*:9898` with no
login. All four are restricted to Tailscale, localhost and the Docker networks
(`firewall_private_trusted_v4/v6`); everyone else is dropped. The public path is
`https://coolify.designflow.app` via the Cloudflare tunnel (cloudflared -> `127.0.0.1:8000`).
- **9898** is a host process, so it is filtered in `INPUT` (module-managed, like SSH).
- **8000/6001/6002** are Docker-published: DNAT sends them through `FORWARD`, never `INPUT`. They are
  filtered in **`DOCKER-USER`** (Docker creates it, jumps to it first, and never flushes it), matched
  by `conntrack --ctorigdstport` (the pre-DNAT port) so container IPs/ports don't matter. Trusted
  sources `RETURN` to Docker's own rules (inserted at the top); the per-port `DROP`s are appended.
- An upstream filter (Hetzner) already blocks 6002/9898 from the internet (packets never reach
  eth0); these rules are the host-side guarantee.
- The stale `INPUT --dport 18790 ACCEPT` (nothing listened) is removed.
- Apply: dispatch `apply.yml` with `tags=firewall` (that exact tag opens the phase2 gate for this
  role only).

## Safe to re-run
Each rule is declarative and idempotent (`iptables -C` match), so re-runs make no changes and
there is no drift. A change persists via `netfilter-persistent save` (handler). The role connects
over Tailscale (a trusted source), so the SSH lockdown can't cut the control path; a final
`ping` confirms reachability.

## Not managed / future
- `files/hetz.rules.v{4,6}` are kept only as a **disaster-recovery snapshot** of the full live
  ruleset; the role does not apply them.
- Tightening INPUT policy to default-DROP is out of scope (would require enumerating every needed
  port and risks breaking apps).
