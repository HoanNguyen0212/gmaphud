#!/usr/bin/env python3
"""Test interface-bound CMU HTTP probe against real loopback HTTP servers."""
from __future__ import annotations

import http.server
import os
from pathlib import Path
import platform
import socket
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "diagnostics/cmu-http-probe.c"
MARKER = b"=== MAZDA CMU TELEMETRY LISTENER STATUS ==="


class Handler(http.server.BaseHTTPRequestHandler):
    status = 200
    body = MARKER + b"\nSpeed Limit: 50 km/h\n"

    def do_GET(self) -> None:  # noqa: N802
        self.send_response(self.status)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(self.body)

    def log_message(self, format: str, *args: object) -> None:  # noqa: A002
        pass


class IPv6HTTPServer(http.server.ThreadingHTTPServer):
    address_family = socket.AF_INET6


def run_probe(binary: Path, interface: str, host: str, port: int, output: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(binary), "--interface", interface, "--host", host, "--port", str(port),
         "--path", "/diag/all", "--output", str(output), "--timeout-ms", "1500"],
        text=True, capture_output=True, timeout=5, check=False,
    )


def run_auto(binary: Path, port: int, output: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(binary), "--auto-usb", "--port", str(port), "--path", "/diag/all",
         "--output", str(output), "--timeout-ms", "1500"],
        text=True, capture_output=True, timeout=5, check=False,
    )


def serve(server: http.server.ThreadingHTTPServer) -> threading.Thread:
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    return worker


def stop(server: http.server.ThreadingHTTPServer, worker: threading.Thread) -> None:
    server.shutdown()
    worker.join(timeout=2)
    server.server_close()


def main() -> int:
    assert SOURCE.is_file(), f"missing helper source: {SOURCE}"
    loopback = "lo0" if platform.system() == "Darwin" else "lo"
    with tempfile.TemporaryDirectory(prefix="gmaphud-cmu-probe-test-") as td:
        temp = Path(td)
        binary = temp / "cmu-http-probe"
        compiled = subprocess.run(
            [os.environ.get("CC", "cc"), "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2",
             str(SOURCE), "-o", str(binary)], text=True, capture_output=True, timeout=30, check=False,
        )
        assert compiled.returncode == 0, compiled.stdout + compiled.stderr

        # A successful IPv4 request writes only the marker-validated response body.
        Handler.status, Handler.body = 200, MARKER + b"\nSpeed Limit: 50 km/h\n"
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        worker = serve(server)
        output = temp / "good-v4.txt"
        result = run_probe(binary, loopback, "127.0.0.1", server.server_port, output)
        stop(server, worker)
        assert result.returncode == 0, result.stdout + result.stderr
        assert output.read_bytes() == Handler.body
        assert "http_status=200" in result.stderr and f"interface={loopback}" in result.stderr
        print("test_bound_ipv4_fetches_listener_body: PASS")

        # A successful IPv6 request remains bound to the selected interface.
        try:
            server6 = IPv6HTTPServer(("::1", 0), Handler)
        except OSError as error:
            raise AssertionError(f"IPv6 loopback is required: {error}") from error
        worker6 = serve(server6)
        output6 = temp / "good-v6.txt"
        result6 = run_probe(binary, loopback, "::1", server6.server_port, output6)
        stop(server6, worker6)
        assert result6.returncode == 0, result6.stdout + result6.stderr
        assert output6.read_bytes() == Handler.body
        assert "transport=ipv6" in result6.stderr
        print("test_bound_ipv6_fetches_listener_body: PASS")

        # Reject non-200 and unrelated bodies without persisting them.
        Handler.status = 503
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        worker = serve(server)
        bad = temp / "bad-status.txt"
        result = run_probe(binary, loopback, "127.0.0.1", server.server_port, bad)
        stop(server, worker)
        assert result.returncode != 0 and not bad.exists() and "http_status=503" in result.stderr
        print("test_rejects_non_200: PASS")

        Handler.status, Handler.body = 200, b"unrelated service response\n"
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        worker = serve(server)
        unrelated = temp / "unrelated.txt"
        result = run_probe(binary, loopback, "127.0.0.1", server.server_port, unrelated)
        stop(server, worker)
        assert result.returncode != 0 and not unrelated.exists()
        assert "cmu_listener_marker_missing" in result.stderr
        print("test_rejects_non_cmu_200_body: PASS")

        # The Linux runner has a non-USB link-local interface; autodetection must reject it.
        missing = temp / "auto-usb.txt"
        result = run_auto(binary, 1, missing)
        assert result.returncode != 0 and not missing.exists()
        assert "usb_interface=" in result.stderr
        assert "result=success" not in result.stderr
        print("test_auto_usb_rejects_non_usb_link_local_interface: PASS")

        # Reject unknown, non-IPv4 interface and malformed target selections.
        for iface in ("gvm-interface-does-not-exist", "lo0-if-no-such-ipv4"):
            rejected = temp / f"{iface}.txt"
            result = run_probe(binary, iface, "127.0.0.1", 1, rejected)
            assert result.returncode != 0 and not rejected.exists()
            assert "not_active_ipv4" in result.stderr
        print("test_rejects_unknown_or_unusable_interface: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
