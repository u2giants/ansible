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


# Largest request body accepted (prompts with long context stay far below this).
MAX_BODY = 64 * 1024 * 1024


class BadRequest(Exception):
    """Malformed or truncated client request body."""


class ProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    timeout = 300  # a client that stalls mid-request is dropped, not waited on forever
    server_version = "zcode-headroom-tls/1.0"

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _read_exact(self, n: int) -> bytes:
        data = self.rfile.read(n)
        if len(data) != n:
            raise BadRequest("request body truncated")
        return data

    def _read_body(self) -> bytes:
        if "chunked" in self.headers.get("Transfer-Encoding", "").lower():
            parts, total = [], 0
            while True:
                line = self.rfile.readline(1024)
                if not line.endswith(b"\n"):
                    raise BadRequest("truncated chunk size line")
                token = line.split(b";", 1)[0].strip()
                if not token or any(c not in b"0123456789abcdefABCDEF" for c in token) or len(token) > 8:
                    raise BadRequest("invalid chunk size")
                size = int(token, 16)
                if size == 0:
                    while True:  # discard trailers up to the blank line
                        trailer = self.rfile.readline(8192)
                        if not trailer.endswith(b"\n"):
                            raise BadRequest("truncated chunk trailer")
                        if trailer in (b"\r\n", b"\n"):
                            return b"".join(parts)
                total += size
                if total > MAX_BODY:
                    raise BadRequest("request body too large")
                parts.append(self._read_exact(size))
                if self.rfile.readline(3) not in (b"\r\n", b"\n"):
                    raise BadRequest("missing CRLF after chunk")
        length = self.headers.get("Content-Length")
        if not length:
            return b""
        if not length.strip().isdigit():
            raise BadRequest("invalid Content-Length")
        n = int(length)
        if n > MAX_BODY:
            raise BadRequest("request body too large")
        return self._read_exact(n) if n else b""

    def _reply(self, status: int, reason: str, text: str) -> None:
        payload = f"{text}\n".encode()
        self.send_response(status, reason)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(payload)
        self.close_connection = True

    def _forward(self) -> None:
        try:
            body = self._read_body()
        except (BadRequest, OSError) as exc:
            try:
                self._reply(400, "Bad Request", f"bad request: {exc}")
            except Exception:
                pass
            return
        path = self.path
        if path.startswith(HANDSHAKE_PREFIX):
            host, port, use_tls = HANDSHAKE_HOST, HANDSHAKE_PORT, True
        else:
            host, port, use_tls = HEADROOM_HOST, HEADROOM_PORT, False

        headers = {}
        for key, value in self.headers.items():
            if key.lower() in HOP_BY_HOP or key.lower() == "content-length":
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

        started = False  # True once the response headers have gone to the client
        try:
            conn.request(self.command, path, body=body or None, headers=headers)
            resp = conn.getresponse()
            self.send_response_only(resp.status, resp.reason)
            for key, value in resp.getheaders():
                if key.lower() in HOP_BY_HOP:
                    continue
                self.send_header(key, value)
            # http.client consumes interim 1xx itself; only these carry no body.
            no_body = self.command == "HEAD" or resp.status in (204, 304)
            has_length = "content-length" in {k.lower() for k, _ in resp.getheaders()}
            if no_body:
                self.end_headers()
                started = True
            elif not has_length:
                # read1 returns as soon as bytes arrive, so SSE events stream
                # through instead of waiting for an 8 KiB buffer to fill.
                self.send_header("Transfer-Encoding", "chunked")
                self.end_headers()
                started = True
                while True:
                    chunk = resp.read1(8192)
                    if not chunk:
                        self.wfile.write(b"0\r\n\r\n")
                        break
                    self.wfile.write(f"{len(chunk):x}\r\n".encode() + chunk + b"\r\n")
                    self.wfile.flush()
            else:
                self.end_headers()
                started = True
                expected = int(resp.getheader("Content-Length", "0") or 0)
                sent = 0
                while True:
                    chunk = resp.read(65536)
                    if not chunk:
                        break
                    try:
                        self.wfile.write(chunk)
                    except OSError:
                        # Client went away; not an upstream failure.
                        self.close_connection = True
                        return
                    sent += len(chunk)
                if sent < expected:
                    # http.client returns b"" on early EOF instead of raising.
                    raise http.client.IncompleteRead(b"", expected - sent)
            self.wfile.flush()
        except Exception as exc:  # noqa: BLE001 - surface proxy failure to client
            if started:
                # Mid-stream failure: a second status line would corrupt the
                # response, so drop the connection and let the client see EOF.
                self.log_error("mid-stream upstream failure on %s: %r", path.split("?", 1)[0], exc)
                self.close_connection = True
                return
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
