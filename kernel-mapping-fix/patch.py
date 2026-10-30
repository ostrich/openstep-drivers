#!/usr/bin/env python3
"""Create a separate OPENSTEP 4.2 Intel kernel with ordered TLB invalidation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile

ORIGINAL_SHA256 = '33469393c0843fc741942c3ae9d91d838467d72abd647dcf2e5bf499a3f14890'
BASE = 0x100000
STUB_ADDRESS = 0x101000
TEXT_START = 0x1012d0


def branch(opcode, address, target):
    return bytes([opcode]) + struct.pack('<i', target - address - 5)


def build(input_bytes, work):
    if hashlib.sha256(input_bytes).hexdigest() != ORIGINAL_SHA256:
        raise ValueError('Unsupported kernel: exact original OPENSTEP 4.2 Intel image required')
    source = Path(__file__).with_name('invalidation.S')
    obj, elf, raw = [work / ('stubs.' + suffix) for suffix in ('o', 'elf', 'bin')]
    subprocess.run(['as', '--32', str(source), '-o', str(obj)], check=True)
    subprocess.run(['ld', '-m', 'elf_i386', '-Ttext=' + hex(STUB_ADDRESS),
                    '-e', 'flush_removed_ptes', str(obj), '-o', str(elf)], check=True)
    subprocess.run(['objcopy', '-O', 'binary', '--only-section=.text', str(elf), str(raw)], check=True)
    symbols = {}
    for line in subprocess.check_output(['nm', '-n', str(elf)], text=True).splitlines():
        fields = line.split()
        if len(fields) == 3:
            symbols[fields[2]] = int(fields[0], 16)
    code = raw.read_bytes()
    off = STUB_ADDRESS - BASE
    if not code or STUB_ADDRESS + len(code) > TEXT_START:
        raise ValueError('Stub exceeds verified executable padding')
    if any(input_bytes[off:off + len(code)]):
        raise ValueError('Expected executable padding is occupied')
    edits = [
        (0x18fa65, bytes.fromhex('89f28b1df0'), branch(0xe9, 0x18fa65, 0x18faf3),
         'Skip pmap_remove invalidation before PTE changes'),
        (0x18fa33, bytes.fromhex('e858150000'), branch(0xe8, 0x18fa33, symbols['flush_removed_ptes']),
         'Invalidate cleared PTEs before deallocating mappings'),
        (0x19104d, bytes.fromhex('8b038b4b04'), branch(0xe9, 0x19104d, symbols['flush_retired_table']),
         'Invalidate cleared PDEs before page-table reuse'),
    ]
    data = bytearray(input_bytes)
    records = []
    for address, before, after, purpose in edits:
        pos = address - BASE
        if input_bytes[pos:pos + len(before)] != before:
            raise ValueError('Original instructions differ at ' + hex(address))
        data[pos:pos + len(after)] = after
        records.append(dict(address=hex(address), before=before.hex(), after=after.hex(), purpose=purpose))
    data[off:off + len(code)] = code
    disassembly = subprocess.check_output(['objdump', '-d', str(elf)], text=True)
    record = dict(original_sha256=ORIGINAL_SHA256, patched_sha256=hashlib.sha256(data).hexdigest(),
                  assembly_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  stub_address=hex(STUB_ADDRESS), stub_bytes=code.hex(), edits=records,
                  symbols={k: hex(symbols[k]) for k in ('flush_removed_ptes', 'flush_retired_table')})
    return bytes(data), record, disassembly


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('original', type=Path)
    p.add_argument('output', type=Path, help='New file; existing files are never overwritten')
    p.add_argument('--record', type=Path, required=True, help='New JSON build record')
    args = p.parse_args()
    if args.output.resolve() == args.record.resolve():
        p.error('Kernel output and JSON record must be different files')
    if args.output.exists() or args.record.exists():
        p.error('Output or record already exists; choose new paths')
    try:
        original = args.original.read_bytes()
        with tempfile.TemporaryDirectory(prefix='os42-tlb-') as tmp:
            patched, record, disassembly = build(original, Path(tmp))
        with args.output.open('xb') as f:
            f.write(patched)
            f.flush()
            os.fsync(f.fileno())
        args.output.chmod(args.original.stat().st_mode & 0o777)
        with args.record.open('x') as f:
            json.dump(record, f, indent=2)
            f.write('\n')
        print('Created', args.output)
        print('SHA-256:', record['patched_sha256'])
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        p.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
