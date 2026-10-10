CC = cc
CFLAGS = -O2 -Wall -static -nostdinc -I/NextDeveloper/Headers -I/NextDeveloper/Headers/ansi -I/NextDeveloper/Headers/bsd -DKERNEL -DMACH_USER_API -DKERNEL_SERVER_INSTANCE=VirtioNet_instance $(TESTFLAGS)
all: VirtioNet.config/VirtioNet_reloc virtio-netctl
VirtioNet.o: VirtioNet.m ../../src/split-queue.h ../../src/legacy-transport.h ../../src/legacy-pci.h ../../src/legacy-io.h ../../src/native-dma.h
	$(CC) $(CFLAGS) -c VirtioNet.m -o $@
split-queue.o: ../../src/split-queue.c ../../src/split-queue.h
	$(CC) $(CFLAGS) -c ../../src/split-queue.c -o $@
VirtioNet.config/VirtioNet_reloc: VirtioNet.o split-queue.o Default.table Load_Commands.sect English.lproj/Localizable.strings
	test -d VirtioNet.config || mkdir VirtioNet.config
	cp Default.table VirtioNet.config/Default.table
	cp Default.table VirtioNet.config/Instance0.table
	test -d VirtioNet.config/English.lproj || mkdir VirtioNet.config/English.lproj
	cp English.lproj/Localizable.strings VirtioNet.config/English.lproj/
	kl_ld -o $@ VirtioNet.o split-queue.o -n VirtioNet -l Load_Commands.sect -i VirtioNet_instance
clean:
	rm -f VirtioNet.o split-queue.o VirtioNet.config/VirtioNet_reloc virtio-netctl
virtio-netctl: virtio-netctl.m
	$(CC) -O2 -Wall $(TESTFLAGS) -Wl,-segprot,__TEXT,rwx,rwx virtio-netctl.m -o $@ -lDriver
