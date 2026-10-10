#!/usr/bin/env python3
"""Patch only the known EIDE 4.03 Mach-O. Original input remains untouched."""
import argparse, hashlib, json, struct, subprocess, tempfile
from pathlib import Path
ORIGINAL_SHA = '8d9bc6da3a57f53a57d68e44e3b2a9d67707a5fe881a06477c35f94a217552a5'
HOOK, RESUME, CAVE = 0x8191, 0x8198, 0xb444
TEXT_OFF, TEXT_RELOC, TEXT_NRELOC = 2328, 84248, 2110
CONST_ADDR, CONST_OFF, CONST_HEADER = 45920, 48248, 220

def patch(original):
    if hashlib.sha256(original).hexdigest() != ORIGINAL_SHA:
        raise ValueError('Input is not the verified EIDE 4.03 executable')
    if original[TEXT_OFF+HOOK:TEXT_OFF+RESUME] != bytes.fromhex('80bbe805000000'):
        raise ValueError('Unexpected hook instructions')
    with tempfile.TemporaryDirectory(prefix='.eide-patch-', dir=Path(__file__).resolve().parent) as directory:
        obj = Path(directory)/'patch.o'
        subprocess.run(['as','--32','-o',str(obj),str(Path(__file__).with_name('enable-busmaster.S'))],check=True)
        elf = obj.read_bytes()
    # ELF32 relocatable object produced by GNU as. Decode without extra libraries.
    shoff = struct.unpack_from('<I',elf,32)[0]
    shentsize, shnum, shstr = struct.unpack_from('<HHH',elf,46)
    sections = [struct.unpack_from('<10I',elf,shoff+i*shentsize) for i in range(shnum)]
    def data(s): return elf[s[4]:s[4]+s[5]]
    strings = data(sections[shstr])
    def string(b,x): return b[x:b.index(0,x)].decode()
    names = [string(strings,s[0]) for s in sections]
    textindex = names.index('.text')
    code = bytearray(data(sections[textindex]))
    rel = sections[names.index('.rel.text')]
    symtab = sections[rel[6]]
    symstrings = data(sections[symtab[6]])
    symbols = [struct.unpack_from('<IIIBBH',data(symtab),i) for i in range(0,symtab[5],16)]
    # Original section ordinals and original symbol index are deliberately retained.
    targets = {'get_selector':(0xe7b0,10,False),
               'set_selector':(0xe7bc,10,False),
               'objc_msgSend':(0,77,True),
               'resume_target':(RESUME,1,False)}
    relocations=[]
    for pos in range(0,rel[5],8):
        offset, info = struct.unpack_from('<II',data(rel),pos)
        symbol, kind = info>>8, info&255
        name=string(symstrings,symbols[symbol][0])
        target, ordinal, external = targets[name]
        addend=struct.unpack_from('<i',code,offset)[0]
        if kind == 1: value=target+addend; pcrel=0
        elif kind == 2: value=target+addend-(CAVE+offset); pcrel=1
        else: raise ValueError('Unsupported ELF relocation')
        struct.pack_into('<I',code,offset,value&0xffffffff)
        word=ordinal | pcrel<<24 | 2<<25 | int(external)<<27
        relocations.append((CAVE-CONST_ADDR+offset,word))
    caveoff=CONST_OFF+CAVE-CONST_ADDR
    if CAVE+len(code)>49152 or any(original[caveoff:caveoff+len(code)]):
        raise ValueError('Executable padding is unavailable')
    result=bytearray(original)
    result[caveoff:caveoff+len(code)]=code
    result[TEXT_OFF+HOOK:TEXT_OFF+RESUME]=b'\xe9'+struct.pack('<i',CAVE-HOOK-5)+b'\x90\x90'
    # Move only relocation tables to EOF; file offsets and virtual addresses of
    # every original section and symbol remain unchanged.
    textrels=[struct.unpack_from('<II',original,TEXT_RELOC+i*8) for i in range(TEXT_NRELOC)]
    if any(HOOK<=r<RESUME for r,w in textrels):
        raise ValueError('Hook overlaps existing relocation')
    textrels.append((HOOK+1,3 | 1<<24 | 2<<25))
    while len(result)%4: result.append(0)
    textrelocoff=len(result)
    result.extend(b''.join(struct.pack('<II',*r) for r in sorted(textrels,reverse=True)))
    constrelocoff=len(result)
    result.extend(b''.join(struct.pack('<II',*r) for r in sorted(relocations,reverse=True)))
    struct.pack_into('<II',result,28+56+48,textrelocoff,len(textrels))
    struct.pack_into('<I',result,CONST_HEADER+36,CAVE+len(code)-CONST_ADDR)
    struct.pack_into('<II',result,CONST_HEADER+48,constrelocoff,len(relocations))
    return bytes(result),{'hook_address':hex(HOOK),'routine_address':hex(CAVE),
                         'routine_bytes':len(code),'new_relocations':len(relocations)+1}

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('input',type=Path);ap.add_argument('output',type=Path)
    args=ap.parse_args()
    if args.input.resolve()==args.output.resolve():ap.error('Choose a separate output path')
    original=args.input.read_bytes()
    result,metadata=patch(original)
    with args.output.open('xb') as f:f.write(result)
    print(json.dumps(dict(metadata,original_sha256=ORIGINAL_SHA,
                         patched_sha256=hashlib.sha256(result).hexdigest()),indent=2))
if __name__=='__main__':main()
