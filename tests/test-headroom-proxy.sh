#!/usr/bin/env bash
# Exercise the headroom_proxy TLS front and PERF recorder against local fakes.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILES="$REPO_ROOT/roles/headroom_proxy/files"
work="$(mktemp -d)"; trap 'kill $(jobs -p) 2>/dev/null || true; rm -rf "$work"' EXIT
cd "$work"
openssl req -x509 -newkey rsa:2048 -nodes -keyout k.pem -out c.pem -days 1 -subj /CN=127.0.0.1 2>/dev/null
cat > up.py <<'EOF'
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path == "/cut":
            self.send_response(200); self.send_header("Content-Length", "100"); self.end_headers()
            self.wfile.write(b"partial"); self.wfile.flush(); self.close_connection = True
        elif self.path == "/sse":
            self.send_response(200); self.send_header("Content-Type", "text/event-stream")
            self.send_header("Connection", "close"); self.end_headers()
            for i in range(3):
                self.wfile.write(f"data: {i}\n\n".encode()); self.wfile.flush(); time.sleep(1)
            self.close_connection = True
        else:
            self.send_response(204); self.end_headers()
    def do_HEAD(self):
        self.send_response(204); self.end_headers()
    def do_POST(self):
        b = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        n = len(self.headers.get_all("Content-Length") or [])
        out = b + f"|cl={n}".encode()
        self.send_response(200); self.send_header("Content-Length", str(len(out))); self.end_headers()
        self.wfile.write(out)
ThreadingHTTPServer(("127.0.0.1", 18788), H).serve_forever()
EOF
sed -e 's/^LISTEN_HOST = .*/LISTEN_HOST = "127.0.0.1"/; s/^LISTEN_PORT = .*/LISTEN_PORT = 18443/' \
    -e 's#^CERT_FILE = .*#CERT_FILE = "c.pem"#; s#^KEY_FILE = .*#KEY_FILE = "k.pem"#' \
    -e 's/^HEADROOM_HOST = .*/HEADROOM_HOST = "127.0.0.1"/; s/^HEADROOM_PORT = .*/HEADROOM_PORT = 18788/' \
    -e 's/    timeout = 300 /    timeout = 3 /' "$FILES/zcode_headroom_tls.py" > front.py
grep -q 'timeout = 3 ' front.py
python3 -I up.py & python3 -I front.py 2>/dev/null &
for _ in $(seq 50); do curl -sk -o /dev/null https://127.0.0.1:18443/empty && break; read -t 0.2 <> <(:) || true; done

# SSE events must arrive as they are produced, not all at the end.
mapfile -t times < <(curl -sk -N https://127.0.0.1:18443/sse | while IFS= read -r l; do
  [[ -n "$l" ]] && date +%s.%N; done)
[[ ${#times[@]} -eq 3 ]]
python3 -c "import sys; t=[float(x) for x in sys.argv[1:]]; assert t[2]-t[0] > 1.5, t" "${times[@]}"

[[ "$(curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1:18443/empty)" == 204 ]]
[[ "$(curl -sk -I -o /dev/null -w '%{http_code}' https://127.0.0.1:18443/empty)" == 204 ]]
[[ "$(printf 'hello' | curl -sk -H 'Transfer-Encoding: chunked' --data-binary @- https://127.0.0.1:18443/echo)" == 'hello|cl=1' ]]
[[ "$(curl -sk -H 'content-length: 5' --data-binary 'abcde' https://127.0.0.1:18443/echo)" == 'abcde|cl=1' ]]

python3 -I - <<'EOF'
import socket, ssl
ctx = ssl._create_unverified_context()
# Upstream dies mid-body: exactly one status line, no trailing 502, then EOF.
s = ctx.wrap_socket(socket.create_connection(("127.0.0.1", 18443)), server_hostname="x")
s.settimeout(8); s.sendall(b"GET /cut HTTP/1.1\r\nHost: x\r\n\r\n")
got = b""
while True:
    d = s.recv(4096)
    if not d:
        break
    got += d
assert got.count(b"HTTP/1.1 ") == 1 and b"502" not in got and b"partial" in got, got
EOF

python3 -I - <<'EOF'
import socket, ssl
ctx = ssl._create_unverified_context()
def first_line(req, wait=8):
    s = ctx.wrap_socket(socket.create_connection(("127.0.0.1", 18443)), server_hostname="x")
    s.settimeout(wait); s.sendall(req)
    return s.recv(200).split(b"\r\n")[0]
pre = b"POST /e HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n"
for body in (b"zz\r\nab\r\n0\r\n\r\n", b"-5\r\nab\r\n0\r\n\r\n", b"ffffffffffffffff\r\nab\r\n", b"20\r\nshort"):
    assert first_line(pre + body) == b"HTTP/1.1 400 Bad Request", body
EOF

# PERF recorder: headroom 0.41 line with extra and reordered fields.
python3 -I - "$FILES/record.py" <<'EOF'
import sys
src = open(sys.argv[1]).read()
ns = {}; exec(src[src.index('import csv'):src.index('rows = {}')], ns)
line = ("2026-10-21 07:23:25,622 - headroom.proxy - INFO - [hr_1_2] PERF model=m msgs=9 "
        "tok_before=10 tok_after=8 tok_saved=2 tok_inflated=0 tool_saved=5 cache_read=7 "
        "cache_write=1 cache_hit_pct=100 opt_ms=3 transforms=a:b c:d client=x")
r = ns['parse'](line)
assert r and r['tok_saved'] == '2' and r['cache_read'] == '7' and r['transforms'] == 'a:b', r
old = ("2026-10-19 07:23:25,622 - headroom.proxy - INFO - [hr_3_4] PERF model=m msgs=9 "
       "tok_before=10 tok_after=8 tok_saved=2 cache_read=7 cache_write=1 cache_hit_pct=100 "
       "transforms=a:b")
r = ns['parse'](old)
assert r and r['reqid'] == 'hr_3_4' and r['cache_write'] == '1' and r['transforms'] == 'a:b', r
assert ns['parse']("2026-10-21 07:23:25,622 - x - INFO - [hr_1_2] PERF model=m msgs=1") is None
EOF
echo "PASS: headroom TLS front streams, frames, de-chunks and rejects bad bodies; PERF recorder parses 0.41"
