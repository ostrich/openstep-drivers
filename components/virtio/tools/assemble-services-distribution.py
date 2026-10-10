#!/usr/bin/env python3
"""Assemble a reproducible distribution from validated native package builds."""
import argparse,gzip,hashlib,io,json,shutil,tarfile,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3];SRC=ROOT/'components/virtio'
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--driver-build',type=Path,required=True);p.add_argument('--services-build',type=Path,required=True)
p.add_argument('--output',type=Path,required=True);a=p.parse_args()
output=a.output.resolve();output.relative_to(ROOT);output.mkdir()
top=output/'OpenStepVirtioServices-0.1';top.mkdir()
def copy(source,name):
    assert source.is_file() and not source.is_symlink(),source
    destination=top/name;destination.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,destination)
    destination.chmod(0o755 if source.stat().st_mode&0o111 else 0o644)
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def native(build,package,report):
    data=json.loads((build/report).read_text())
    for name in ('bom','info','sizes','tar.Z'):copy(build/(package+'.pkg')/(package+'.'+name),package+'.pkg/'+package+'.'+name)
    return data
console=native(a.driver_build,'VirtioConsole','build.json')
assert console['warning_free'] and not console['testing'] and not console['diagnostics']
services=native(a.services_build,'OpenStepVirtioServices','results.json')
assert all(services[k] for k in ('native_package_built','payload_validated','binaries_equal_tested_build','native_installer_tar_checked'))
# Independently inspect actual compressed native payloads, rather than
# trusting package-build success flags or an old uncompressed payload copy.
def payload(build,package):
    data=subprocess.check_output(['gzip','-dc',str(build/(package+'.pkg')/(package+'.tar.Z'))])
    with tarfile.open(fileobj=io.BytesIO(data),mode='r:') as tar:
        result={}
        for member in tar.getmembers():
            path=Path(member.name)
            assert not path.is_absolute() and '..' not in path.parts,member.name
            assert member.isdir() or member.isfile(),member.name
            if member.isfile():
                name=str(path);assert name not in result,name
                assert member.uid==0 and member.gid==0,(name,member.uid,member.gid)
                result[name]=tar.extractfile(member).read()
        return result
cp=payload(a.driver_build,'VirtioConsole');sp=payload(a.services_build,'OpenStepVirtioServices')
for name,expected in console['artifact_sha256'].items():
    installed='private/Drivers/i386/VirtioConsole.config/VirtioConsole_reloc' if name=='VirtioConsole.reloc' else 'usr/local/bin/'+name
    assert hashlib.sha256(cp[installed]).hexdigest()==expected,installed
for name in ('openstep-qga','openstep-pty','openstep-agent-file'):
    installed=('usr/local/libexec/' if name=='openstep-agent-file' else 'usr/local/sbin/')+name
    assert sp[installed]==(a.services_build/(name+'.tested')).read_bytes(),installed
# Include only source/build inputs described by the native build manifests.
for manifest in (console,services):
    for name,expected in manifest['source_sha256'].items():
        assert name.startswith('source/') and '..' not in Path(name).parts,name
        source=SRC/name.removeprefix('source/')
        if source.name.startswith('README') or source.name=='distribute.py':continue
        assert digest(source)==expected,'Native package source drift: '+name
        copy(source,name)
copy(SRC/'package-services/README.txt','README.txt')
copy(SRC/'LICENSE','LICENSE-MIT.txt')
for name in ('agent-client.py','pty-client.py'):copy(SRC/'tools'/name,'host/'+name)
copy(SRC/'package-console/configure-guest.sh','scripts/configure-guest.sh')
# Reject private paths, personal names and stray build products in text artifacts.
for file in top.rglob('*'):
    if not file.is_file() or '.pkg' in str(file.relative_to(top)):continue
    text=file.read_text()
    assert '/home/' not in text and '/run/media/' not in text and '/users/' not in text.lower(),file
hashes={str(f.relative_to(top)):digest(f) for f in sorted(top.rglob('*')) if f.is_file()}
(top/'SHA256.json').write_text(json.dumps(hashes,indent=2)+'\n')
archive=output/(top.name+'.pkg.I.tar.gz')
with archive.open('wb') as raw,gzip.GzipFile(filename='',mode='wb',fileobj=raw,mtime=0) as zipped,tarfile.open(fileobj=zipped,mode='w',format=tarfile.USTAR_FORMAT) as tar:
    for path in [top,*sorted(top.rglob('*'))]:
        info=tar.gettarinfo(str(path),str(path.relative_to(output)))
        info.uid=info.gid=0;info.uname=info.gname='root';info.mtime=946684800
        if path.is_file():tar.addfile(info,io.BytesIO(path.read_bytes()))
        else:tar.addfile(info)
with tarfile.open(archive,'r:gz') as tar:
    members=tar.getmembers();assert all(m.isfile() or m.isdir() for m in members)
    for name,expected in hashes.items():assert hashlib.sha256(tar.extractfile(top.name+'/'+name).read()).hexdigest()==expected
(output/'audit.json').write_text(json.dumps({'archive_sha256':digest(archive),'files':len(hashes)+1,'native_sources_match':True,'archive_payload_hashes_verified':True,'private_path_scan_passed':True},indent=2)+'\n')
print(archive)
