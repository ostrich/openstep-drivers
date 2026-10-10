#!/usr/bin/env python3
"""Validate native TCPBuffers package and assemble its self-contained release."""
import argparse,gzip,hashlib,io,json,re,subprocess,tarfile
from pathlib import Path
BASE=Path(__file__).resolve().parents[1]
if not __debug__:raise SystemExit('Validation must be enabled')
p=argparse.ArgumentParser();p.add_argument('--build',required=True,type=Path);p.add_argument('--archive',required=True,type=Path);p.add_argument('--evidence',required=True,type=Path);a=p.parse_args()
build=a.build;package=build/'TCPBuffers.pkg';assert {x.name for x in package.iterdir()}=={'TCPBuffers.'+x for x in ('bom','info','sizes','tar.Z')}
blob=subprocess.check_output(['gzip','-dc',str(package/'TCPBuffers.tar.Z')]);prefix='private/Drivers/i386/TCPBuffers.config/'
with tarfile.open(fileobj=io.BytesIO(blob)) as tar:
 members=tar.getmembers();assert all(not m.name.startswith('/') and '..' not in Path(m.name).parts and (m.isfile() or m.isdir()) and m.uid==0 and m.gid==0 for m in members)
 names=[m.name.removeprefix('./').rstrip('/') for m in members];assert len(names)==len(set(names))
 files={m.name.removeprefix('./'):tar.extractfile(m).read() for m in members if m.isfile()}
 assert set(files)=={prefix+x for x in ('Default.table','Instance0.table','English.lproj/Localizable.strings','TCPBuffers_reloc')}|{'usr/local/bin/tcp-buffersctl','usr/local/sbin/tcp-buffers-configure'}
 assert files[prefix+'TCPBuffers_reloc']==(build/'TCPBuffers_reloc').read_bytes()
 assert files['usr/local/bin/tcp-buffersctl']==(build/'tcp-buffersctl').read_bytes()
 assert files['usr/local/sbin/tcp-buffers-configure']==(BASE/'package/configure-guest.sh').read_bytes()
 assert b'"Apply TCP Defaults" = "No"' in files[prefix+'Instance0.table']
 for name in ('usr/local/bin/tcp-buffersctl','usr/local/sbin/tcp-buffers-configure'):assert next(m.mode for m in members if m.name.removeprefix('./')==name)&0o111
 evidence=json.loads(a.evidence.read_text());assert evidence['release_ready'] and evidence['driver_sha256']==hashlib.sha256(files[prefix+'TCPBuffers_reloc']).hexdigest()
paths=[(x,'TCPBuffers.pkg/'+x.name) for x in sorted(package.iterdir())]
paths+=[(BASE/'package/README.txt','README.txt'),(BASE/'package/configure-guest.sh','configure-guest.sh'),(BASE/'LICENSE','TCPBuffers-source/LICENSE')]
for path in sorted((BASE/'TCPBuffers').rglob('*')):
 if path.is_file() and path.suffix not in ('.o','.pyc') and 'TCPBuffers.config' not in path.parts:paths.append((path,'TCPBuffers-source/'+str(path.relative_to(BASE))))
paths+=[(BASE/'package/build-on-openstep.sh','TCPBuffers-source/package/build-on-openstep.sh'),(BASE/'package/TCPBuffers.info','TCPBuffers-source/package/TCPBuffers.info'),(BASE/'package/configure-guest.sh','TCPBuffers-source/package/configure-guest.sh')]
with tarfile.open(build/'source.tar') as source_archive:
 for path,name in paths:
  if name.startswith('TCPBuffers-source/') and path!=BASE/'LICENSE':
   rel=str(path.relative_to(BASE));assert source_archive.extractfile(rel).read()==path.read_bytes(),'Source changed after native build: '+rel
readme=(BASE/'package/README.txt').read_text();assert not re.search(r'/home/|/run/media/|~/|/Users/|\bwork/',readme,re.I)
manifest={name:hashlib.sha256(path.read_bytes()).hexdigest() for path,name in paths};manifest['payload']={name:hashlib.sha256(data).hexdigest() for name,data in files.items()}
with a.archive.open('xb') as output:
 with gzip.GzipFile(fileobj=output,mode='wb',filename='',mtime=0) as gz:
  with tarfile.open(fileobj=gz,mode='w',format=tarfile.USTAR_FORMAT) as tar:
   for path,name in paths:
    data=path.read_bytes();m=tarfile.TarInfo(name);m.size=len(data);m.mode=0o644;m.uid=m.gid=0;m.uname='root';m.gname='wheel';tar.addfile(m,io.BytesIO(data))
   data=(json.dumps(manifest,indent=2)+'\n').encode();m=tarfile.TarInfo('SHA256.json');m.size=len(data);m.mode=0o644;tar.addfile(m,io.BytesIO(data))
with tarfile.open(a.archive) as tar:
 for path,name in paths:assert tar.extractfile(name).read()==path.read_bytes()
digest=hashlib.sha256(a.archive.read_bytes()).hexdigest();a.archive.with_name(a.archive.name+'.sha256').write_text(digest+'  '+a.archive.name+'\n');print(digest,a.archive)
