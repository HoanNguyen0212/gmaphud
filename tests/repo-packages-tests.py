"""Validate the published dual-architecture repository and immutable artifacts."""
import bz2
import gzip
import hashlib
import lzma
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
raw = (root / 'docs/Packages').read_bytes()
records = [dict(line.split(': ', 1) for line in block.splitlines() if ': ' in line)
           for block in raw.decode().strip().split('\n\n')]
assert {r['Architecture'] for r in records} == {'iphoneos-arm', 'iphoneos-arm64'}
assert len(records) == 2 and len({r['Version'] for r in records}) == 1
for r in records:
    package = root / 'docs' / r['Filename']
    data = package.read_bytes()
    assert len(data) == int(r['Size'])
    assert hashlib.sha256(data).hexdigest() == r['SHA256']
    assert subprocess.check_output(['dpkg-deb', '-f', str(package), 'Architecture'], text=True).strip() == r['Architecture']
for suffix, decode in [('gz', gzip.decompress), ('bz2', bz2.decompress), ('xz', lzma.decompress)]:
    assert decode((root / f'docs/Packages.{suffix}').read_bytes()) == raw
assert 'Architectures: iphoneos-arm iphoneos-arm64' in (root / 'docs/Release').read_text()
# Reject incomplete input without rewriting the repository.
assert subprocess.run([sys.executable, str(root / 'build-repo.py'), str(package)], capture_output=True).returncode != 0
print('Dual-architecture package indexes and artifacts passed')
