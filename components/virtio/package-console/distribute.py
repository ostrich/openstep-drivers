#!/usr/bin/env python3
"""Validate the native VirtioConsole package and make an OPENSTEP-readable archive."""
import argparse,gzip,hashlib,io,json,subprocess,tarfile
from pathlib import Path
BASE=Path(__file__).resolve().parents[1]
if not __debug__:raise SystemExit('Run without -O; package validation must remain enabled')
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('package',type=Path);p.add_argument('archive',type=Path)
p.add_argument('--tested-build',type=Path,required=True,help='Quiet native build directory verified by the guest tests')
a=p.parse_args()
build_manifest=json.loads((a.tested_build/'build.json').read_text())
assert build_manifest['testing'] is False and build_manifest['diagnostics'] is False
assert build_manifest['warning_free'] is True
for name,digest in build_manifest['artifact_sha256'].items():
 assert hashlib.sha256((a.tested_build/name).read_bytes()).hexdigest()==digest

if a.package.name!='VirtioConsole.pkg' or not a.archive.name.endswith('.tar.gz'):p.error('Expected VirtioConsole.pkg and output .tar.gz')
assert {x.name for x in a.package.iterdir()}=={'VirtioConsole.'+s for s in ('bom','info','sizes','tar.Z')}
assert all(x.is_file() and not x.is_symlink() for x in a.package.iterdir())
blob=subprocess.check_output(['zcat',str(a.package/'VirtioConsole.tar.Z')])
root='private/Drivers/i386/VirtioConsole.config/'
with tarfile.open(fileobj=io.BytesIO(blob)) as t:
 members=t.getmembers()
 assert all(m.uid==0 and m.gid==0 and (m.isfile() or m.isdir()) for m in members)
 assert all(not m.name.startswith('/') and '..' not in Path(m.name).parts for m in members)
 names=[m.name.removeprefix('./').rstrip('/') for m in members]
 assert len(names)==len(set(names)), 'Duplicate payload paths'
 files={m.name.removeprefix('./'):t.extractfile(m).read() for m in members if m.isfile()}
 assert set(files)=={root+n for n in ('Default.table','Instance0.table','English.lproj/Localizable.strings','VirtioConsole_reloc')}|{'usr/local/bin/virtio-console','usr/adm/virtio-console.lock'}
 for name,source in [('Default.table','Default.table'),('Instance0.table','Default.table'),('English.lproj/Localizable.strings','English.lproj/Localizable.strings')]:
  assert files[root+name]==(BASE/'drivers/VirtioConsole'/source).read_bytes()
 assert b'VirtioConsoleTest' not in files[root+'VirtioConsole_reloc']
 assert b'VirtioConsole Test Failure' not in files[root+'VirtioConsole_reloc']
 assert b'VirtioConsoleTestFault' not in files[root+'VirtioConsole_reloc']
 assert b'VirtioConsoleProbe:' not in files[root+'VirtioConsole_reloc']
 assert b'VirtioConsoleFault:' not in files[root+'VirtioConsole_reloc']
 assert files[root+'VirtioConsole_reloc']==(a.tested_build/'VirtioConsole.reloc').read_bytes(), 'Package driver differs from tested release'
 assert files['usr/local/bin/virtio-console']==(a.tested_build/'virtio-console').read_bytes(), 'Utility differs from tested release'
 assert b'--test-' not in files['usr/local/bin/virtio-console']
 assert files['usr/adm/virtio-console.lock']==b''
 assert next(m.mode for m in members if m.name.removeprefix('./')=='usr/adm/virtio-console.lock')==0o644
 assert next(m.mode for m in members if m.name.removeprefix('./')=='usr/local/bin/virtio-console')&0o111
paths=[(x,'VirtioConsole.pkg/'+x.name) for x in sorted(a.package.iterdir())]
paths.append((BASE/'package-console/README.txt','README.txt'))
paths.append((BASE/'package-console/configure-guest.sh','configure-guest.sh'))
paths.append((BASE/'tools/console-client.py','console-client.py'))
paths.append((BASE/'LICENSE','VirtioConsole-source/LICENSE'))
source_files=[
 'src/legacy-io.h','src/legacy-pci.h','src/legacy-transport.h',
 'src/native-dma.h','src/split-queue.c','src/split-queue.h','src/console-buffer.h','src/console-link.h',
 'drivers/VirtioConsole/Default.table','drivers/VirtioConsole/Load_Commands.sect',
 'drivers/VirtioConsole/English.lproj/Localizable.strings',
 'drivers/VirtioConsole/Makefile','drivers/VirtioConsole/VirtioConsole.m',
 'drivers/VirtioConsole/virtio-console.m']
for rel in source_files:
 x=BASE/rel
 assert x.is_file() and not x.is_symlink(), 'Missing or indirect source file: '+rel
 assert build_manifest['source_sha256']['source/'+rel]==hashlib.sha256(x.read_bytes()).hexdigest(), 'Source changed after compilation: '+rel
 paths.append((x,'VirtioConsole-source/'+rel))
# No private host paths or development-work references belong in distribution docs.
readme=(BASE/'package-console/README.txt').read_text()
assert not any(word in readme.lower() for word in ('/home/','/users/','work/virtio','investigations/'))
with a.archive.open('xb') as output:
 with gzip.GzipFile(fileobj=output,mode='wb',filename='',mtime=0) as gz:
  with tarfile.open(fileobj=gz,mode='w',format=tarfile.USTAR_FORMAT) as t:
   for path,name in paths:
    # OPENSTEP make treats a zero source timestamp as a missing prerequisite.
    # Keep deterministic timestamps, but use a nonzero epoch for native builds.
    m=t.gettarinfo(str(path),arcname=name);m.uid=m.gid=0;m.uname='root';m.gname='wheel';m.mode=0o644;m.mtime=946684800
    with path.open('rb') as f:t.addfile(m,f)
   source_manifest={rel:build_manifest['source_sha256']['source/'+rel] for rel in source_files}
   data=(json.dumps(source_manifest,indent=2)+'\n').encode();m=tarfile.TarInfo('SOURCE-SHA256.json');m.size=len(data);m.mode=0o644;t.addfile(m,io.BytesIO(data))
   manifest={n:hashlib.sha256(b).hexdigest() for n,b in files.items()}
   data=(json.dumps(manifest,indent=2)+'\n').encode();m=tarfile.TarInfo('PAYLOAD-SHA256.json');m.size=len(data);m.mode=0o644;t.addfile(m,io.BytesIO(data))
with tarfile.open(a.archive) as t:
 for path,name in paths:assert t.extractfile(name).read()==path.read_bytes()
digest=hashlib.sha256(a.archive.read_bytes()).hexdigest()
a.archive.with_name(a.archive.name+'.sha256').write_text(digest+'  '+a.archive.name+'\n')
print(json.dumps({'archive':str(a.archive),'sha256':digest,'payload_files':len(files)},indent=2))
