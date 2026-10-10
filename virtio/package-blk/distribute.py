#!/usr/bin/env python3
"""Validate the native VirtioBlk package and make an OPENSTEP-readable archive."""
import argparse,gzip,hashlib,io,json,subprocess,tarfile
from pathlib import Path
BASE=Path(__file__).resolve().parents[1]
if not __debug__:raise SystemExit('Run without -O; package validation must remain enabled')
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('package',type=Path);p.add_argument('archive',type=Path)
p.add_argument('--tested-driver',type=Path,required=True,help='Exact release binary verified by the guest tests')
p.add_argument('--firmware',type=Path,required=True,help='Verified self-contained VirtioBlk-firmware bundle')
p.add_argument('--source-manifest',type=Path,required=True,help='Source snapshot captured by the native package build')
a=p.parse_args()
if a.package.name!='VirtioBlk.pkg' or not a.archive.name.endswith('.tar.gz'):p.error('Expected VirtioBlk.pkg and output .tar.gz')
assert {x.name for x in a.package.iterdir()}=={'VirtioBlk.'+s for s in ('bom','info','sizes','tar.Z')}
assert all(x.is_file() and not x.is_symlink() for x in a.package.iterdir())
blob=subprocess.check_output(['zcat',str(a.package/'VirtioBlk.tar.Z')])
root='private/Drivers/i386/VirtioBlk.config/'
with tarfile.open(fileobj=io.BytesIO(blob)) as t:
 members=t.getmembers()
 assert all(m.uid==0 and m.gid==0 and (m.isfile() or m.isdir()) for m in members)
 assert all(not m.name.startswith('/') and '..' not in Path(m.name).parts for m in members)
 names=[m.name.removeprefix('./').rstrip('/') for m in members]
 assert len(names)==len(set(names)), 'Duplicate payload paths'
 files={m.name.removeprefix('./'):t.extractfile(m).read() for m in members if m.isfile()}
 assert set(files)=={root+n for n in ('Default.table','Instance0.table','English.lproj/Localizable.strings','VirtioBlk_reloc')}|{'usr/local/bin/virtio-blkctl'}
 for name,source in [('Default.table','Default.table'),('Instance0.table','Default.table'),('English.lproj/Localizable.strings','English.lproj/Localizable.strings')]:
  assert files[root+name]==(BASE/'VirtioBlk'/source).read_bytes()
 assert b'VirtioBlkTrace' not in files[root+'VirtioBlk_reloc'], 'Diagnostic logging binary must not be distributed'
 assert b'VirtioBlkTest' not in files[root+'VirtioBlk_reloc']
 assert b'VirtioBlk Test Failure' not in files[root+'VirtioBlk_reloc']
 assert b'VirtioBlkTestFaults' not in files[root+'VirtioBlk_reloc']
 assert b'VirtioBlkTestNextFault' not in files[root+'VirtioBlk_reloc']
 assert files[root+'VirtioBlk_reloc']==a.tested_driver.read_bytes(), 'Package driver differs from tested release'
 assert b'--test-completion' not in files['usr/local/bin/virtio-blkctl']
 assert b'--test-timeout' not in files['usr/local/bin/virtio-blkctl']
 assert b'--test-preflush' not in files['usr/local/bin/virtio-blkctl']
 assert next(m.mode for m in members if m.name.removeprefix('./')=='usr/local/bin/virtio-blkctl')&0o111
paths=[(x,'VirtioBlk.pkg/'+x.name) for x in sorted(a.package.iterdir())]
paths.append((BASE/'package-blk/README.txt','README.txt'))
paths.append((BASE/'package-blk/configure-guest.sh','configure-guest.sh'))
# Previously released bundles retain their original member name. New builds
# emit the normalized filename; accept exactly one recognized patch, never both.
firmware_patch_names={'0004-virtio-pci-allow-opt-in-low-memory-queues.patch','seabios-low-queues.patch'}
firmware_patch=firmware_patch_names & {p.name for p in a.firmware.iterdir()}
assert len(firmware_patch)==1,'Expected one low-memory queue patch'
firmware_names={'bios.bin','SeaBIOS-source.tar.gz','COPYING','COPYING.LESSER','README.txt','BUILD.json'} | firmware_patch
assert {p.name for p in a.firmware.iterdir()}==firmware_names,'Incomplete firmware/source bundle'
firmware_manifest=json.loads((a.firmware/'BUILD.json').read_text())
assert firmware_manifest['clean_rebuild_byte_identical'] is True
assert hashlib.sha256((a.firmware/'bios.bin').read_bytes()).hexdigest()==firmware_manifest['bios_sha256']
for x in sorted(a.firmware.iterdir()):
 assert x.is_file() and not x.is_symlink()
 paths.append((x,'VirtioBlk-firmware/'+x.name))
paths.append((BASE/'LICENSE','VirtioBlk-source/LICENSE'))
source_files=[
 'src/legacy-io.h','src/legacy-pci.h','src/legacy-transport.h',
 'src/native-dma.h','src/split-queue.c','src/split-queue.h',
 'src/block-protocol.h','src/block-scsi.h','src/block-mode.h',
 'src/block-flight-trace.h',
 'VirtioBlk/Default.table','VirtioBlk/Load_Commands.sect',
 'VirtioBlk/English.lproj/Localizable.strings',
 'VirtioBlk/Makefile','VirtioBlk/VirtioBlk.m',
 'VirtioBlk/virtio-blkctl.m']
for rel in source_files:
 x=BASE/rel
 assert x.is_file() and not x.is_symlink(), 'Missing or indirect source file: '+rel
 paths.append((x,'VirtioBlk-source/'+rel))
source_manifest=json.loads(a.source_manifest.read_text())
assert source_manifest['driver_sha256']==hashlib.sha256(a.tested_driver.read_bytes()).hexdigest()
for rel in source_files:
 assert source_manifest['sources'][rel]==hashlib.sha256((BASE/rel).read_bytes()).hexdigest(),'Source changed after package compilation: '+rel
paths.append((a.source_manifest,'SOURCE-SHA256.json'))
with a.archive.open('xb') as output:
 with gzip.GzipFile(fileobj=output,mode='wb',filename='',mtime=0) as gz:
  with tarfile.open(fileobj=gz,mode='w',format=tarfile.USTAR_FORMAT) as t:
   for path,name in paths:
    m=t.gettarinfo(str(path),arcname=name);m.uid=m.gid=0;m.uname='root';m.gname='wheel';m.mode=0o644;m.mtime=0
    with path.open('rb') as f:t.addfile(m,f)
   manifest={n:hashlib.sha256(b).hexdigest() for n,b in files.items()}
   data=(json.dumps(manifest,indent=2)+'\n').encode();m=tarfile.TarInfo('PAYLOAD-SHA256.json');m.size=len(data);m.mode=0o644;t.addfile(m,io.BytesIO(data))
with tarfile.open(a.archive) as t:
 for path,name in paths:assert t.extractfile(name).read()==path.read_bytes()
digest=hashlib.sha256(a.archive.read_bytes()).hexdigest()
a.archive.with_name(a.archive.name+'.sha256').write_text(digest+'  '+a.archive.name+'\n')
print(json.dumps({'archive':str(a.archive),'sha256':digest,'payload_files':len(files)},indent=2))
