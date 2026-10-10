#!/usr/bin/env python3
"""Validate VMTablet's native package and create an OPENSTEP-readable tar.gz."""
import argparse,gzip,hashlib,io,json,subprocess,tarfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
DRIVER_SHA='730ed81b4456ff412f8421ea310273739aff84ae0082b570856164734f5b7375'
ap=argparse.ArgumentParser(description=__doc__)
ap.add_argument('package',type=Path);ap.add_argument('archive',type=Path);args=ap.parse_args()
if args.package.name!='VMTablet.pkg' or not args.archive.name.endswith('.tar.gz'):ap.error('Use VMTablet.pkg and an output ending in .tar.gz')
expected={'VMTablet.bom','VMTablet.info','VMTablet.sizes','VMTablet.tar.Z'}
assert {p.name for p in args.package.iterdir()}==expected
assert all(p.is_file() and not p.is_symlink() for p in args.package.iterdir())
payload=subprocess.check_output(['zcat',str(args.package/'VMTablet.tar.Z')])
base='private/Drivers/i386/VMTablet.config/'
with tarfile.open(fileobj=io.BytesIO(payload)) as tar:
 members=tar.getmembers()
 assert all(m.uid==0 and m.gid==0 and not m.issym() and not m.islnk() for m in members)
 assert all(not m.name.startswith('/') and '..' not in Path(m.name).parts for m in members)
 files={m.name.removeprefix('./'):tar.extractfile(m).read() for m in members if m.isfile()}
 assert set(files)=={base+n for n in ['Default.table','Instance0.table','VMTablet_reloc','English.lproj/Localizable.strings']}
 assert hashlib.sha256(files[base+'VMTablet_reloc']).hexdigest()==DRIVER_SHA
 for name,source in [('Default.table','Default.table'),('Instance0.table','Default.table'),('English.lproj/Localizable.strings','English.lproj/Localizable.strings')]:
  assert files[base+name]==(ROOT/'vmtablet'/source).read_bytes()
paths=[(p,args.package.name+'/'+p.name) for p in sorted(args.package.iterdir())]
paths.append((Path(__file__).with_name('README.distribution.txt'),'README.txt'))
for name in ['Makefile','VMTablet.m','Default.table','Load_Commands.sect','English.lproj/Localizable.strings']:
 paths.append((ROOT/'vmtablet'/name,'VMTablet-source/'+name))
with args.archive.open('xb') as output:
 with gzip.GzipFile(fileobj=output,mode='wb',filename='',mtime=0) as compressed:
  with tarfile.open(fileobj=compressed,mode='w',format=tarfile.USTAR_FORMAT) as archive:
   for path,name in paths:
    entry=archive.gettarinfo(str(path),arcname=name)
    entry.uid=entry.gid=0;entry.uname='root';entry.gname='wheel';entry.mode=0o644;entry.mtime=0
    with path.open('rb') as source:archive.addfile(entry,source)
with tarfile.open(args.archive,'r:gz') as archive:
 for path,name in paths:assert archive.extractfile(name).read()==path.read_bytes()
digest=hashlib.sha256(args.archive.read_bytes()).hexdigest()
args.archive.with_name(args.archive.name+'.sha256').write_text(digest+'  '+args.archive.name+'\n')
print(json.dumps({'archive':str(args.archive),'sha256':digest,'driver_sha256':DRIVER_SHA,'source_files':5,'payload_files':len(files)},indent=2))
