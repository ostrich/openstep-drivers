#!/usr/bin/env python3
"""Run portable checks without an SDK or VM, storing outputs under work/."""
import ast
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'work/checks'
OUT.mkdir(parents=True, exist_ok=True)


def run(command):
    subprocess.run(command, cwd=ROOT, check=True)


for path in (p for name in ('vmtablet', 'vmwarefb', 'virtio', 'tcp-buffers', 'eide-busmaster') for p in (ROOT/name).rglob('*')):
    if not path.is_file() or '__pycache__' in path.parts:
        continue
    if path.suffix == '.py':
        ast.parse(path.read_text(), filename=str(path))
    elif path.suffix == '.sh':
        run(['sh', '-n', str(path)])
    elif path.suffix in ('.m', '.c', '.h'):
        for name in re.findall(r'^\s*#\s*include\s*"([^"]+)"', path.read_text(), re.M):
            assert (path.parent / name).is_file(), f'{path}: missing include {name}'
for entry in json.loads((ROOT / 'manifest.json').read_text())['components']:
    for key in ('root', 'build', 'package', 'distribute'):
        assert (ROOT / entry[key]).exists(), f'{entry["name"]}: missing {key}'
for path in [ROOT/'README.md', *ROOT.joinpath('docs').glob('*.md'), *(p for name in ('vmtablet', 'vmwarefb', 'virtio', 'tcp-buffers', 'eide-busmaster') for p in (ROOT/name).rglob('README.md'))]:
    for target in re.findall(r'\]\(([^)]+)\)', path.read_text()):
        if not target.startswith(('https:', 'http:', '#')):
            assert (path.parent / target.split('#')[0]).exists(), f'{path}: broken link {target}'
cc = os.environ.get('CC', 'cc')
for name, inputs in [
    ('queue-test', ['virtio/src/split-queue.c', 'virtio/tests/queue-test.c']),
    ('framebuffer-policy', ['vmwarefb/tests/policy-tests.c']),
]:
    output = OUT / name
    run([cc, '-std=gnu89', '-Wall', '-Wextra', '-Werror', *inputs, '-o', str(output)])
    run([str(output)])
if sys.platform == 'linux':
    output = OUT / 'native-dma-test'
    run([cc, '-std=gnu89', '-Wall', '-Wextra', '-Werror', '-Wno-deprecated',
         '-Wno-pointer-to-int-cast', '-Wno-int-to-pointer-cast',
         '-Ivirtio/tests/native-dma-stubs', 'virtio/tests/native-dma-test.c',
         '-o', str(output)])
    run([str(output)])
run(['python3', 'scripts/check-host-clients.py'])
run(['python3', 'eide-busmaster/test-package.py'])
print('Portable source, build-input and protocol checks passed')
