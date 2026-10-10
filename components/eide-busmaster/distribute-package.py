#!/usr/bin/env python3
"""Validate the native package and wrap it in a tar.gz for installation."""
import argparse,hashlib,io,json,subprocess,tarfile,gzip
from pathlib import Path
PATCHED='aa3582fdafa70ee62f2384ee66632d5879f2ffd70851ce0b2b9f0c37a71f6f12'
ORIGINAL='8d9bc6da3a57f53a57d68e44e3b2a9d67707a5fe881a06477c35f94a217552a5'
ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('package',type=Path);ap.add_argument('archive',type=Path);args=ap.parse_args()
assert args.package.name=='EIDEBusMaster.pkg'
expected={'EIDEBusMaster.info','EIDEBusMaster.bom','EIDEBusMaster.sizes','EIDEBusMaster.tar.Z'}
assert {p.name for p in args.package.iterdir()}==expected
assert all(p.is_file() and not p.is_symlink() for p in args.package.iterdir())
info=(args.package/'EIDEBusMaster.info').read_text();assert 'LongFilenames   NO' in info
payload=subprocess.check_output(['zcat',str(args.package/'EIDEBusMaster.tar.Z')])
base='private/Drivers/i386/EIDE.config/'
with tarfile.open(fileobj=io.BytesIO(payload)) as tar:
 members=tar.getmembers()
 assert all(m.uid==0 and m.gid==0 and not m.issym() and not m.islnk() for m in members)
 assert all(not m.name.startswith('/') and '..' not in Path(m.name).parts for m in members)
 files={m.name.removeprefix('./'):tar.extractfile(m).read() for m in members if m.isfile()}
 assert all(name.startswith(base) for name in files)
 assert hashlib.sha256(files[base+'EIDE_reloc']).hexdigest()==PATCHED
 assert hashlib.sha256(files[base+'EIDE_reloc.original']).hexdigest()==ORIGINAL
if not args.archive.name.endswith('.tar.gz'):ap.error('Output must end in .tar.gz')
# USTAR avoids modern PAX headers that old guest tar programs may not support.
with args.archive.open('xb') as output:
 with gzip.GzipFile(fileobj=output,mode='wb',filename='',mtime=0) as compressed:
  with tarfile.open(fileobj=compressed,mode='w',format=tarfile.USTAR_FORMAT) as archive:
   paths=[(p,args.package.name+'/'+p.name) for p in sorted(args.package.iterdir())]
   paths.append((Path(__file__).with_name('README.distribution.txt'),'README.txt'))
   for path,name in paths:
    entry=archive.gettarinfo(str(path),arcname=name)
    entry.uid=entry.gid=0;entry.uname='root';entry.gname='wheel';entry.mode=0o644;entry.mtime=0
    with path.open('rb') as source:archive.addfile(entry,source)
with tarfile.open(args.archive,'r:gz') as archive:
 for path,name in paths:assert archive.extractfile(name).read()==path.read_bytes()
digest=hashlib.sha256(args.archive.read_bytes()).hexdigest()
args.archive.with_name(args.archive.name+'.sha256').write_text(digest+'  '+args.archive.name+'\n')
print(json.dumps({'archive':str(args.archive),'sha256':digest,'payload_files':len(files)},indent=2))
