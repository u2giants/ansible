# dev_windows

Reconciles a Windows 11 developer computer over OpenSSH/Tailscale. After three
bootstrap packages, the canonical AI DevOps WinGet Configuration owns packages;
the role list is a compatibility fallback only. This role owns the Tailscale-only SSH firewall and delegates Albert's
skills, dotfiles, SSH aliases/keys, and MCP wiring to the versioned `ai-devops`
installer. Set `dev_apply_secrets=true` only when the controller has a scoped
`OP_SERVICE_ACCOUNT_TOKEN`; task output is suppressed.
