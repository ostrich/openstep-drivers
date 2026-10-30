#!/usr/bin/env python3
"""Exercise boot-registration behavior only against isolated temporary files."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE=Path(__file__).with_name('module')/'configure-guest.sh'

class ConfigureTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        self.table=self.root/'System.config/Instance0.table';self.table.parent.mkdir()
        self.original='"Other" = "keep";\n"Boot Drivers" = "PCI EIDE VirtioNet";\n'
        self.table.write_text(self.original)
        self.installed=self.root/'installed';self.installed.mkdir()
        (self.installed/'KernelMappingFix_reloc').write_bytes(b'module')
        (self.installed/'Instance0.table').write_text('"Apply Mapping Fix" = "Yes";\n')
        self.active=self.root/'active'
        auth=self.root/'whoami';auth.write_text('#!/bin/sh\necho root\n');auth.chmod(0o755)
        s=SOURCE.read_text().replace('table=/usr/Devices/System.config/Instance0.table','table='+str(self.table)).replace('installed=/private/Drivers/i386/KernelMappingFix.config','installed='+str(self.installed)).replace('active=/usr/Devices/KernelMappingFix.config','active='+str(self.active)).replace('/usr/ucb/whoami',str(auth))
        self.script=self.root/'configure';self.script.write_text(s)
    def tearDown(self):self.tmp.cleanup()
    def run_mode(self,mode):return subprocess.run(['/bin/sh',str(self.script),mode],capture_output=True,text=True)
    def test_enable_idempotent_backup(self):
        for _ in range(2):self.assertEqual(self.run_mode('enable').returncode,0)
        text=self.table.read_text();self.assertIn('"KernelMappingFix PCI EIDE VirtioNet"',text)
        self.assertEqual(text.count('KernelMappingFix'),1)
        self.assertEqual(self.table.with_name('Instance0.table.before-kernel-mapping-fix').read_text(),self.original)
        self.assertEqual((self.active/'KernelMappingFix_reloc').read_bytes(),b'module')
    def test_disable_preserves_other_drivers(self):
        self.assertEqual(self.run_mode('enable').returncode,0)
        self.assertEqual(self.run_mode('disable').returncode,0)
        self.assertEqual(self.table.read_text(),self.original)
    def test_status_changes_nothing(self):
        before=sorted(str(p.relative_to(self.root)) for p in self.root.rglob('*'))
        r=self.run_mode('status');self.assertEqual(r.returncode,0);self.assertEqual(r.stdout,'disabled for next boot\n')
        self.assertEqual(before,sorted(str(p.relative_to(self.root)) for p in self.root.rglob('*')))
    def test_bad_format_preserved(self):
        for text in ['"Other" = "yes";\n',self.original+self.original]:
            self.table.write_text(text);self.assertNotEqual(self.run_mode('enable').returncode,0);self.assertEqual(self.table.read_text(),text)
    def test_different_active_driver_refused(self):
        self.active.mkdir();(self.active/'KernelMappingFix_reloc').write_bytes(b'other')
        self.assertNotEqual(self.run_mode('enable').returncode,0)
        self.assertEqual(self.table.read_text(),self.original)
        self.assertEqual((self.active/'KernelMappingFix_reloc').read_bytes(),b'other')
    def test_unknown_mode(self):self.assertEqual(self.run_mode('unknown').returncode,2)

unittest.main()
