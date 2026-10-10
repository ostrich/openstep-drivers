CC = cc
CFLAGS = -O2 -Wall -static -nostdinc -I/NextDeveloper/Headers -I/NextDeveloper/Headers/ansi -I/NextDeveloper/Headers/bsd -DKERNEL -DMACH_USER_API -DKERNEL_SERVER_INSTANCE=VirtioConsole_instance $(TESTFLAGS)
all: VirtioConsole.config/VirtioConsole_reloc virtio-console
VirtioConsole.o: VirtioConsole.m ../src/split-queue.h ../src/legacy-pci.h ../src/legacy-io.h ../src/legacy-transport.h ../src/native-dma.h ../src/console-buffer.h ../src/console-link.h
	$(CC) $(CFLAGS) -c VirtioConsole.m -o $@
split-queue.o: ../src/split-queue.c ../src/split-queue.h
	$(CC) $(CFLAGS) -c ../src/split-queue.c -o $@
VirtioConsole.config/VirtioConsole_reloc: VirtioConsole.o split-queue.o Default.table Load_Commands.sect English.lproj/Localizable.strings
	test -d VirtioConsole.config || mkdir VirtioConsole.config
	cp Default.table VirtioConsole.config/Default.table
	cp Default.table VirtioConsole.config/Instance0.table
	test -d VirtioConsole.config/English.lproj || mkdir VirtioConsole.config/English.lproj
	cp English.lproj/Localizable.strings VirtioConsole.config/English.lproj/
	kl_ld -o $@ VirtioConsole.o split-queue.o -n VirtioConsole -l Load_Commands.sect -i VirtioConsole_instance
# OPENSTEP libDriver contains text relocations; permit the required writable
# text segment rather than suppressing the native linker's relocation warnings.
virtio-console: virtio-console.m
	$(CC) -O2 -Wall $(TESTFLAGS) -Wl,-segprot,__TEXT,rwx,rwx virtio-console.m -o $@ -lDriver
clean:
	rm -f VirtioConsole.o split-queue.o VirtioConsole.config/VirtioConsole_reloc virtio-console
