# dev_ubuntu

Reconciles an Ubuntu developer computer over Tailscale SSH. Apt owns packages;
the role installs OpenSSH, the owner public key, the AI DevOps toolkit, skills,
managed instructions, and optional 1Password-backed MCP/shell configuration.
The Hetz production `apt_repos` role is intentionally excluded because those
captured sources are not proven workstation-portable. Tailscale and `op` are
explicit bootstrap prerequisites.

The managed user's checkout is recursively returned to that user before Git
runs, and both Git and the installer run without privilege escalation. This
repairs legacy root-owned Git objects without granting access to sibling
checkouts or changing the shared `/worksp` parent.
