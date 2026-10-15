#!/usr/bin/env python3
"""Run GMapHUD checks, retain local logs and print a compact local summary."""
import argparse
from collections import Counter
from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent
STORAGE = Path.home() / ".config/gmaphud/checks"
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
MAX_EVENTS = 40
MAX_CHUNK = 8192
# Fixed diagnostic codes summarize the log; raw messages stay in the private local log.
PATTERNS = [
    (r"assertion.*failed|assertionerror|\bFAIL: |\bFAILED \(|\b[1-9]\d* failed\b", "assertion_failed"),
    (r"(?:fatal error:|error:).*file not found|no such file or directory|cannot find -l|library not found|no rule to make target", "missing_input"),
    (r"command not found|: (?:clang|make|python3|xcrun): not found|unable to find utility|invalid developer|sdk.*(?:not found|cannot|invalid)|unknown target|unsupported (?:architecture|option)", "toolchain_unavailable"),
    (r"use of undeclared identifier|undeclared \(first use", "undeclared_identifier"),
    (r"error:.*expected |syntaxerror:|syntax error|parse error", "syntax_error"),
    (r"incompatible|no (?:member|known class|visible @interface)|property .*not found|too (?:few|many) arguments|unrecognized selector|cannot (?:convert|initialize)|conflicting types", "type_or_api_mismatch"),
    (r"undefined symbols?|undefined reference|duplicate symbols?|linker command failed", "link_failed"),
    (r"(?:dpkg-deb|dpkg|ldid|codesign).*error|no space left on device|permission denied", "packaging_or_access_error"),
    (r"segmentation fault|bus error|abort trap|killed:|terminated by signal", "process_signal"),
]
RULES = [(re.compile(pattern, re.IGNORECASE), kind) for pattern, kind in PATTERNS]
DIAGNOSTIC = re.compile(r"^(.*?):(\d+)(?::\d+)?:\s*(fatal error|error|warning|note):")
MARKER = re.compile(r"\b(?:error|warning|fatal|failed|exception|traceback|assertion)\b", re.IGNORECASE)


