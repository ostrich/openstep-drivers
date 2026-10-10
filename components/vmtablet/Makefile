CC = cc
CFLAGS = -O2 -Wall -static -nostdinc -I. -I/NextDeveloper/Headers -I/NextDeveloper/Headers/ansi -I/NextDeveloper/Headers/bsd -DKERNEL -DMACH_USER_API -DKERNEL_SERVER_INSTANCE=VMTablet_instance
all: VMTablet.config/VMTablet_reloc
VMTablet.o: VMTablet.m
	$(CC) $(CFLAGS) -c VMTablet.m -o VMTablet.o
VMTablet.config/VMTablet_reloc: VMTablet.o Default.table Load_Commands.sect English.lproj/Localizable.strings
	test -d VMTablet.config || mkdir VMTablet.config
	cp Default.table VMTablet.config/Default.table
	cp Default.table VMTablet.config/Instance0.table
	test -d VMTablet.config/English.lproj || mkdir VMTablet.config/English.lproj
	cp English.lproj/Localizable.strings VMTablet.config/English.lproj/Localizable.strings
	kl_ld -o VMTablet.config/VMTablet_reloc VMTablet.o -n VMTablet -l Load_Commands.sect -i VMTablet_instance
