#!/usr/bin/env python3
"""Execute actual patch bytes with mocked PCI API, including failure paths.
Requires unicorn; this complements real-guest tests, not replaces them.
"""
import hashlib, importlib.util, struct, sys
from pathlib import Path
from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
from unicorn.x86_const import *
spec=importlib.util.spec_from_file_location('patch',Path(__file__).with_name('patch.py'))
patch=importlib.util.module_from_spec(spec);spec.loader.exec_module(patch)
original=Path(sys.argv[1]).read_bytes();binary,meta=patch.patch(original)
assert patch.patch(original)[0]==binary
assert hashlib.sha256(binary).hexdigest()=='aa3582fdafa70ee62f2384ee66632d5879f2ffd70851ce0b2b9f0c37a71f6f12'
try:patch.patch(binary)
except ValueError:pass
else:raise AssertionError('Patched input was not rejected')
# Original section locations and symbols must be preserved; changes consist of
# the hook, padding routine, relocation headers/tables and extended const size.
assert binary[:28]==original[:28]
assert binary[108840:111596]==original[108840:111596]

cases=[('Yes',0x103,None,0x107,True),('yes',0x103,None,0x107,True),
 ('Yes',0xf9000103,None,0xf9000107,True),('No',0x103,None,0x103,False),
 ('No',0x107,None,0x107,False),(None,0x103,None,0x103,False),
 (None,0x107,None,0x107,True),('Yes',0x103,'read1',0x103,False),
 ('Yes',0x103,'write',0x103,False),('Yes',0x103,'ignored',0x103,False),
 ('Yes',0x103,'read2',0x107,False),('Yes',0x102,None,0x102,False),
 ('Yes',0x107,None,0x107,True)]
for option,command,failure,expected,enabled in cases:
 u=Uc(UC_ARCH_X86,UC_MODE_32);u.mem_map(0,0x80000)
 # Materialize the original virtual segment layout without relocation. Calls
 # to address zero are intercepted as objc_msgSend; real relocation is tested
 # by rld in the guest. Local selector references use their original addresses.
 u.mem_write(0,binary[2328:2328+49152])
 u.mem_write(0xe7b0,struct.pack('<I',0x11111111))
 u.mem_write(0xe7bc,struct.pack('<I',0x22222222))
 obj,frame,stack,string=0x30000,0x41000,0x40000,0x50000
 initial=bool(command&4) and option!='No'
 u.mem_write(obj+0x5e8,bytes([initial]))
 if option:u.mem_write(string,option.encode()+b'\0')
 u.mem_write(frame-16,struct.pack('<I',0x12345678))
 u.mem_write(frame+16,struct.pack('<I',0x87654321))
 for reg,value in [(UC_X86_REG_EAX,string if option else 0),(UC_X86_REG_EBX,obj),
  (UC_X86_REG_EBP,frame),(UC_X86_REG_ESP,stack),(UC_X86_REG_ESI,0xabcdef),
  (UC_X86_REG_EDI,0xfedcba)]:u.reg_write(reg,value)
 state={'command':command,'reads':0,'writes':0,'finished':False}
 def hook(uc,address,size,user):
  if address==patch.RESUME:
   state['finished']=True;uc.emu_stop();return
  if address!=0:return
  sp=uc.reg_read(UC_X86_REG_ESP)
  ret,receiver,selector,value,register,description=struct.unpack('<6I',uc.mem_read(sp,24))
  assert receiver==0x12345678 and description==0x87654321 and register==4
  status=0
  if selector==0x11111111:
   state['reads']+=1
   if failure=='read'+str(state['reads']):status=1
   else:uc.mem_write(value,struct.pack('<I',state['command']))
  elif selector==0x22222222:
   state['writes']+=1
   assert value==((command&0xffff)|4),'PCI status must not be written back'
   if failure=='write':status=1
   elif failure!='ignored':state['command']=(command&0xffff0000)|value
  else:raise AssertionError('Unexpected selector')
  uc.reg_write(UC_X86_REG_EAX,status);uc.reg_write(UC_X86_REG_ESP,sp+4)
  uc.reg_write(UC_X86_REG_EIP,ret)
 u.hook_add(UC_HOOK_CODE,hook);u.emu_start(patch.HOOK,0x7ffff,count=1000)
 assert state['finished'] and state['command']==expected
 actual=bool(u.mem_read(obj+0x5e8,1)[0]);assert actual==enabled
 assert bool(u.reg_read(UC_X86_REG_EFLAGS)&0x40)==(not enabled)
 assert u.reg_read(UC_X86_REG_ESP)==stack
 assert u.reg_read(UC_X86_REG_EBP)==frame and u.reg_read(UC_X86_REG_EBX)==obj
 assert u.reg_read(UC_X86_REG_ESI)==0xabcdef and u.reg_read(UC_X86_REG_EDI)==0xfedcba
 if option in (None,'No'):assert state['reads']==state['writes']==0
 print(f'PASS option={option!r} command={command:#x} failure={failure!r} DMA={enabled}')
print(f'{len(cases)} machine-code cases passed; reproducibility and input guards passed')
