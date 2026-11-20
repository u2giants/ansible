---
issue: 43
status: OPEN
owner: claude session 4f932126-eceb-4c13-baaf-5c03d0b5d35a (hetz)
---

# hetz health check, 2026-11-18: follow-ups

## 0. ⚠️ Business decisions only the owner can make

None. Nothing in this workstream needs Albert. Every item below is technical work for the AI.

Already settled. Do not re-ask:
- 2026-11-18 6:35 PM EST: Albert asked for the CRM job (#3) and the Coolify exposure (#4) to be fixed. Both are done (§3).
- 2026-11-19 2:25 PM EST: asked whether to investigate the shared-database overload, Albert said **"Not now."** Do not start it unless he asks again. It is tracked in https://github.com/popcre/shared-db/issues/6886.

## 1. What this application is

`hetz` is POP Creations' single Hetzner Ubuntu server. Public IP 178.156.180.212; Tailscale IP 100.66.37.58. It hosts the business web apps through Coolify, a self-hosted deployment tool. The apps include POP CRM (crm.designflow.app), POP DAM (dam.designflow.app), POP PIM, data admin, the NAS monitor and email cleanup. It also runs the AI agent tooling.

This repository, https://github.com/u2giants/ansible, manages the server's operating-system layer: packages, firewall, SSH and system units. Start with https://github.com/u2giants/ansible/blob/main/AGENTS.md.

## 2. What this session set out to do, and why

On 2026-11-18 Albert asked: "is Hetz working in tip-top shape? performance, errors, security, anything". The request was a read-only investigation. It found four problems:

1. Second disk full.
2. Swap nearly exhausted.
3. POP CRM "apply ignore rules" job failing.
4. Coolify login exposed over plain HTTP on public port 8000.

Albert then asked for #3 and #4 to be fixed.

## 3. Current state: what is true right now (2026-11-20 8:53 AM EST)

- **#3 is done.** https://github.com/u2giants/popcrm-web/pull/73 was merged as commit https://github.com/u2giants/popcrm-web/commit/521d5b503f0162370ff498d7e9441853f1582a5a. The job now skips the scan when no ignore rules exist and retries timed-out reads twice. The server checkout of popcrm-web was fast-forwarded; it had been 355 commits behind, and the four other CRM timer jobs run from the same checkout. Verified: the unit `popcrm-apply-ignore-rules.service` exited 0 at 2026-11-18 6:38 PM EST and again at 2026-11-20 6:35 AM EST.
- **#4 is done.** https://github.com/u2giants/ansible/pull/40 was merged as commit https://github.com/u2giants/ansible/commit/6127b4333133408ded15006147f0fc6ea5ea0d75. The `firewall` role now restricts Docker-published ports 8000, 6001, 6002 and 9898 to Tailscale, localhost and the Docker subnets, and it removed the stale 18790 rule. It was applied through the repo's apply pipeline. Verified 2026-11-18 at about 6:50 PM EST: probes from the outside machine `edgesynology1` to those four ports time out. https://coolify.designflow.app answers 302, Backrest answers locally, and 443 and 1904 still work.
- **Disk (#1) has recovered but has no guard.** `/mnt/HC_Volume_107232195` was at 100% on Nov 18 and is at 70% now. Who freed the space is unknown. Issue 43 tracks a standing guard.
- **Swap (#2) has recovered.** It was 11.2 of 12 GB on Nov 18 and is 6.5 GB now. It is a watch item.
- **The shared database overload is not investigated, per the owner.** It is tracked in https://github.com/popcre/shared-db/issues/6886.

## 4. Everything tried that did NOT work

- **The local `techsupport` checkout has a corrupt `.git`** (no HEAD or config), so it could not be pulled. That repo (https://github.com/u2giants/techsupport) is about home SMB setup, not hetz. The useful baseline for hetz is this ansible repo.
- **Starting nested Claude sessions failed** while Albert was on Remote Control; the app refuses session starts there. Background subagents were used instead.
- **The first diagnosis of #3 was wrong.** It looked like a slow query. The subagent measured the scan at about 85 ms over about 23,000 rows. The real cause was the whole shared database timing out (see §5).

## 5. Root causes and key findings

- **The CRM failures came from load on the shared Supabase database.** Its logs showed statement timeouts across every query type on 2026-11-18, peaking near 160 an hour. Nobody owns that problem yet: https://github.com/popcre/shared-db/issues/6886.
- **Backrest has no authentication.** Any process that can reach port 9898 can call `POST /v1.Backrest/GetConfig` and read the backup repository password and S3 keys. Before #40 it was already blocked from the internet by an upstream filter, most likely the Hetzner cloud firewall, which is not documented in this repo. It is now also blocked on the host. It remains open to the tailnet. That exposure is tracked in issue 43. The credentials appeared only in a local session transcript on hetz, so per the standing rule they are not rotated.
- **Backrest's DB-dump job writes a 145 MB Coolify database dump every 15 minutes with 24-hour retention**, about 14 GB at steady state. It is a large fixed share of the second disk.
- **Traefik spams Let's Encrypt retries** for `coolify.designflow.app`, about 418 errors a day while rate-limited. That name is actually served through Cloudflare. `higress.designflow.app` is routed but has no DNS.
- **Root SSH is allowed only from Tailscale, localhost and 10.0.1.0/24** (Coolify). This is by design; do not "fix" it.

## 6. Exact next steps

1. **Add a disk-space guard for `/mnt/HC_Volume_107232195`.** Use an alert or automatic pruning of `coolify-backups-old`, delivered through this repo (for example a `cron_glue` or `backrest_watchdog` addition). You'll know it worked when the apply passes and a simulated threshold breach produces the alert or prune.
2. **Decide whether Backrest needs login auth.** Its config supports it. Enable it through the repo or Coolify without breaking the Backrest watchdog. You'll know it worked when `GetConfig` without credentials returns 401, from the tailnet and from localhost.
3. **Stop the Traefik Let's Encrypt retries for `coolify.designflow.app`, and drop the dead `higress` route.** You'll know it worked when there are 0 ACME errors in `docker logs --since 24h coolify-proxy`.
4. **Schedule the 28 pending package updates and the reboot** through the normal maintenance path. You'll know it worked when `/var/run/reboot-required` is absent.
5. **Retirement:** close issue 43 and delete this file in the same PR.

## 7. Constraints and gotchas

- Change the host only through this repo and its apply pipeline. Never hand-edit `/etc` on hetz.
- Docker rewrites its own chains; see https://github.com/u2giants/ansible/blob/main/roles/firewall/README.md.
- Docker and containerd data stays on `/dev/sda1` on purpose, because the network volume is too slow for databases.
- `/worksp/ansible` on hetz is another session's dirty checkout (branch `codex/fix-software-drift`). Use a fresh clone or worktree.
- The root `HANDOFF.md` here is still a legacy full document. Its migration was skipped because other sessions are active in this repo.

## 8. Access and environment

Work from hetz itself, user `ai`, with passwordless sudo. `gh` is authenticated as `u2giants`. Secrets live in the 1Password vault `vibe_coding`, never in files. The outside-vantage probe host is the SSH alias `edgesynology1`.

## 9. Open questions and risks

- 2026-11-18: the upstream filter that blocks 9898 from the internet is unidentified and undocumented (probably a Hetzner cloud firewall). Risk: someone edits it unaware.
- The shared-database overload could recur and hit other apps. Owner: none yet (issue 6886).
- IPv6 blocking from outside was not tested; the same rules are in place for IPv6.

## Self-audit (2026-11-20)

1. **Could a newcomer continue?** Yes. The app context is in §1, the state with proof in §3, and the steps in §6.
2. **Could they continue as well as I could?** Yes. The dead ends are in §4 and the non-obvious findings in §5.
3. **Are all the details present?** Yes, across §2–§9, with GitHub URLs throughout.
4. **Does §0 hold every business decision?** Yes. A sweep of §3, §5, §6 and §9 found the overload ("Not now", recorded in §0) and no other business decision. Everything else is technical.
