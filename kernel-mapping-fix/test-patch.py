#!/usr/bin/env python3
"""Host structural checks; pass the exact original kernel as the sole argument."""
import hashlib
import importlib.util
from pathlib import Path
import struct
import sys
import tempfile
import unittest

path = Path(sys.argv.pop(1))
spec = importlib.util.spec_from_file_location('kernel_patch', Path(__file__).with_name('patch.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class PatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = path.read_bytes()
        with tempfile.TemporaryDirectory() as tmp:
            cls.output, cls.record, cls.asm = m.build(cls.original, Path(tmp))

    def test_original_unchanged(self):
        self.assertEqual(path.read_bytes(), self.original)
        self.assertEqual(hashlib.sha256(self.original).hexdigest(), m.ORIGINAL_SHA256)

    def test_guard(self):
        bad = bytearray(self.original)
        bad[-1] ^= 1
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError):
                m.build(bytes(bad), Path(tmp))

    def test_only_declared_bytes_change(self):
        allowed = set()
        for edit in self.record['edits']:
            off = int(edit['address'], 16) - m.BASE
            allowed.update(range(off, off + len(bytes.fromhex(edit['after']))))
        off = m.STUB_ADDRESS - m.BASE
        allowed.update(range(off, off + len(bytes.fromhex(self.record['stub_bytes']))))
        self.assertEqual(len(self.original), len(self.output))
        self.assertTrue(all(i in allowed for i, (a, b) in enumerate(zip(self.original, self.output)) if a != b))

    def test_branch_targets(self):
        expected = [0x18faf3, int(self.record['symbols']['flush_removed_ptes'], 16),
                    int(self.record['symbols']['flush_retired_table'], 16)]
        for edit, target in zip(self.record['edits'], expected):
            address = int(edit['address'], 16)
            data = bytes.fromhex(edit['after'])
            self.assertEqual(address + 5 + struct.unpack('<i', data[1:])[0], target)

    def test_loader_headers_unchanged(self):
        self.assertEqual(self.original[:0x884], self.output[:0x884])
        self.assertEqual(self.original[0x12d0:0x8fa33], self.output[0x12d0:0x8fa33])

    def test_assembly_has_both_flush_sites(self):
        self.assertIn('<flush_removed_ptes>:', self.asm)
        self.assertIn('<flush_retired_table>:', self.asm)
        self.assertIn('190f90', self.asm)
        self.assertIn('191052', self.asm)
        self.assertIn('invlpg %fs:', self.asm)
        self.assertIn('pusha', self.asm)
        self.assertIn('popa', self.asm)


unittest.main()
