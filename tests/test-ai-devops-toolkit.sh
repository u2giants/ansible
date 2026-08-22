#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

managed_user="$(id -un)"
managed_group="$(id -gn)"
source_repo="$TMP_ROOT/source"
home_dir="$TMP_ROOT/home"
mkdir -p "$source_repo/bin" "$home_dir"

git -C "$source_repo" init -q -b main
git -C "$source_repo" config user.name test
git -C "$source_repo" config user.email test@example.invalid

cat > "$source_repo/install.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == --skip-secrets ]]
if [[ -f "$HOME/fail-next-install" ]]; then
  rm -f "$HOME/fail-next-install"
  exit 23
fi
printf '%s\n' install >> "$HOME/toolkit-test.log"
SCRIPT
cat > "$source_repo/bin/ai-install-skills" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == --adopt-globals ]]
printf '%s\n' globals >> "$HOME/toolkit-test.log"
SCRIPT
cat > "$source_repo/bin/ai-devops" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == doctor ]]
printf '%s\n' doctor >> "$HOME/toolkit-test.log"
SCRIPT
chmod +x "$source_repo/install.sh" "$source_repo/bin/ai-install-skills" "$source_repo/bin/ai-devops"
git -C "$source_repo" add .
git -C "$source_repo" commit -qm release
release="$(git -C "$source_repo" rev-parse HEAD)"

playbook="$TMP_ROOT/playbook.yml"
cat > "$playbook" <<YAML
---
- name: Test AI DevOps toolkit role
  hosts: localhost
  connection: local
  gather_facts: false
  become: false
  roles:
    - role: "$REPO_ROOT/roles/ai_devops_toolkit"
YAML

make_predecessor() {
  local path="$1"
  mkdir -p "$path"
  git -C "$path" init -q -b main
  git -C "$path" config user.name test
  git -C "$path" config user.email test@example.invalid
  printf '%s\n' predecessor > "$path/old.txt"
  git -C "$path" add old.txt
  git -C "$path" commit -qm predecessor
  git -C "$path" remote add origin "$source_repo"
  git -C "$path" rev-parse HEAD
}

run_role() {
  local target="$1" backup="$2" state="$3" predecessor="$4"
  ANSIBLE_CONFIG="$REPO_ROOT/ansible.cfg" ansible-playbook -i localhost, "$playbook" \
    -e "managed_user=$managed_user" \
    -e "ai_devops_toolkit_group=$managed_group" \
    -e ai_devops_toolkit_verify_memory_schedule=false \
    -e "ai_devops_toolkit_home=$home_dir" \
    -e "ai_devops_toolkit_state_dir=$state" \
    -e "ai_devops_toolkit_completion_marker=$state/$release.installed" \
    -e "ai_devops_toolkit_repo_url=$source_repo" \
    -e "ai_devops_toolkit_path=$target" \
    -e "ai_devops_toolkit_backup_path=$backup" \
    -e "ai_devops_toolkit_version=$release" \
    -e '{"ai_devops_toolkit_rewrite_predecessors":["'"$predecessor"'"]}'
}

target="$TMP_ROOT/worksp/ai-devops"
backup="$TMP_ROOT/worksp/backup"
state="$TMP_ROOT/state"
predecessor="$(make_predecessor "$target")"
run_role "$target" "$backup" "$state" "$predecessor" >/dev/null
[[ "$(git -C "$target" rev-parse HEAD)" == "$release" ]]
[[ "$(git -C "$target" branch --show-current)" == main ]]
[[ "$(git -C "$backup" rev-parse HEAD)" == "$predecessor" ]]
[[ -f "$state/$release.installed" ]]
[[ "$(cat "$home_dir/toolkit-test.log")" == $'install\nglobals\ndoctor' ]]
second="$(run_role "$target" "$backup" "$state" "$predecessor")"
grep -Eq 'changed=0' <<< "$second"

retry_target="$TMP_ROOT/retry/ai-devops"
retry_backup="$TMP_ROOT/retry/backup"
retry_state="$TMP_ROOT/retry-state"
retry_predecessor="$(make_predecessor "$retry_target")"
touch "$home_dir/fail-next-install"
if run_role "$retry_target" "$retry_backup" "$retry_state" "$retry_predecessor" >/dev/null 2>&1; then
  echo "FAIL: fail-once install unexpectedly succeeded" >&2
  exit 1
fi
[[ "$(git -C "$retry_target" rev-parse HEAD)" == "$release" ]]
[[ ! -e "$retry_state/$release.installed" ]]
run_role "$retry_target" "$retry_backup" "$retry_state" "$retry_predecessor" >/dev/null
[[ -f "$retry_state/$release.installed" ]]

echo "PASS: AI DevOps toolkit cutover is recoverable and idempotent"
