#!/usr/bin/env python3
"""Validate a native VMWareFB package and wrap it in an OPENSTEP-readable archive."""
import argparse,gzip,hashlib,io,json,subprocess,tarfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('package',type=Path);p.add_argument('archive',type=Path);a=p.parse_args()
if a.package.name!='VMWareFB.pkg' or not a.archive.name.endswith('.tar.gz'):p.error('Expected VMWareFB.pkg and output .tar.gz')
expected={'VMWareFB.'+ext for ext in ('bom','info','sizes','tar.Z')}
assert {x.name for x in a.package.iterdir()}==expected
assert all(x.is_file() and not x.is_symlink() for x in a.package.iterdir())
base='private/Drivers/i386/VMWareFB.config/'
resources={'Default.table':'Default.table','Instance0.table':'Default.table','Display.modes':'Display.modes','English.lproj/Info.rtf':'English.lproj/Info.rtf','English.lproj/Localizable.strings':'English.lproj/Localizable.strings'}
payload=subprocess.check_output(['zcat',str(a.package/'VMWareFB.tar.Z')])
with tarfile.open(fileobj=io.BytesIO(payload)) as t:
 members=t.getmembers()
 assert all(m.uid==0 and m.gid==0 and (m.isfile() or m.isdir()) for m in members)
 assert all(not m.name.startswith('/') and '..' not in Path(m.name).parts for m in members)
 files={m.name.removeprefix('./'):t.extractfile(m).read() for m in members if m.isfile()}
 assert set(files)=={base+x for x in resources}|{base+'VMWareFB_reloc','usr/lib/NextStep/Displays/VMWareFB_psdrvr'}
 for name,source in resources.items():assert files[base+name]==(ROOT/'components/vmwarefb'/source).read_bytes(),name
 assert b'VMWareFB Test Failure' not in files[base+'VMWareFB_reloc']
 assert b'VMWareFBTest:' not in files[base+'VMWareFB_reloc']
 assert b'VMWareFB Test Failure' not in files[base+'Instance0.table']
 assert (a.package/'VMWareFB.info').read_bytes()==Path(__file__).with_name('VMWareFB.info').read_bytes()
paths=[(x,'VMWareFB.pkg/'+x.name) for x in sorted(a.package.iterdir())]
paths.append((Path(__file__).with_name('README.distribution.txt'),'README.txt'))
source=ROOT/'components/vmwarefb'
for x in sorted(source.rglob('*')):
 rel=x.relative_to(source)
 # Host packaging tools are colocated now; they are not standalone guest source.
 if rel.parts[0]=='package':continue
 if rel.parts[0]=='tests' and rel.as_posix() not in ('tests/probe.m','tests/policy-tests.c'):continue
 if rel.as_posix() in ('README.md','README.upstream.rdoc'):continue
 if any(part.startswith('.') or part in ('__pycache__','VMWareFB.config','.work-build-test') for part in rel.parts):continue
 if x.is_file() and x.suffix not in ('.o','.pyc') and x.name not in ('VMWareFB_psdrvr','policy-tests'):
  paths.append((x,'VMWareFB-source/'+rel.as_posix()))
paths.append((Path(__file__).with_name('README.distribution.md'),'VMWareFB-source/README.md'))
manifest={name:hashlib.sha256(data).hexdigest() for name,data in files.items()}
with a.archive.open('xb') as out:
 with gzip.GzipFile(fileobj=out,mode='wb',filename='',mtime=0) as gz:
  with tarfile.open(fileobj=gz,mode='w',format=tarfile.USTAR_FORMAT) as t:
   for path,name in paths:
    info=t.gettarinfo(str(path),arcname=name);info.uid=info.gid=0;info.uname='root';info.gname='wheel';info.mode=0o644;info.mtime=0
    with path.open('rb') as f:t.addfile(info,f)
   data=(json.dumps(manifest,indent=2)+'\n').encode();info=tarfile.TarInfo('PAYLOAD-SHA256.json');info.size=len(data);info.mode=0o644;t.addfile(info,io.BytesIO(data))
with tarfile.open(a.archive,'r:gz') as t:
 for path,name in paths:assert t.extractfile(name).read()==path.read_bytes()
digest=hashlib.sha256(a.archive.read_bytes()).hexdigest()
a.archive.with_name(a.archive.name+'.sha256').write_text(digest+'  '+a.archive.name+'\n')
print(json.dumps({'archive':str(a.archive),'sha256':digest,'payload_files':len(files)},indent=2))
