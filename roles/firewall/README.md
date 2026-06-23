# Role: `firewall`  — ⚠️ RISKY · phase2 · CAN LOCK YOU OUT

The single highest-risk role. A wrong rule can (a) lock you out of SSH, or (b) wipe Docker's
iptables chains and kill **all** container networking. Read plan §4a before touching it. Prove
it on a **throwaway scratch host** with a full rebuild-and-diff before it ever touches prod.

## Guards baked in
1. **Double-gated.** Requires `enable_phase2=true` **and** `firewall_apply=true`.
2. **Never auto-generates a filter table over Docker.** In production use **mode A**: set
   `firewall_rules_v4_raw` / `firewall_rules_v6_raw` to the box's real `iptables-save` output
   (from `bin/discover.sh`), so Docker's `nat`/`DOCKER*` chains are preserved verbatim.
3. **Pre-apply assertions** confirm the candidate ruleset contains the `tailscale0` interface,
   the SSH allow, and a `:DOCKER` chain (unless `firewall_allow_no_docker: true`).
4. **Auto-revert timer.** Before applying, it snapshots last-known-good and arms a
   `systemd-run` timer that restores it in `firewall_autorevert_seconds` (default 60). If the
   apply locks us out, the confirmation `ping` task can't run, the timer is never cancelled,
   and the good rules come back automatically. Your way back in is Tailscale (`100.66.37.58`).

## Modes
- **Mode A (production):** provide `firewall_rules_v4_raw`/`_v6_raw`. Preserves Docker chains.
- **Mode B (scratch only):** no raw ruleset → emits a minimal host-INPUT-only table with no
  Docker chains. Allowed only when `firewall_allow_no_docker: true`.

## Proving it (do this first, on scratch)
```bash
ansible-playbook playbooks/site.yml -l scratch --tags firewall \
  -e enable_phase2=true -e firewall_apply=true -e firewall_allow_no_docker=true
# Confirm: still reachable; second run = 0 changes; rebuild-and-diff clean (plan §8.3).
```

## `--check` warning
`--check` is **not** reliable for this role (command/shell tasks). Do not trust a prod
`--check` diff here — prove on scratch (plan §4a).
