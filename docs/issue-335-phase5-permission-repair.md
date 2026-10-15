# Issue 335 Phase 5 Ubuntu permission repair

On 2026-09-11, Albert Hazan explicitly authorized the Ansible-managed repair
for `/worksp/ai-devops` and its normal serialized application. The authorized
action is limited to returning that checkout to the managed Ubuntu user so Git
can fetch the landed Phase 5 source. The shared `/worksp` parent and sibling
repositories remain out of scope.

This is the separate post-authorization policy change required by the local
task-gate overlay: declared infrastructure work may reach the exact serialized
production workflow after the matching central policy release lands. The repair
runs only through the `dev_ubuntu_ai_devops` tag against the declared `vps2`
inventory host; routine Phase 1 remains unchanged.

Verification requires the focused ownership test, Ansible lint and syntax
checks, the read-only host diff, one exact-head final review, and live proof that
user `ai` can fetch the checkout after the managed apply.
