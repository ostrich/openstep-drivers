#!/usr/bin/env python3
"""Exercise the host client on a real Unix PTY, including restoration on failure."""
import fcntl
import os
import runpy
import select
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / 'virtio/tools/pty-client.py'
OUT = ROOT / 'work/virtio/agent'
OUT.mkdir(parents=True, exist_ok=True)
api = runpy.run_path(str(CLIENT))
encode, take = api['encode'], api['take']


class Tests(unittest.TestCase):
    def exercise(self, ending):
        with tempfile.TemporaryDirectory(dir=OUT) as directory:
            path = Path(directory) / 'terminal.sock'
            with socket.socket(socket.AF_UNIX) as listener:
                listener.bind(str(path))
                listener.listen(1)
                listener.settimeout(5)
                master, slave = os.openpty()
                process = None
                peer = None
                original = termios.tcgetattr(slave)
                flags = fcntl.fcntl(slave, fcntl.F_GETFL)
                buffer = bytearray()
                seen = []

                def packet():
                    deadline = time.monotonic() + 5
                    while True:
                        value = take(buffer)
                        if value:
                            seen.append(value)
                            if value[0] == 9:
                                if ending != 'silent-peer':peer.sendall(encode(10,value[1]))
                                continue
                            return value
                        peer.settimeout(max(.001, deadline - time.monotonic()))
                        data = peer.recv(4096)
                        if not data:
                            raise EOFError('Client disconnected before expected packet')
                        buffer.extend(data)

                try:
                    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
                    process = subprocess.Popen(
                        [sys.executable, str(CLIENT), '--socket', str(path), '--heartbeat-timeout', '2'],
                        stdin=slave, stdout=slave, stderr=slave,
                    )
                    peer, _ = listener.accept()
                    kind, hello = packet()
                    self.assertEqual(kind, 1)
                    peer.sendall(encode(2, hello[:8] + struct.pack('<I', 123)))
                    deadline = time.monotonic() + 5
                    while termios.tcgetattr(slave)[3] & termios.ECHO:
                        self.assertLess(time.monotonic(), deadline, 'Client did not enter raw mode')
                        self.assertIsNone(process.poll())
                        time.sleep(.005)
                    # These must cross the socket as bytes, not host signals.
                    os.write(master, b'\x03\x1a')
                    while True:
                        kind, body = packet()
                        if kind == 3:
                            self.assertEqual(body, b'\x03\x1a')
                            break
                    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 120, 0, 0))
                    process.send_signal(signal.SIGWINCH)
                    while True:
                        kind, body = packet()
                        if kind == 5 and struct.unpack('<HH', body) == (40, 120):
                            break
                    expected = 0
                    if ending == 'escape':
                        os.write(master, b'\x1d')
                    elif ending == 'signal':
                        process.send_signal(signal.SIGTERM)
                    elif ending == 'exit':
                        peer.sendall(encode(4, b'terminal output\r\n') + encode(7, struct.pack('<II', 7, 0)))
                        peer.close()
                        peer = None
                        expected = 7
                    elif ending == 'malformed':
                        peer.sendall(b'badmagic' + struct.pack('<II', 4, 0))
                        expected = 1
                    elif ending == 'disconnect':
                        peer.close()
                        peer = None
                        expected = 1
                    elif ending == 'silent-peer':
                        expected = 1
                    elif ending == 'idle-peer':
                        deadline=time.monotonic()+4
                        while time.monotonic()<deadline:
                            peer.settimeout(.1)
                            try:data=peer.recv(4096)
                            except socket.timeout:continue
                            self.assertTrue(data)
                            buffer.extend(data)
                            while True:
                                value=take(buffer)
                                if not value:break
                                seen.append(value);self.assertEqual(value[0],9)
                                peer.sendall(encode(10,value[1]))
                        self.assertIsNone(process.poll())
                        self.assertGreaterEqual(sum(kind==9 for kind,body in seen),2)
                        os.write(master,b'\x1d')
                    else:
                        raise AssertionError(ending)
                    self.assertEqual(process.wait(timeout=5), expected)
                    self.assertEqual(termios.tcgetattr(slave), original)
                    self.assertEqual(fcntl.fcntl(slave, fcntl.F_GETFL), flags)
                    if ending == 'exit':
                        output = bytearray()
                        while select.select([master], [], [], .05)[0]:
                            output.extend(os.read(master, 4096))
                        self.assertIn(b'terminal output', output)
                finally:
                    if process and process.poll() is None:
                        process.kill()
                        process.wait(timeout=5)
                    if peer:
                        peer.close()
                    os.close(master)
                    os.close(slave)

    def test_lifecycle_and_terminal_restoration(self):
        for ending in ('escape', 'signal', 'exit', 'malformed', 'disconnect','silent-peer','idle-peer'):
            with self.subTest(ending=ending):
                self.exercise(ending)


if __name__ == '__main__':
    unittest.main()
