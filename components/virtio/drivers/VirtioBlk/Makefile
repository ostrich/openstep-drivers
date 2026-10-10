CC = cc
CFLAGS = -O2 -Wall -static -nostdinc -I/NextDeveloper/Headers -I/NextDeveloper/Headers/ansi -I/NextDeveloper/Headers/bsd -DKERNEL -DMACH_USER_API -DKERNEL_SERVER_INSTANCE=VirtioBlk_instance $(TESTFLAGS)
all: VirtioBlk.config/VirtioBlk_reloc virtio-blkctl
VirtioBlk.o: VirtioBlk.m ../../src/split-queue.h ../../src/legacy-pci.h ../../src/legacy-io.h ../../src/legacy-transport.h ../../src/native-dma.h ../../src/block-protocol.h ../../src/block-scsi.h ../../src/block-mode.h
	$(CC) $(CFLAGS) -c VirtioBlk.m -o $@
split-queue.o: ../../src/split-queue.c ../../src/split-queue.h
	$(CC) $(CFLAGS) -c ../../src/split-queue.c -o $@
VirtioBlk.config/VirtioBlk_reloc: VirtioBlk.o split-queue.o Default.table Load_Commands.sect English.lproj/Localizable.strings
	test -d VirtioBlk.config || mkdir VirtioBlk.config
	cp Default.table VirtioBlk.config/Default.table
	cp Default.table VirtioBlk.config/Instance0.table
	test -d VirtioBlk.config/English.lproj || mkdir VirtioBlk.config/English.lproj
	cp English.lproj/Localizable.strings VirtioBlk.config/English.lproj/
	kl_ld -o $@ VirtioBlk.o split-queue.o -n VirtioBlk -l Load_Commands.sect -i VirtioBlk_instance
# OPENSTEP libDriver contains text relocations; permit the required writable
# text segment rather than suppressing the native linker's relocation warnings.

virtio-blkctl: virtio-blkctl.m
	$(CC) -O2 -Wall $(TESTFLAGS) -Wl,-segprot,__TEXT,rwx,rwx virtio-blkctl.m -o $@ -lDriver
clean:
	rm -f VirtioBlk.o split-queue.o VirtioBlk.config/VirtioBlk_reloc virtio-blkctl
