CC = cc
CFLAGS = -O2 -Wall -static -nostdinc -IvmwareFB_reloc.tproj -I/NextDeveloper/Headers -I/NextDeveloper/Headers/ansi -I/NextDeveloper/Headers/bsd -DKERNEL -DMACH_USER_API -DKERNEL_SERVER_INSTANCE=VMWareFB_instance
OBJECTS = VMWareFB.o VMWareFBAccel.o VMWareFBRegisters.o VMWareFBUtility.o VMWareFBCursor.o vmware.o
all: VMWareFB.config/VMWareFB_reloc VMWareFB_psdrvr
$(OBJECTS): vmwareFB_reloc.tproj/VMWareFB.h vmwareFB_reloc.tproj/vmware.h vmwareFB_reloc.tproj/svga_reg.h vmwareFB_reloc.tproj/VMWareFBPolicy.h
.m.o:
	$(CC) $(CFLAGS) -c $< -o $@
.c.o:
	$(CC) $(CFLAGS) -c $< -o $@
VMWareFB.o: vmwareFB_reloc.tproj/VMWareFB.m
	$(CC) $(CFLAGS) -c vmwareFB_reloc.tproj/VMWareFB.m -o $@
VMWareFBAccel.o: vmwareFB_reloc.tproj/VMWareFBAccel.m
	$(CC) $(CFLAGS) -c vmwareFB_reloc.tproj/VMWareFBAccel.m -o $@
VMWareFBRegisters.o: vmwareFB_reloc.tproj/VMWareFBRegisters.m
	$(CC) $(CFLAGS) -c vmwareFB_reloc.tproj/VMWareFBRegisters.m -o $@
VMWareFBUtility.o: vmwareFB_reloc.tproj/VMWareFBUtility.m
	$(CC) $(CFLAGS) -c vmwareFB_reloc.tproj/VMWareFBUtility.m -o $@
VMWareFBCursor.o: vmwareFB_reloc.tproj/VMWareFBCursor.m
	$(CC) $(CFLAGS) -c vmwareFB_reloc.tproj/VMWareFBCursor.m -o $@
vmware.o: vmwareFB_reloc.tproj/vmware.c
	$(CC) $(CFLAGS) -c vmwareFB_reloc.tproj/vmware.c -o $@
VMWareFB.config/VMWareFB_reloc: $(OBJECTS) Default.table Display.modes vmwareFB_reloc.tproj/Load_Commands.sect $(wildcard English.lproj/*)
	test -d VMWareFB.config || mkdir VMWareFB.config
	cp Default.table VMWareFB.config/Default.table
	cp Default.table VMWareFB.config/Instance0.table
	cp Display.modes VMWareFB.config/Display.modes
	test -d VMWareFB.config/English.lproj || mkdir VMWareFB.config/English.lproj
	cp English.lproj/* VMWareFB.config/English.lproj/
	kl_ld -o $@ $(OBJECTS) -n VMWareFB -l vmwareFB_reloc.tproj/Load_Commands.sect -i VMWareFB_instance
VMWareFB_psdrvr: psdriver/VMWareFB_psdrvr.c
	$(CC) $(PSDRIVER_CPPFLAGS) -O2 -c psdriver/VMWareFB_psdrvr.c -o VMWareFB_psdrvr.o
	ld -r -o VMWareFB_psdrvr VMWareFB_psdrvr.o
clean:
	rm -f $(OBJECTS) VMWareFB.config/VMWareFB_reloc VMWareFB_psdrvr.o VMWareFB_psdrvr
