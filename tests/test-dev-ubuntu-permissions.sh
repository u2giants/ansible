#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tasks="$root/roles/dev_ubuntu/tasks/main.yml"

grep -Fq 'Restore the managed user'"'"'s ownership of the AI DevOps checkout' "$tasks"
grep -Fq 'path: "{{ dev_ubuntu_repo_path }}"' "$tasks"
grep -Fq 'owner: "{{ ansible_user }}"' "$tasks"
grep -Fq 'group: "{{ ansible_user }}"' "$tasks"
grep -Fq 'recurse: true' "$tasks"

python3 - "$tasks" <<'PY'
import sys, yaml
tasks = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
by_name = {task["name"]: task for task in tasks}
for name in ("Clone or update AI DevOps", "Install AI DevOps command links"):
    assert by_name[name].get("become") is False, f"{name} must run as the managed user"
print("PASS: Ubuntu checkout ownership and unprivileged Git/install are enforced")
PY
