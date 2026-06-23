# Cloud-Init first-boot bootstrap (plan §5.4)

`user-data.yaml.j2` makes a fresh **Hetzner Cloud** box reachable by CI with no manual steps:
creates the `ai` user with passwordless sudo + the CI public key, installs Python 3, installs
Tailscale and joins the tailnet (`tag:ci`, `--ssh`). After first boot the box is code-defined
from second zero.

## Render & use (secret stays out of git)
```bash
TS_AUTHKEY="$(op read op://vibe_coding/ts-ci-ephemeral/credential)" \
CI_PUBKEY="$(op read op://vibe_coding/ci-deploy-ssh/public_key)" \
  envsubst < user-data.yaml.j2 > user-data.yaml.rendered
# pass user-data.yaml.rendered as the server's user-data at provision time, then delete it.
```
`.gitignore` excludes `*.rendered` and `user-data.yaml` — never commit a rendered file; it
contains the Tailscale auth key.

## Caveat
Hetzner **dedicated/Robot** servers use `installimage` + a post-install script, not cloud-init.
Confirm which product `hetz` is (plan §5.4). Universal fallback: a one-shot `bootstrap.sh` from
a laptop.
