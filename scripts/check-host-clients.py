#!/usr/bin/env python3
"""Check host client protocols and real PTY lifecycle behavior without guest builds."""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
for name in ('agent-client-test.py', 'pty-client-test.py', 'pty-terminal-test.py'):
    subprocess.run([sys.executable, str(ROOT / 'virtio/tests' / name)], cwd=ROOT, check=True)
print('Host client protocol and terminal checks passed')
