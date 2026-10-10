CC = cc
CFLAGS = -O2 -Wall -static -nostdinc -I. -I/NextDeveloper/Headers -I/NextDeveloper/Headers/ansi -I/NextDeveloper/Headers/bsd -DKERNEL -DMACH_USER_API -DKERNEL_SERVER_INSTANCE=TCPBuffers_instance
all: TCPBuffers.config/TCPBuffers_reloc tcp-buffersctl
TCPBuffers.o: TCPBuffers.m
	$(CC) $(CFLAGS) -c TCPBuffers.m -o TCPBuffers.o
TCPBuffers.config/TCPBuffers_reloc: TCPBuffers.o Default.table Load_Commands.sect English.lproj/Localizable.strings
	test -d TCPBuffers.config || mkdir TCPBuffers.config
	cp Default.table TCPBuffers.config/Default.table
	cp Default.table TCPBuffers.config/Instance0.table
	test -d TCPBuffers.config/English.lproj || mkdir TCPBuffers.config/English.lproj
	cp English.lproj/Localizable.strings TCPBuffers.config/English.lproj/Localizable.strings
	kl_ld -o TCPBuffers.config/TCPBuffers_reloc TCPBuffers.o -n TCPBuffers -l Load_Commands.sect -i TCPBuffers_instance

tcp-buffersctl: tcp-buffersctl.m
	$(CC) -O2 -Wall -Wl,-segprot,__TEXT,rwx,rwx tcp-buffersctl.m -o $@ -lDriver