def private_write(path, text):
    """Atomic private file; never follows an existing destination symlink."""
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, tmp = tempfile.mkstemp(prefix=".check-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def project_files(root):
    """Map compiler paths, including disposable Theos copies, to known project code files."""
    by_name = {}
    for folder in (root, root / "common", root / "provider", root / "tests", root / "tweak", root / "tweak/prefs"):
        for path in folder.glob("*"):
            if path.suffix in (".m", ".mm", ".h", ".c", ".x", ".py", ".sh") and path.is_file():
                relative = path.relative_to(root).as_posix()
                if re.fullmatch(r"[A-Za-z0-9_./-]{1,120}", relative):
                    by_name.setdefault(path.name, []).append(relative)
    return by_name


def extract_log(path, root=ROOT):
    files = project_files(root)
    events, counts = [], Counter()
    total_lines = clipped = 0
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        while True:
            line = handle.readline(MAX_CHUNK)
            if not line:
                break
            total_lines += 1
            if len(line) == MAX_CHUNK and not line.endswith("\n"):
                clipped += 1
                # Drop the remainder, rather than interpret a fragment as a new diagnostic.
                while line and not line.endswith("\n"):
                    line = handle.readline(MAX_CHUNK)
                continue
            line = ANSI.sub("", line).strip()
            kind = next((kind for pattern, kind in RULES if pattern.search(line)), None)
            if not kind and not MARKER.search(line):
                continue
            diagnostic = DIAGNOSTIC.match(line)
            severity = diagnostic[3] if diagnostic else ("warning" if re.search(r"\bwarning\b", line, re.I) else "error")
            severity = "error" if severity == "fatal error" else severity
            counts[severity] += 1
            event = {"log_line": total_lines, "severity": severity, "kind": kind or "unrecognized_diagnostic"}
            if diagnostic:
                matches = files.get(Path(diagnostic[1]).name, [])
                if len(matches) == 1:
                    event["project_file"] = matches[0]
                    event["source_line"] = int(diagnostic[2])
            # Keep early causes and the last cascades; never silently pretend evidence is complete.
            events.append(event)
            if len(events) > MAX_EVENTS:
                del events[MAX_EVENTS // 2]
    return {"diagnostics": events, "counts": dict(counts), "log_lines": total_lines,
            "omitted_diagnostics": sum(counts.values()) - len(events), "oversized_lines_skipped": clipped}


def stop_owned_group(process):
    """Allow cleanup, then reap descendants even if their parent already exited."""
    try:
        os.killpg(process.pid, signal.SIGTERM)
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            process.poll()
            os.killpg(process.pid, 0)
            time.sleep(0.05)
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


@contextmanager
def handle_interrupts():
    def interrupted(*_):
        raise KeyboardInterrupt

    handlers = {sig: signal.signal(sig, interrupted) for sig in (signal.SIGTERM, signal.SIGHUP)}
    try:
        yield
    finally:
        for sig, handler in handlers.items():
            signal.signal(sig, handler)


def execute(command, cwd, log_path, timeout):
    env = os.environ.copy()
    env["GMAPHUD_CHECK_RUNNING"] = "1"
    started = time.monotonic()
    reason = "exit"
    with handle_interrupts():
        with log_path.open("xb") as log:
            os.chmod(log_path, 0o600)
            process = None
            try:
                process = subprocess.Popen(command, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                           stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                while True:
                    remaining = timeout - (time.monotonic() - started)
                    if remaining <= 0:
                        raise subprocess.TimeoutExpired(command, timeout)
                    try:
                        status = process.wait(timeout=min(30, remaining))
                        break
                    except subprocess.TimeoutExpired:
                        if time.monotonic() - started >= timeout:
                            raise
                        print("GMapHUD: build/test vẫn đang chạy…", flush=True)
            except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
                reason = "timeout" if isinstance(error, subprocess.TimeoutExpired) else "interrupted"
                # This session owns the subprocess group, never the user's other tools/apps.
                saved = {sig: signal.signal(sig, signal.SIG_IGN) for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT)}
                try:
                    if process is not None:
                        stop_owned_group(process)
                finally:
                    for sig, handler in saved.items():
                        signal.signal(sig, handler)
                status = 124 if reason == "timeout" else 130
    return (128 - status if status < 0 else status), round(time.monotonic() - started, 3), reason


def finish(task, exit_code, duration, reason, directory, root=ROOT):
    log = directory / "full.log"
    evidence = extract_log(log, root)
    state = {"task": task, "exit_code": exit_code, "reason": reason, "evidence": evidence}
    private_write(directory / "evidence.json", json.dumps(state, ensure_ascii=False, indent=2) + "\n")
    passed = exit_code == 0
    lines = [f"{'PASS' if passed else 'FAIL'} {task} · exit {exit_code} · {duration:.1f}s · "
             f"{evidence['counts'].get('warning', 0)} warning(s)"]
    if not passed:
        if reason != "exit":
            lines.append(f"Lệnh bị dừng ({reason}); kiểm tra timeout hoặc tín hiệu trước khi chạy lại.")
        for event in [item for item in evidence["diagnostics"] if item["severity"] == "error"][:5]:
            location = f" {event['project_file']}:{event['source_line']}" if "project_file" in event else ""
            lines.append(f"L{event['log_line']}: {event['kind']}{location}")
    if evidence["omitted_diagnostics"] or evidence["oversized_lines_skipped"]:
        lines.append("Bằng chứng đã rút gọn; cần đọc log gốc khi điều tra.")
    lines.append(f"Log đầy đủ: {log}")
    brief = "\n".join(lines) + "\n"
    raw_bytes = log.stat().st_size
    metrics = {"exit_code": exit_code, "duration_seconds": duration, "raw_log_bytes": raw_bytes,
               "brief_bytes": len(brief.encode()), "output_byte_reduction_percent":
               round(100 * (1 - len(brief.encode()) / raw_bytes), 2) if raw_bytes else None,
               "note": "Output bytes only; not measured agent quota savings."}
    private_write(directory / "metrics.json", json.dumps(metrics, ensure_ascii=False, indent=2) + "\n")
    private_write(directory / "brief.txt", brief)
    print(brief, end="", flush=True)
    return exit_code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("task", choices=("test", "source-test", "build"))
    parser.add_argument("scheme", nargs="?", choices=("all", "rootless", "rootful"))
    parser.add_argument("--timeout", type=int, default=900)
    args = parser.parse_args()
    if args.timeout < 1 or args.timeout > 7200:
        parser.error("timeout must be 1..7200 seconds")
    if args.task != "build" and args.scheme:
        parser.error("scheme is only for build")
    command = ["sh", str(ROOT / {"test": "test.sh", "source-test": "test-source-output.sh", "build": "build-tweak.sh"}[args.task])]
    if args.task == "build":
        command.append(args.scheme or "all")
    STORAGE.mkdir(parents=True, exist_ok=True, mode=0o700)
    STORAGE.chmod(0o700)
    directory = Path(tempfile.mkdtemp(prefix=time.strftime("%Y%m%d-%H%M%S-") + args.task + "-", dir=STORAGE))
    print(f"GMapHUD: chạy {args.task}; đang lưu log riêng…", flush=True)
    try:
        status, duration, reason = execute(command, ROOT, directory / "full.log", args.timeout)
    except OSError:
        print("Không khởi chạy được build/test.", file=sys.stderr)
        return 127
    with handle_interrupts():
        try:
            return finish(args.task, status, duration, reason, directory)
        except (Exception, KeyboardInterrupt):
            print(f"Không tạo được tóm tắt; giữ exit {status}. Log tại {directory / 'full.log'}", file=sys.stderr)
            return status


if __name__ == "__main__":
    raise SystemExit(main())
