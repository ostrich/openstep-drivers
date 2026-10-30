#!/usr/bin/env python3
"""Package the separately built Intel DriverKit module with native receipts."""
import argparse,hashlib,json,shutil,subprocess,sys
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--build',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--nextpkg',default='nextpkg',help='Host nextpkg executable or Python entry point');a=p.parse_args()
root=Path(__file__).resolve().parent;out=a.output.resolve();source=root/'module';build=a.build.resolve()
if a.nextpkg.endswith('.py'):
 if not Path(a.nextpkg).is_file():p.error('nextpkg entry point does not exist')
 builder=[sys.executable,a.nextpkg]
else:
 executable=shutil.which(a.nextpkg)
 if not executable:p.error('nextpkg not found; pass --nextpkg /path/to/nextpkg')
 builder=[executable]
for name in ['KernelMappingFix_reloc','kernel-mapping-fixctl']:
 if not (build/name).is_file():p.error('Missing build result: '+name)
if out.exists():p.error('Output directory already exists; choose a new directory')
out.mkdir(parents=True);stage=out/'stage'
# /usr/Devices is the system alias of this directory, not a second payload.
for base in ['private/Drivers/i386']:
 d=stage/base/'KernelMappingFix.config';(d/'English.lproj').mkdir(parents=True)
 for name in ['Default.table','Instance0.table','English.lproj/Localizable.strings','KernelMappingFix_reloc']:
  src=build/name if name=='KernelMappingFix_reloc' else source/('Default.table' if name=='Instance0.table' else name)
  shutil.copyfile(src,d/name);(d/name).chmod(0o644)
d=stage/'usr/local/sbin';d.mkdir(parents=True)
for name,src in [('kernel-mapping-fixctl',build/'kernel-mapping-fixctl'),('kernel-mapping-fix-configure',source/'configure-guest.sh')]:shutil.copyfile(src,d/name);(d/name).chmod(0o755)
d=stage/'usr/local/share/licenses/KernelMappingFix';d.mkdir(parents=True);shutil.copyfile(source/'LICENSE',d/'LICENSE')
pre='''#!/bin/sh
test "$#" = 2 && test "$2" = / || { echo 'Install this system driver at / on the boot volume.' >&2; exit 1; }
'''
(out/'pre_install').write_text(pre)
(out/'pre_delete').write_text(pre+'set -- disable\n'+(source/'configure-guest.sh').read_text())
for name in ['pre_install','pre_delete']:(out/name).chmod(0o755)
shutil.copyfile(source/'README.txt',out/'README.txt')
spec=dict(name='KernelMappingFix',version='0.1',revision=1,title='Kernel Mapping Fix',description='Corrects Intel OPENSTEP 4.2 mapping invalidation in memory without changing the kernel file.',root='stage',architectures=['i386'],readme='README.txt',hooks=dict(pre_install='pre_install',pre_delete='pre_delete'))
(out/'package.json').write_text(json.dumps(spec,indent=2)+'\n')
subprocess.run(builder+['build',str(out/'package.json'),'-o',str(out/'archives')],check=True)
(out/'module-inputs.json').write_text(json.dumps({name:hashlib.sha256((build/name).read_bytes()).hexdigest() for name in ['KernelMappingFix_reloc','kernel-mapping-fixctl']},indent=2)+'\n')
