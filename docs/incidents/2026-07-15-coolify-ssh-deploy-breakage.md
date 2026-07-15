# Incident 2026-07-15 — Coolify app deploys silently broken by SSH hardening

**Severity:** high (all app deploys on `hetz` broken) · **Host damage:** none (host stayed up)
**Affected:** every Coolify-managed app on the `hetz` VPS — popcrm-web, poppim-web, popdam,
monitor, hiclaw, etc.
**Root cause area:** `roles/ssh_hardening` SSH access policy vs. Coolify's root-over-Docker-bridge
deploy path.

## What happened

Starting **2026-07-14**, every Coolify-managed app deploy on `hetz` silently failed:

- The GitHub Actions "deploy" job triggered Coolify and got a **"deployment queued"** response, so
  CI looked green.
- The deployment then **FAILED** inside Coolify with `Server is not functional` /
  `Permission denied (publickey)`.
- The running container was **never replaced** (it stayed days old) and the live site kept serving
  the **old bundle**.
- Coolify marked its own server `is_reachable=false, is_usable=false`.

There was no obvious error surfaced in GitHub Actions — the deploy trigger still returned "queued",
which is why the breakage was silent.

## What change caused it

The `ssh_hardening` role's template
[`roles/ssh_hardening/templates/20-access-policy.conf.j2`](../../roles/ssh_hardening/templates/20-access-policy.conf.j2)
was applied on **2026-07-14 16:32**, rendering `/etc/ssh/sshd_config.d/20-access-policy.conf` with:

- global `PermitRootLogin no`
- `Match Address <ssh_trusted_sources>` (Tailscale `100.64.0.0/10` + IPv6 ULA + `127.0.0.1`/`::1`)
  → `PermitRootLogin prohibit-password`
- `Match Address *,!<trusted>` (the public-internet bucket) → `AllowUsers ai` (root not allowed)

The controlling variable is `ssh_trusted_sources` in
[`roles/ssh_hardening/defaults/main.yml`](../../roles/ssh_hardening/defaults/main.yml).

**Why that broke deploys:** Coolify performs deploys by SSHing **as `root`** to
`host.docker.internal` from the **Docker bridge network `10.0.1.0/24`** (observed source
`10.0.1.15`). Because `10.0.1.0/24` was **not** in `ssh_trusted_sources`, Coolify's root SSH fell
into the "public internet" bucket (`AllowUsers ai`, root refused) and was rejected.

Host `auth.log` confirms it, first occurrence **2026-07-14 16:33:02** — immediately after the
config was written:

```
User root from 10.0.1.15 not allowed because not listed in AllowUsers
```

**This was not a key problem.** Coolify's public key (`coolify coolify-localhost`, restricted with
`from="10.0.1.0/24"`, fingerprint `wXtvwv6u…`) was still present in `/root/.ssh/authorized_keys`
and still matched Coolify's stored private key. The access *policy* refused it, not the key.

## The warning / do-not-repeat

Any future tightening of `ssh_trusted_sources` / `AllowUsers` / `PermitRootLogin` in the
`ssh_hardening` role **MUST preserve root SSH (key-only) from the Docker bridge `10.0.1.0/24`**,
because **Coolify's deploy engine connects as root over that network** to `host.docker.internal`.

Removing it silently breaks **ALL** app deploys on the host with **no obvious error in GitHub
Actions** (the deploy trigger still returns "queued"). This is safe to keep: Coolify's
`authorized_keys` entry is already restricted to `from="10.0.1.0/24"` and is key-only (no password).

Before changing SSH access policy on `hetz`, verify:

1. Coolify can still `is_usable=true` its localhost server, and
2. a test app deploy actually **swaps the container** (not just returns "queued").

Note the firewall already trusts `10.0.1.0/24` for port 22 (see `AGENTS.md` §10, "Firewall default
policy"); the gap was only in the `ssh_hardening` access *policy* (`AllowUsers` / `PermitRootLogin`),
so the two must be kept consistent.

## The fix

Add the Coolify/Docker internal bridge network **`10.0.1.0/24` (IPv4)** to the `ssh_trusted_sources`
role variable in [`roles/ssh_hardening/defaults/main.yml`](../../roles/ssh_hardening/defaults/main.yml)
so the `Match Address` block grants root `PermitRootLogin prohibit-password` from that network:

```yaml
ssh_trusted_sources:
  - "100.64.0.0/10"          # Tailscale IPv4 (CGNAT range)
  - "fd7a:115c:a1e0::/48"    # Tailscale IPv6 (ULA prefix)
  - "127.0.0.1"              # localhost (cloudflared SSH lands here)
  - "::1"
  - "10.0.1.0/24"            # Coolify / Docker internal bridge — Coolify SSHes as root to deploy
```

Applied via the normal **Ansible apply pipeline** (not by hand-editing `/etc` on the box). After
the change renders the drop-in and reloads sshd, Coolify's localhost server returns to
`is_usable=true` and app deploys resume swapping containers.

The fix is safe and scoped: Coolify's `authorized_keys` entry is already pinned to
`from="10.0.1.0/24"` and is key-only, so this grants no broader access than the key already allows.
