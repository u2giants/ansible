#!/usr/bin/env bash
# Pins the gated-dispatch invariants of apply.yml (docs/deployment.md).
set -euo pipefail
f="$(dirname "$0")/../.github/workflows/apply.yml"
python3 - "$f" <<'PY'
import sys, yaml
w = yaml.safe_load(open(sys.argv[1]))
on = w.get("on", w.get(True))
assert set(on) == {"workflow_dispatch"}, f"apply.yml must trigger only on workflow_dispatch: {list(on)}"
assert on["workflow_dispatch"]["inputs"]["sha"]["required"] is True, "sha input must be required"
steps = w["jobs"]["apply"]["steps"]
text = yaml.safe_dump(steps)
assert "refs/heads/main" in text, "must refuse non-main refs"
assert "[0-9a-f]{40}" in text and "git/ref/heads/main" in text, "must check sha is 40-hex and the main tip"
co = [s for s in steps if str(s.get("uses", "")).startswith("actions/checkout")]
assert co and all(s.get("with", {}).get("ref") == "${{ github.event.inputs.sha }}" for s in co), "checkout must pin sha"
PY
echo "PASS: apply.yml gated-dispatch invariants"
