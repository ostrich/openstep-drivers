#!/usr/bin/env python3
"""Validate the native VirtioRNG package and make an OPENSTEP-readable archive."""
import argparse,gzip,hashlib,io,json,subprocess,tarfile
from pathlib import Path
BASE=Path(__file__).resolve().parents[1]
if not __debug__:raise SystemExit('Run without -O; package validation must remain enabled')
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('package',type=Path);p.add_argument('archive',type=Path)
p.add_argument('--tested-driver',type=Path,help='Require identity with an already-tested release binary')
a=p.parse_args()
if a.package.name!='VirtioRNG.pkg' or not a.archive.name.endswith('.tar.gz'):p.error('Expected VirtioRNG.pkg and output .tar.gz')
assert {x.name for x in a.package.iterdir()}=={'VirtioRNG.'+s for s in ('bom','info','sizes','tar.Z')}
assert all(x.is_file() and not x.is_symlink() for x in a.package.iterdir())
blob=subprocess.check_output(['zcat',str(a.package/'VirtioRNG.tar.Z')])
root='private/Drivers/i386/VirtioRNG.config/'
with tarfile.open(fileobj=io.BytesIO(blob)) as t:
 members=t.getmembers()
 assert all(m.uid==0 and m.gid==0 and (m.isfile() or m.isdir()) for m in members)
 assert all(not m.name.startswith('/') and '..' not in Path(m.name).parts for m in members)
 names=[m.name.removeprefix('./').rstrip('/') for m in members]
 assert len(names)==len(set(names)), 'Duplicate payload paths'
 files={m.name.removeprefix('./'):t.extractfile(m).read() for m in members if m.isfile()}
 assert set(files)=={root+n for n in ('Default.table','Instance0.table','English.lproj/Localizable.strings','VirtioRNG_reloc')}|{'usr/local/bin/virtio-rng-read'}
 for name,source in [('Default.table','Default.table'),('Instance0.table','Default.table'),('English.lproj/Localizable.strings','English.lproj/Localizable.strings')]:
  assert files[root+name]==(BASE/'VirtioRNG'/source).read_bytes()
 assert b'VirtioRNGTest' not in files[root+'VirtioRNG_reloc']
 assert b'VirtioRNG Test Failure' not in files[root+'VirtioRNG_reloc']
 assert b'VirtioRNGTestFaults' not in files[root+'VirtioRNG_reloc']
 if a.tested_driver:assert files[root+'VirtioRNG_reloc']==a.tested_driver.read_bytes(), 'Package differs from tested release'
 assert next(m.mode for m in members if m.name.removeprefix('./')=='usr/local/bin/virtio-rng-read')&0o111
paths=[(x,'VirtioRNG.pkg/'+x.name) for x in sorted(a.package.iterdir())]
paths.append((BASE/'package/README.txt','README.txt'))
paths.append((BASE/'LICENSE','VirtioRNG-source/LICENSE'))
source_files=[
 'src/legacy-io.h','src/legacy-pci.h','src/legacy-transport.h',
 'src/native-dma.h','src/split-queue.c','src/split-queue.h',
 'VirtioRNG/Default.table','VirtioRNG/Load_Commands.sect',
 'VirtioRNG/English.lproj/Localizable.strings',
 'VirtioRNG/Makefile','VirtioRNG/VirtioRNG.m',
 'VirtioRNG/virtio-rng-read.m']
for rel in source_files:
 x=BASE/rel
 assert x.is_file() and not x.is_symlink(), 'Missing or indirect source file: '+rel
 paths.append((x,'VirtioRNG-source/'+rel))
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
