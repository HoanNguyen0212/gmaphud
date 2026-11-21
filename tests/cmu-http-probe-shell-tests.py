#!/usr/bin/env python3
from __future__ import annotations

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "diagnostics/usb-probe/layout/var/jb/usr/local/bin/gmaphud-cmu-http-probe"
BODY = b"=== MAZDA CMU TELEMETRY LISTENER STATUS ===\nport=8889\n"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        self.send_response(200)
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)

    def log_message(self, format: str, *args: object) -> None:
        pass


def main() -> int:
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix="gmaphud-shell-probe-") as temp:
            output = Path(temp) / "diag.txt"
            result = subprocess.run(
                ["/bin/sh", str(HELPER), "--interface", "lo", "--host", "127.0.0.1",
                 "--port", str(server.server_port), "--path", "/diag/all",
                 "--output", str(output), "--timeout-ms", "1500"],
                text=True, capture_output=True, timeout=10, check=False,
            )
            assert result.returncode == 0, result.stdout + result.stderr
            assert output.read_bytes() == BODY
            print("rootless_python_ipv4_probe: PASS")
    finally:
        server.shutdown()
        thread.join(timeout=2)
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
