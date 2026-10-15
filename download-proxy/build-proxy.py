#!/usr/bin/env python3
"""Build only the proxy and static redirects; never upload the package checkout."""
import json
import argparse
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--static-only', action='store_true', help='Build the quota fallback for a preview branch')
args = parser.parse_args()
root = Path(__file__).resolve().parent
output = root / ('pages-fallback-check' if args.static_only else 'pages-output')
output.mkdir(exist_ok=True)
if not args.static_only:
    (output / '_worker.js').write_text((root / 'worker.mjs').read_text())
(output / '_redirects').write_text(
    '/__fallback/* https://bechou0410.github.io/gmaphud/:splat 307\n'
    '/* https://bechou0410.github.io/gmaphud/:splat 307\n'
)
(output / '_routes.json').write_text(json.dumps({
    'version': 1, 'include': ['/*'],
    'exclude': ['/*'] if args.static_only else ['/__fallback/*'],
}) + '\n')
print('Built proxy with static fallback redirects in ' + str(output))
