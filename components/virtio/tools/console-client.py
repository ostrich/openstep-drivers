#!/usr/bin/env python3
"""Bounded raw virtio-console echo client. Peer must run the matching byte-count echo."""
import argparse
import hashlib
import json
import os
import selectors
import socket
import stat
import time
from pathlib import Path


def echo_stream(peer, source, length, timeout=30):
    """Compare echoed bytes with exactly what was sent; retain at most 64 KiB.

    No replay or reconnect. Receipt here proves an echo, not file persistence.
    """
    if not 1 <= length <= 16777216 or not 0 < timeout <= 300:
        raise ValueError('Invalid byte count or deadline')
    deadline = time.monotonic() + timeout
    sent = received = 0
    pending = b''
    expected = bytearray()
    digest = hashlib.sha256()
    old_timeout = peer.gettimeout()
    peer.setblocking(False)
    selector = selectors.DefaultSelector()
    selector.register(peer, selectors.EVENT_READ | selectors.EVENT_WRITE)
    try:
        while received < length:
            if not pending and sent < length and len(expected) < 65536:
                pending = source.read(min(4096, length - sent, 65536 - len(expected)))
                if not pending:
                    raise EOFError('Input ended before requested byte count')
            mask = selectors.EVENT_READ | (selectors.EVENT_WRITE if pending else 0)
            selector.modify(peer, mask)
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f'Echo deadline: sent={sent}, received={received}; no replay')
            ready = selector.select(remaining)
            if not ready:
                raise TimeoutError(f'Echo deadline: sent={sent}, received={received}; no replay')
            for key, events in ready:
                if events & selectors.EVENT_WRITE and pending:
                    try:
                        count = peer.send(pending)
                        if not count:
                            raise EOFError('Peer stopped accepting output; no replay')
                    except BlockingIOError:
                        count = 0
                    if count:
                        expected.extend(pending[:count])
                        digest.update(pending[:count])
                        pending = pending[count:]
                        sent += count
                if events & selectors.EVENT_READ:
                    try:
                        data = peer.recv(4096)
                    except BlockingIOError:
                        continue
                    if not data:
                        raise EOFError(f'Peer closed: sent={sent}, received={received}; no replay')
                    if len(data) > len(expected) or data != expected[:len(data)]:
                        raise ValueError(f'Echo mismatch at byte {received}')
                    del expected[:len(data)]
                    received += len(data)
        if sent != length or expected or pending:
            raise ValueError('Transfer ended with incomplete state')
        return {'sent': sent, 'received': received, 'sha256': digest.hexdigest(),
                'exact_echo': True, 'replayed': False}
    finally:
        selector.close()
        peer.settimeout(old_timeout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--socket', type=Path, required=True)
    parser.add_argument('--input', type=Path, required=True, help='Stable regular file, 1 byte..16 MiB')
    parser.add_argument('--timeout', type=float, default=30)
    args = parser.parse_args()
    if not 0 < args.timeout <= 300:
        parser.error('Timeout must be greater than zero and at most 300 seconds')
    try:
        with args.input.open('rb') as source:
            metadata = os.fstat(source.fileno())
            if not 1 <= metadata.st_size <= 16777216:
                raise ValueError('Input size must be 1 byte..16 MiB')
            if not stat.S_ISREG(metadata.st_mode):
                raise ValueError('Input must be a regular file')
            with socket.socket(socket.AF_UNIX) as peer:
                peer.settimeout(args.timeout)
                peer.connect(str(args.socket))
                result = echo_stream(peer, source, metadata.st_size, args.timeout)
        print(json.dumps(result, indent=2))
    except (OSError, ValueError) as exc:
        parser.exit(1, str(exc) + '\n')


if __name__ == '__main__':
    main()
