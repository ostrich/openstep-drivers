#!/usr/bin/env python3
"""Generate module fingerprints and exact patch bytes from a supported kernel."""
import argparse,hashlib,importlib.util,json,tempfile
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('kernel',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
root=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('patch',root/'patch.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
original=a.kernel.read_bytes()
with tempfile.TemporaryDirectory() as tmp:patched,record,_=m.build(original,Path(tmp))
start,end=0x18ec70,0x191846
header='/* Generated from the exact supported kernel; do not edit. */\n'
header+='#define PMAP_START 0x%xU\n#define PMAP_LENGTH %dU\n#define PAYLOAD_ADDRESS %sU\n'%(start,end-start,record['stub_address'])
for name,data in [('original_pmap_hash',original[start-m.BASE:end-m.BASE]),('patched_pmap_hash',patched[start-m.BASE:end-m.BASE])]:header+='static const char '+name+'[] = "'+hashlib.sha256(data).hexdigest()+'";\n'
header+='static const unsigned char payload[] = {'+','.join('0x%02x'%v for v in bytes.fromhex(record['stub_bytes']))+'};\n'
header+='struct patch_site { unsigned address; unsigned char original[5], patched[5]; };\nstatic const struct patch_site sites[] = {\n'
for edit in record['edits']:
 arrays=['{'+','.join('0x%02x'%v for v in bytes.fromhex(edit[k]))+'}' for k in ['before','after']]
 header+=' {%sU,%s,%s},\n'%(edit['address'],arrays[0],arrays[1])
header+='};\n'
a.output.write_text(header)
print('Generated module inputs; patched image',record['patched_sha256'])
