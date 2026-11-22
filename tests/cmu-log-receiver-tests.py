#!/usr/bin/env python3
"""Host-side end-to-end tests for native gmaphud-cmu-log-receiver.c."""
from __future__ import annotations

import hashlib
import http.client
import json
import os
import shutil
import socket
import subprocess
import tempfile
import time
import unittest
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "diagnostics/cmureceiver/gmaphud-cmu-log-receiver.c"


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def post_chunk(port: int, payload: bytes, *, session="boot", filename="cmu_listener.log",
               inode=4900, offset=0, sha_override: str | None = None) -> tuple[int, dict]:
    digest = sha_override if sha_override is not None else hashlib.sha256(payload).hexdigest()
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    headers = {
        "Content-Type": "text/plain",
        "Content-Length": str(len(payload)),
        "X-CMU-Session": session,
        "X-CMU-File": filename,
        "X-CMU-Inode": str(inode),
        "X-CMU-Offset": str(offset),
        "X-CMU-SHA256": digest,
        "X-CMU-Rotated": "0",
        "Connection": "close",
    }
    conn.request("POST", "/api/v1/cmu-logs/chunk", body=payload, headers=headers)
    resp = conn.getresponse()
    raw = resp.read().decode("utf-8", errors="replace")
    conn.close()
    return resp.status, json.loads(raw)


class NativeCMULogReceiverTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="gmaphud-receiver-test-"))
        self.bin = self.tmp / "gmaphud-cmu-log-receiver"
        cc = shutil.which("cc") or shutil.which("clang") or shutil.which("gcc")
        assert cc is not None, "C compiler required for receiver host test"
        res = subprocess.run(
            [cc, "-Wall", "-Wextra", "-Werror", "-O2", str(SRC), "-o", str(self.bin)],
            capture_output=True,
            text=True,
        )
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_chunk_append_idempotency_errors_and_manifest(self):
        data_root = self.tmp / "auto-sessions"
        port = free_port()
        env = os.environ.copy()
        env.update({
            "GVM_CMU_PUSH_ROOT": str(data_root),
            "GVM_CMU_PUSH_PORT": str(port),
            "GVM_CMU_PUSH_TEST_MODE": "1",
            "GVM_CMU_PUSH_BIND": "127.0.0.1",
            "GVM_CMU_PUSH_RETENTION_DAYS": "7",
        })
        proc = subprocess.Popen([str(self.bin)], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            status_file = data_root / "receiver-status.txt"
            deadline = time.time() + 5.0
            while time.time() < deadline:
                if status_file.exists() and "state=listening" in status_file.read_text():
                    break
                time.sleep(0.05)
            self.assertTrue(status_file.exists() and "state=listening" in status_file.read_text())

            # 1. First valid chunk
            c1 = b"[07:57:01] RX: LIMIT 50\n"
            code, body = post_chunk(port, c1, session="../evil/boot", filename="cmu_listener.log", inode=4900, offset=0)
            self.assertEqual(code, 200)
            self.assertEqual(body["ack_offset"], len(c1))
            self.assertEqual(body["sha256"], hashlib.sha256(c1).hexdigest())

            # 2. Idempotent retry of same chunk
            code, body = post_chunk(port, c1, session="../evil/boot", filename="cmu_listener.log", inode=4900, offset=0)
            self.assertEqual(code, 200)
            self.assertEqual(body["ack_offset"], len(c1))

            # 3. Second contiguous chunk
            c2 = b"[07:57:05] RX: NAV 3 200 Duy Tan\n"
            code, body = post_chunk(port, c2, session="../evil/boot", filename="cmu_listener.log", inode=4900, offset=len(c1))
            self.assertEqual(code, 200)
            self.assertEqual(body["ack_offset"], len(c1) + len(c2))

            # 4. Offset gap -> 409 Conflict
            code, body = post_chunk(port, b"gap\n", session="../evil/boot", filename="cmu_listener.log", inode=4900, offset=999)
            self.assertEqual(code, 409)
            self.assertEqual(body["error"], "offset-gap")

            # 5. SHA-256 mismatch -> 400 Bad Request
            code, body = post_chunk(port, b"bad\n", session="../evil/boot", filename="cmu_listener.log", inode=4900,
                                    offset=len(c1) + len(c2), sha_override="0" * 64)
            self.assertEqual(code, 400)
            self.assertEqual(body["error"], "sha256-mismatch")

            # Verify persisted bytes & path traversal sanitization
            day = datetime.now().strftime("%Y-%m-%d")
            saved = data_root / day / "cmu-push" / "unknown" / "cmu_listener.log.inode-4900"
            self.assertTrue(saved.exists(), f"expected {saved}")
            self.assertEqual(saved.read_bytes(), c1 + c2)

            manifest = data_root / day / "cmu-push" / "cmu-push-manifest.ndjson"
            lines = manifest.read_text().splitlines()
            self.assertEqual(len(lines), 3)
            self.assertIn("file=cmu_listener.log inode=4900 offset=0", lines[0])
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)
            if proc.stdout:
                proc.stdout.close()
            if proc.stderr:
                proc.stderr.close()


if __name__ == "__main__":
    unittest.main()
