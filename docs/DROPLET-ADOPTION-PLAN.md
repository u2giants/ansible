# Droplet adoption plan — bring the DO backup-wiz droplet under Ansible

**Issue:** [u2giants/ansible#10](https://github.com/u2giants/ansible/issues/10)
**Written:** 2026-08-23 · **Status:** plan only, nothing executed yet

---

## 1. What the droplet is

A DigitalOcean droplet running the **Restore Wizard** — the web app at
`backup.designflow.app` that shows whether the backups are healthy and performs restores.
It is the *monitor* side of the backup system; the *producer* (the Backrest instance that
actually makes the backups) runs on `hetz`.

| Fact | Value |
|---|---|
| Tailscale IP | `100.94.183.1` (SSH alias `backupwiz` / `wiz`) |
| Public IP | `167.172.245.66` |
| OS | Ubuntu 24.04.3 LTS, Python 3.12.3 |
| Disk | 8.7 GB total — small, and that matters (see §3.4) |
| RAM / swap | 458 MB + a 2 GB `/swapfile` |
| Login | `root` only; no non-root users exist |
| Containers | `restore-wizard`, `backrest` (read-only mirror), `cloudflared` |
| App dir | `/opt/restore-wizard` (compose file, `.env`, `ssh/`) |
| Code repo | `u2giants/backrest-wiz` |
| Deploy today | GitHub Actions `deploy.yml` → `appleboy/ssh-action` → `secrets.DEPLOY_HOST` |

**Why adopt it.** The mission (`docs/DISASTER-RECOVERY.md`) is that the owner says "rebuild
everything" and remembers nothing. The droplet is currently outside that: not rebuildable
from code, not drift-checked, host settings applied by hand. The 2026-08-23 disk-full
incident is the symptom — see §3.4.

---

## 2. Where things stand today

- `inventory/hosts.ini` has `[do_backup_wiz]` as a **commented-out placeholder** ("folded in
  later, plan §2.3"). Nothing in this repo touches the droplet.
- The droplet's own playbook lives in **`u2giants/backrest-wiz/ansible/playbook.yml`**. It is
  idempotent and reasonable — installs Docker from the official apt repo, renders `.env` and
  the Hetzner SSH key from vaulted vars, brings the stack up, and (as of PR #4) installs the
  journald cap and weekly Docker prune. **It has never been run against the live droplet.**
  Its README says so explicitly.
- `setup-droplet.sh` (the imperative predecessor) is still in the repo and still physically
  present at `/opt/restore-wizard/setup-droplet.sh` on the box.

---

## 3. The four real obstacles

These are the things that will bite, in the order they will bite. None is a blocker; each
needs a deliberate decision.

### 3.1 CI cannot reach the droplet yet

This repo's `apply.yml` authenticates with the **`ci-deploy-ssh`** key from 1Password
(`op://vibe_coding/ci-deploy-ssh/private_key`) and reaches hosts over an ephemeral
`tag:ci` Tailscale node.

The droplet's `/root/.ssh/authorized_keys` contains exactly **two** keys — commented
`916-alien` and `albt16`. The CI key is **not** among them. Tailscale is up on the droplet
(`100.94.183.1`), so the network path exists; only the key is missing.

*Also unresolved:* `backrest-wiz`'s own `deploy.yml` authenticates with a different secret
(`DEPLOY_SSH_KEY`) that must already correspond to one of those two keys. Which one, and
whether it is the personal `916-alien` key, needs checking before anything is rotated —
removing the wrong key breaks app deploys.

### 3.2 `site.yml` is Hetzner-shaped and must not be pointed at the droplet

`playbooks/site.yml` applies `coolify`, `cloudflared_coolify`, `backrest_watchdog`,
`retired_platform_cleanup`, `memory_sync_containment` and more. Several of those are
meaningful only on `hetz`, and some would actively damage the droplet (`cloudflared_coolify`
manages a *different* tunnel; the droplet runs its own cloudflared **as a container**, not a
host unit).

Running `site.yml -l do_backup_wiz` is therefore **not** the adoption path. The droplet needs
its own playbook that composes a deliberately chosen subset of roles.

### 3.3 The droplet has no non-root user and no firewall

`hetz` is managed as `ansible_user=ai` with `ssh_hardening` and `firewall` roles. The droplet
has neither: root-only login, and `ufw` is not active. Adopting it *as-is* (root user, no
firewall) is honest and safe; adopting it *and* hardening it in the same change is where
lockout risk lives. Those are two separate phases on purpose (§4).

### 3.4 The 8.7 GB disk is the standing hazard

On 2026-08-23 the disk hit **98.6%**. None of it was backup data — backups go to DO Spaces
correctly. It was ~2.6 GB of stale containerd image layers from four months of redeploys,
816 MB of buildkit cache, a 384 MB uncapped journal, and 733 MB of old Claude Code CLI
versions under `/root/.claude/remote`.

Fixed in `u2giants/backrest-wiz` **PR #4** (merged): a 100 MB journald cap and a weekly
`docker-prune.timer`, applied to the live box with byte-identical contents. Disk is now 68%.

**Consequence for this plan:** those two guards are the first thing that must survive the
port into this repo, and the droplet's own playbook is currently their only home. Whichever
repo ends up owning them, exactly one must — two copies will fight.

---

## 4. The plan, in phases

Each phase is independently valuable and independently revertible. Do not merge phases.

### Phase D0 — Prove the existing playbook (do this first, changes nothing here)

**Where:** `u2giants/backrest-wiz`, from a control node that can reach the droplet.

1. `ansible-playbook -i inventory.ini ansible/playbook.yml --syntax-check`
2. `--check --diff` against the live droplet. Expect diffs: the box was built by
   `setup-droplet.sh`, not by this playbook.
3. Read every reported diff and decide, per item, whether the playbook or the box is right.
   Known drift to expect: `/opt/restore-wizard` still holds app source (`server.js`, `src/`,
   `public/`, `login.html`, `package.json`) and a `docker-compose.yml.bak` left by the old
   script — the playbook does not manage any of it.
4. Only then run it for real, in a window where a broken Restore Wizard is acceptable.

**You'll know it worked when:** a second consecutive run reports `changed=0`, all three
containers are up, and `https://backup.designflow.app` returns 200.

⚠️ **Do not skip to D1.** Adopting an unproven playbook into the serialized CI pipeline means
the first real test happens on a merge to `main`, unattended.

### Phase D1 — Give CI a way in

**Where:** this repo + the droplet.

1. Confirm which private key `backrest-wiz`'s `DEPLOY_SSH_KEY` secret holds, and which
   `authorized_keys` entry it matches. Write the answer down.
2. Add the **`ci-deploy-ssh`** public key to the droplet's `/root/.ssh/authorized_keys`
   *additively* — never replace the file.
3. Verify from a `tag:ci`-tagged node that `ssh root@100.94.183.1` succeeds with that key.

**You'll know it worked when:** a `workflow_dispatch` dry run of `apply.yml` (auto-apply
still off for this host) reaches the droplet and gathers facts.

⚠️ Removing either existing key before step 1 is answered can break app deploys **and** the
owner's own access. Add only; remove nothing in this phase.

### Phase D2 — Inventory + a droplet-only playbook

**Where:** this repo.

1. Uncomment and fill in `[do_backup_wiz]` in `inventory/hosts.ini`:
   `backup-wiz ansible_host=100.94.183.1 ansible_user=root`
   (Tailscale IP, matching how `hetz` is addressed. INI reminder already in that file: never
   put a `#` comment after a `key=value`.)
2. Add `inventory/group_vars/do_backup_wiz.yml` for droplet-specific vars.
3. Add **`playbooks/droplet.yml`** — a *separate* entrypoint, `hosts: do_backup_wiz`,
   composing only roles that genuinely apply. Start deliberately small:
   - `apt_repos` (Docker's official repo — the droplet already uses it)
   - `base`, `packages` (audit their task lists for hetz-only assumptions first)
   - a **new `backup_wiz` role** holding the droplet's host layer, ported from
     `backrest-wiz/ansible/playbook.yml`: Docker engine install, the journald cap, and the
     weekly `docker-prune` timer.
   Explicitly **excluded** for now: `coolify`, `cloudflared_coolify`, `backrest_watchdog`,
   `firewall`, `ssh_hardening`, `users`, `memory_sync_containment`,
   `retired_platform_cleanup`. Write the exclusions as a comment in the playbook so a later
   session does not "helpfully" add them back.
4. Extend `check.yml` to lint the new playbook.

**Scope boundary, unchanged:** Ansible owns the droplet's *host* layer. The Restore Wizard
*containers* stay owned by `backrest-wiz`'s `deploy.yml`. Do not let the new role run
`docker compose up` — that is the reconcile loop this repo's `AGENTS.md` forbids.

**You'll know it worked when:** `ansible-playbook playbooks/droplet.yml --check --diff`
reports no unexpected changes and `changed=0` on a second real run.

### Phase D3 — Wire it into CI

**Where:** `.github/workflows/`.

1. Add a droplet apply step to `apply.yml` (or a sibling `apply-droplet.yml`) under its own
   `concurrency: apply-droplet` group — **not** shared with `apply-hetzner`, so a droplet
   apply can never queue behind or interleave with a Hetzner apply.
2. Gate it on its own repo variable (e.g. `ENABLE_DROPLET_AUTO_APPLY`), default **off**, so
   merging the code does not immediately start applying.
3. Run it manually via `workflow_dispatch` several times until boring, then flip the variable on.
4. Add the droplet to `drift.yml` so it gets the same config and software-inventory drift
   detection `hetz` has.

**You'll know it worked when:** a no-op merge to `main` produces a green droplet apply
reporting `changed=0`, and the drift job reports the droplet clean.

### Phase D4 — Retire the duplicates

**Where:** both repos, only after D3 is boring.

1. Delete `setup-droplet.sh` from `backrest-wiz` and from `/opt/restore-wizard/` on the box.
2. Reduce `backrest-wiz/ansible/playbook.yml` to app-deploy concerns only (or delete it),
   leaving the host layer solely here. Update `backrest-wiz/AGENTS.md`, whose host-policy
   banner will then finally be true for this droplet.
3. Update `docs/RECOVERY-GAP-PLAN.md` and `docs/RUNBOOK-REBUILD.md` to cover rebuilding the
   droplet.

**You'll know it worked when:** `docs/RUNBOOK-REBUILD.md` describes a droplet rebuild end to
end and the host layer is defined in exactly one place.

---

## 5. Deliberately out of scope

- **Hardening** (firewall, `ssh_hardening`, a non-root `ai` user). Worth doing, but as its
  own change with the owner present — lockout on a remote box with no console is the risk.
- **Resizing the droplet.** With the §3.4 guards in place, 8.7 GB is adequate. Revisit only
  if disk climbs past ~80% with the guards running.
- **The producer side** (`backrest_producer` role for `hetz`) — that is
  `backrest-wiz`'s legacy handoff Phase B4.1, a separate workstream.
- **Backup secrets into 1Password** (restic password, DO Spaces keys, currently plaintext in
  `/opt/restore-wizard/.env`) — Phase B4.3 there. Related, but not a prerequisite.

---

## 6. Owner decisions — ANSWERED 2026-08-23, do not re-ask

1. **Adopt as root, or create a non-root `ai` user first?** → **Adopt as root now, harden
   later.** Phase D2's inventory line is therefore `ansible_user=root`.
2. **Auto-apply on merge, or manual dispatch only?** → **Manual dispatch until three
   consecutive clean runs, then flip to automatic.**
   *Who does the "manual" part:* an **AI session**, via
   `gh workflow run apply-droplet.yml`. The owner never clicks anything — "manual" here means
   *not triggered by a merge*, not *done by a human*. Schedule: three dispatches on three
   separate days during Phase D3, then set `ENABLE_DROPLET_AUTO_APPLY=true`.
3. **After D4, delete `backrest-wiz/ansible/playbook.yml` or keep it?** → **Keep it, stripped
   to app-deploy concerns only.**
4. **Phase D0 requires running the never-tested playbook against the live droplet, risking a
   few minutes of Restore Wizard downtime (backups unaffected).** → **Approved.**

Recorded by the session that wrote this plan; owner answers given 2026-08-23.
