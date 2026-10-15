#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tasks="$root/roles/dev_ubuntu/tasks/main.yml"
apply="$root/.github/workflows/apply.yml"
check="$root/.github/workflows/check.yml"
inventory="$root/inventory/hosts.ini"

grep -Fq 'Restore the managed user'"'"'s ownership of the AI DevOps checkout' "$tasks"
grep -Fq 'path: "{{ dev_ubuntu_repo_path }}"' "$tasks"
grep -Fq 'owner: "{{ ansible_user }}"' "$tasks"
grep -Fq 'group: "{{ ansible_user }}"' "$tasks"
grep -Fq 'recurse: true' "$tasks"
grep -Fq 'vps2 ansible_host=100.66.37.58 ansible_user=ai' "$inventory"
grep -Fq 'if [ "$tags" = "dev_ubuntu_ai_devops" ]; then' "$apply"
grep -Fq 'playbooks/dev-computers.yml -l vps2' "$apply"
grep -Fq -- '--tags dev_ubuntu_ai_devops -e dev_ai_repo_branch=origin/main' "$apply"
grep -Fq 'playbooks/dev-computers.yml -l vps2' "$check"

python3 - "$tasks" <<'PY'
import sys, yaml
tasks = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
by_name = {task["name"]: task for task in tasks}
for name in ("Clone or update AI DevOps", "Install AI DevOps command links"):
    assert by_name[name].get("become") is False, f"{name} must run as the managed user"
    assert "dev_ubuntu_ai_devops" in by_name[name].get("tags", []), f"{name} must be in the scoped apply"
verify = by_name["Verify the AI DevOps checkout repair and installation"]
assert verify.get("become") is False
assert "dev_ubuntu_ai_devops" in verify.get("tags", [])
print("PASS: Ubuntu checkout ownership and unprivileged Git/install are enforced")
PY
