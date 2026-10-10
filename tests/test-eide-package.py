#!/usr/bin/env python3
"""Ensure native wrapper metadata cannot hide a missing or unsafe payload."""
import hashlib
import importlib.util
import io
import tarfile
import unittest
from pathlib import Path
from unittest.mock import patch

path = Path(__file__).resolve().parents[1] / 'components/eide-busmaster/distribute-package.py'
spec = importlib.util.spec_from_file_location('eide_distribution', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
BASE = 'private/Drivers/i386/EIDE.config/'


def payload(extra=None, empty=False):
    out = io.BytesIO()
    entries = [('.', None, 0, 20)]
    if not empty:
        entries += [(BASE+'EIDE_reloc', b'patched', 0, 0),
                    (BASE+'EIDE_reloc.original', b'original', 0, 0)]
    if extra:
        entries.append(extra)
    with tarfile.open(fileobj=out, mode='w') as tar:
        for name, data, uid, gid in entries:
            info = tarfile.TarInfo(name); info.uid=uid; info.gid=gid
            info.type = tarfile.DIRTYPE if data is None else tarfile.REGTYPE
            info.size = len(data) if data else 0
            tar.addfile(info, io.BytesIO(data) if data is not None else None)
    return out.getvalue()


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.patches = [patch.object(module, 'PATCHED', hashlib.sha256(b'patched').hexdigest()),
                        patch.object(module, 'ORIGINAL', hashlib.sha256(b'original').hexdigest())]
        for item in self.patches: item.start()
    def tearDown(self):
        for item in self.patches: item.stop()
    def test_native_root_wrapper(self):
        self.assertEqual(len(module.validate_payload(payload())), 2)
    def test_empty_package(self):
        with self.assertRaisesRegex(AssertionError, 'Missing EIDE'):
            module.validate_payload(payload(empty=True))
    def test_payload_file_ownership(self):
        with self.assertRaises(AssertionError):
            module.validate_payload(payload((BASE+'bad', b'x', 0, 20)))
    def test_duplicate(self):
        with self.assertRaisesRegex(AssertionError, 'Duplicate'):
            module.validate_payload(payload((BASE+'EIDE_reloc', b'patched', 0, 0)))
    def test_traversal(self):
        with self.assertRaises(AssertionError):
            module.validate_payload(payload((BASE+'../bad', b'x', 0, 0)))
    def test_unrelated_file(self):
        with self.assertRaises(AssertionError):
            module.validate_payload(payload(('etc/bad', b'x', 0, 0)))


if __name__ == '__main__': unittest.main()
