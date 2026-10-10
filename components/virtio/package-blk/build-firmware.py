#!/usr/bin/env python3
"""Bundle corresponding SeaBIOS source and verify a clean rebuild of the tested ROM."""
import argparse
import gzip
import hashlib
import io
import json
import re
import shutil
import subprocess
import tarfile
from pathlib import Path
BASE=Path(__file__).resolve().parents[1]
ROOT=BASE.parents[1]
REVISION='b52ca86e094d19b58e2304417787e96b940e39c6'
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--stock-source',required=True,type=Path)
p.add_argument('--built-tree',required=True,type=Path)
p.add_argument('--output',required=True,type=Path)
a=p.parse_args();output=a.output.resolve();output.relative_to(ROOT/'work/virtio/blk')
if output.exists():raise FileExistsError('Preserve existing firmware bundle')
revision=subprocess.check_output(['git','-C',str(a.stock_source),'rev-parse','HEAD'],text=True).strip()
if revision!=REVISION:raise ValueError('Unexpected source revision')
output.mkdir(parents=True)
source=output/'source';source.mkdir()
archive=subprocess.check_output(['git','-C',str(a.stock_source),'archive',REVISION])
with tarfile.open(fileobj=io.BytesIO(archive)) as t:t.extractall(source,filter='data')
patch=ROOT/'host/seabios/patches/0004-virtio-pci-allow-opt-in-low-memory-queues.patch'
with patch.open('rb') as f:
    subprocess.run(['patch','--batch','--forward','-p1'],cwd=source,stdin=f,check=True)
# Match every tracked input against the tree that produced the tested ROM.
# This rejects accidental inclusion of an unrelated local firmware patch.
for path in source.rglob('*'):
    if path.is_file():
        original=a.built_tree/path.relative_to(source)
        if not original.is_file() or path.read_bytes()!=original.read_bytes():
            raise ValueError('Tested build has a different source input: '+str(path.relative_to(source)))
shutil.copyfile(a.built_tree/'.config',source/'.config')
(source/'.version').write_text('1.17.0\n')
# Preserve clean corresponding source before make creates generated files.
bundle=output/'VirtioBlk-firmware';bundle.mkdir()
with (bundle/'SeaBIOS-source.tar.gz').open('xb') as f:
    with gzip.GzipFile(fileobj=f,mode='wb',filename='',mtime=0) as gz:
        with tarfile.open(fileobj=gz,mode='w',format=tarfile.USTAR_FORMAT) as t:
            for path in sorted(source.rglob('*')):
                m=t.gettarinfo(str(path),arcname='SeaBIOS-source/'+str(path.relative_to(source)))
                m.uid=m.gid=0;m.uname='root';m.gname='root';m.mtime=0
                if path.is_file():
                    with path.open('rb') as stream:t.addfile(m,stream)
                else:t.addfile(m)
with (output/'rebuild.log').open('w') as log:
    subprocess.run(['make','-j2','EXTRAVERSION=-openstep-lowqueue1'],cwd=source,
        stdout=log,stderr=subprocess.STDOUT,check=True)
rebuilt=(source/'out/bios.bin').read_bytes();tested=(a.built_tree/'out/bios.bin').read_bytes()
if rebuilt!=tested:raise RuntimeError('Clean corresponding-source rebuild differs from tested ROM')
(bundle/'bios.bin').write_bytes(tested)
for name in ('COPYING','COPYING.LESSER'):shutil.copyfile(source/name,bundle/name)
shutil.copyfile(patch,bundle/'0004-virtio-pci-allow-opt-in-low-memory-queues.patch')
shutil.copyfile(BASE/'package-blk/firmware-README.txt',bundle/'README.txt')
(bundle/'BUILD.json').write_text(json.dumps({'upstream_revision':REVISION,
    'version':'1.17.0-openstep-lowqueue1','bios_sha256':hashlib.sha256(tested).hexdigest(),
    'build_tools':re.search(r'#define BUILD_TOOLS "([^"]+)"',(source/'out/autoversion.h').read_text())[1],
    'clean_rebuild_byte_identical':True,'build_command':'make EXTRAVERSION=-openstep-lowqueue1'},indent=2)+'\n')
print('Corresponding source rebuild matches tested firmware:',bundle)
