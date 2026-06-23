# Role: `motd`  — [non-disruptive · phase1]

Prints a loud governance banner at every login so any human or AI session that lands on the box
is told — before doing anything — that the host is Ansible-managed and must not be hand-edited
(plan §6, "Document the rule loudly"). This is the on-box half of the agent-governance story;
the repo-side half is [`AGENTS.md`](../../AGENTS.md) / [`CLAUDE.md`](../../CLAUDE.md).

## What it does
- Writes `/etc/motd` (static banner).
- Installs `/etc/update-motd.d/99-ansible-managed` (a short dynamic hook that composes with
  Ubuntu's normal motd machinery).

## Why it's safe
Two files, no services touched. The worst case is a cosmetic login message.

## Configure
`motd_repo_url` (defaults to the repo URL) is shown in the banner.
