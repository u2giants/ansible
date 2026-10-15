#!/usr/bin/env bash
set -eu
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
defaults="$root/roles/dev_tools/defaults/main.yml"
tasks="$root/roles/dev_tools/tasks/main.yml"
readme="$root/roles/dev_tools/README.md"

grep -Fq 'ast_grep_version: "0.45.2"' "$defaults"
grep -Fq 'ast_grep_install_prefix: "/opt/ast-grep"' "$defaults"
grep -Fq 'name: "@ast-grep/cli"' "$tasks"
grep -Fq 'version: "{{ ast_grep_version }}"' "$tasks"
grep -Fq 'global: false' "$tasks"
grep -Fq '@ast-grep/cli-linux-x64-gnu/ast-grep' "$tasks"
grep -Fq 'dest: /usr/local/bin/ast-grep' "$tasks"
grep -Fq 'path: /usr/bin/sg' "$tasks"
grep -Fq 'dpkg-query -S /usr/bin/sg' "$tasks"
grep -Fq "ansible_facts['architecture'] == 'x86_64'" "$tasks"
grep -Fq "ansible_facts['distribution'] == 'Ubuntu'" "$tasks"
if grep -Eq 'dest: .*/sg$|global: true.*ast-grep|@ast-grep/cli@latest' "$tasks" "$defaults" "$readme"; then
  echo 'FAIL: ast-grep role shadows sg, installs globally, or uses latest' >&2
  exit 1
fi
grep -Fq '/opt/ast-grep' "$readme"
grep -Fq 'never installed globally' "$readme"
echo 'PASS: isolated ast-grep role contract'
