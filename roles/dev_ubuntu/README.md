# dev_ubuntu

Reconciles an Ubuntu developer computer over Tailscale SSH. Apt owns packages;
the role installs OpenSSH, the owner public key, the AI DevOps toolkit, skills,
managed instructions, and optional 1Password-backed MCP/shell configuration.
The Hetz production `apt_repos` role is intentionally excluded because those
captured sources are not proven workstation-portable. Tailscale and `op` are
explicit bootstrap prerequisites.
