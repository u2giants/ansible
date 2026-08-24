# AI DevOps toolkit protected-checkout verification

Date: 2026-08-24

This record verifies the privilege branch added by the same commit as this
file. The test ran inside WSL Ubuntu as root so it could create a disposable
UID-1000 managed user, make the test checkout root-owned, and then execute the
runtime portions of the role as that non-root user.

## Privilege integration test

Command:

```bash
wsl.exe -d Ubuntu -u root -- bash -lc \
  "cd /mnt/c/repos/ansible/ansible && \
  AI_TOOLKIT_ROOT_INTEGRATION=1 bash tests/test-ai-devops-toolkit.sh"
```

Result: exit 0.

```text
PASS: AI DevOps toolkit cutover, protected ownership, partial-release upgrade, and idempotence are recoverable
```

The test proves all of the following in a disposable filesystem:

- the governed checkout converges to `root:<managed-user-group>` mode `0750`;
- a committed symlink from the checkout to a sibling directory is not followed,
  and the sibling's owner, group, mode, and content remain unchanged;
- the managed runtime user can read the checkout but cannot create a file in it;
- the simulated installer runs as the managed runtime user and fails if it can
  write into the source checkout;
- an interrupted installation retains the protected ownership contract;
- a retry completes and the following run is idempotent;
- the former same-user path remains covered when root/passwordless sudo is not
  available to the test harness.

## Repository validation

Commands:

```bash
ANSIBLE_CONFIG=/mnt/c/repos/ansible/ansible/ansible.cfg \
  ansible-playbook playbooks/site.yml --syntax-check
ANSIBLE_CONFIG=/mnt/c/repos/ansible/ansible/ansible.cfg ansible-lint
```

Results: both exited 0. Lint reported only the repository's accepted
`command-instead-of-module` warning for the existing Cloudflare tunnel
`systemctl` validation task.
