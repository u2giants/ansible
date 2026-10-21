#!/usr/bin/env python3
"""TLS front for the Z-code / Headroom lane (tailnet only).

Z.ai client signing requires an HTTPS baseURL. Headroom itself is plain HTTP
on the Tailscale interface. This process terminates TLS and routes:

  /api/paas/*  -> https://api.z.ai   (client signing handshake; keep path)
  everything   -> http://127.0.0.1:8788  (headroom-zcode compression lane)

Bound to the Tailscale IP only. Not a public endpoint.
"""

from __future__ import annotations

import http.client
import ssl
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LISTEN_HOST = "100.66.37.58"
LISTEN_PORT = 8443
CERT_FILE = "/etc/ai-zcode-headroom/tls/server-chain.crt"
KEY_FILE = "/etc/ai-zcode-headroom/tls/server.key"

HANDSHAKE_PREFIX = "/api/paas/"
HANDSHAKE_HOST = "api.z.ai"
HANDSHAKE_PORT = 443

HEADROOM_HOST = "100.66.37.58"
HEADROOM_PORT = 8788

HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "host",
}


class ProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "zcode-headroom-tls/1.0"

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _read_body(self) -> bytes:
        if "chunked" in self.headers.get("Transfer-Encoding", "").lower():
            parts = []
            while True:
                size = int(self.rfile.readline().split(b";", 1)[0].strip() or b"0", 16)
                if size == 0:
                    while self.rfile.readline() not in (b"\r\n", b"\n", b""):
                        pass  # discard trailers
                    return b"".join(parts)
                parts.append(self.rfile.read(size))
                self.rfile.readline()  # CRLF after each chunk
        length = self.headers.get("Content-Length")
        if not length:
            return b""
        n = int(length)
        if n <= 0:
            return b""
        return self.rfile.read(n)

    def _forward(self) -> None:
        body = self._read_body()
        path = self.path
        if path.startswith(HANDSHAKE_PREFIX):
            host, port, use_tls = HANDSHAKE_HOST, HANDSHAKE_PORT, True
        else:
            host, port, use_tls = HEADROOM_HOST, HEADROOM_PORT, False

        headers = {}
        for key, value in self.headers.items():
            if key.lower() in HOP_BY_HOP:
                continue
            headers[key] = value
        headers["Host"] = f"{host}:{port}" if use_tls else f"{host}:{port}"
        if body:
            headers["Content-Length"] = str(len(body))

        if use_tls:
            conn = http.client.HTTPSConnection(
                host,
                port,
                timeout=180,
                context=ssl.create_default_context(),
            )
        else:
            conn = http.client.HTTPConnection(host, port, timeout=180)

        try:
            conn.request(self.command, path, body=body or None, headers=headers)
            resp = conn.getresponse()
            self.send_response_only(resp.status, resp.reason)
            for key, value in resp.getheaders():
                if key.lower() in HOP_BY_HOP:
                    continue
                self.send_header(key, value)
            no_body = (
                self.command == "HEAD"
                or resp.status in (204, 304)
                or 100 <= resp.status < 200
            )
            has_length = "content-length" in {k.lower() for k, _ in resp.getheaders()}
            if no_body:
                self.end_headers()
            elif not has_length:
                # read1 returns as soon as bytes arrive, so SSE events stream
                # through instead of waiting for an 8 KiB buffer to fill.
                self.send_header("Transfer-Encoding", "chunked")
                self.end_headers()
                while True:
                    chunk = resp.read1(8192)
                    if not chunk:
                        self.wfile.write(b"0\r\n\r\n")
                        break
                    self.wfile.write(f"{len(chunk):x}\r\n".encode() + chunk + b"\r\n")
                    self.wfile.flush()
            else:
                self.end_headers()
                while True:
                    chunk = resp.read1(8192)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
            self.wfile.flush()
        except Exception as exc:  # noqa: BLE001 - surface proxy failure to client
            try:
                payload = f"upstream error: {exc}\n".encode()
                self.send_response(502, "Bad Gateway")
                self.send_header("Content-Type", "text/plain")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            except Exception:
                pass
        finally:
            conn.close()

    def do_GET(self) -> None:
        self._forward()

    def do_POST(self) -> None:
        self._forward()

    def do_PUT(self) -> None:
        self._forward()

    def do_PATCH(self) -> None:
        self._forward()

    def do_DELETE(self) -> None:
        self._forward()

    def do_HEAD(self) -> None:
        self._forward()

    def do_OPTIONS(self) -> None:
        self._forward()


def main() -> int:
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(CERT_FILE, KEY_FILE)
    httpd = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), ProxyHandler)
    httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
    sys.stderr.write(
        f"zcode-headroom-tls listening on https://{LISTEN_HOST}:{LISTEN_PORT}\n"
    )
    httpd.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
