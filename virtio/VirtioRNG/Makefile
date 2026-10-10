CC = cc
CFLAGS = -O2 -Wall -static -nostdinc -I/NextDeveloper/Headers -I/NextDeveloper/Headers/ansi -I/NextDeveloper/Headers/bsd -DKERNEL -DMACH_USER_API -DKERNEL_SERVER_INSTANCE=VirtioRNG_instance
all: VirtioRNG.config/VirtioRNG_reloc virtio-rng-read
VirtioRNG.o: VirtioRNG.m ../src/split-queue.h ../src/legacy-pci.h ../src/legacy-io.h ../src/legacy-transport.h ../src/native-dma.h
	$(CC) $(CFLAGS) -c VirtioRNG.m -o $@
split-queue.o: ../src/split-queue.c ../src/split-queue.h
	$(CC) $(CFLAGS) -c ../src/split-queue.c -o $@
VirtioRNG.config/VirtioRNG_reloc: VirtioRNG.o split-queue.o Default.table Load_Commands.sect English.lproj/Localizable.strings
	test -d VirtioRNG.config || mkdir VirtioRNG.config
	cp Default.table VirtioRNG.config/Default.table
	cp Default.table VirtioRNG.config/Instance0.table
	test -d VirtioRNG.config/English.lproj || mkdir VirtioRNG.config/English.lproj
	cp English.lproj/Localizable.strings VirtioRNG.config/English.lproj/
	kl_ld -o $@ VirtioRNG.o split-queue.o -n VirtioRNG -l Load_Commands.sect -i VirtioRNG_instance
# OPENSTEP libDriver contains text relocations; permit the required writable
# text segment rather than suppressing the native linker's relocation warnings.
virtio-rng-read: virtio-rng-read.m
	$(CC) -O2 -Wall -Wl,-segprot,__TEXT,rwx,rwx virtio-rng-read.m -o $@ -lDriver
clean:
	rm -f VirtioRNG.o split-queue.o VirtioRNG.config/VirtioRNG_reloc virtio-rng-read
