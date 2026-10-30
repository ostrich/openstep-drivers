CC = cc
CFLAGS = -O2 -Wall -static -nostdinc -I. -I/NextLibrary/Frameworks/System.framework/Headers -I/NextDeveloper/Headers -I/NextDeveloper/Headers/ansi -I/NextDeveloper/Headers/bsd -DKERNEL -DMACH_USER_API -DKERNEL_SERVER_INSTANCE=KernelMappingFix_instance
all: KernelMappingFix.config/KernelMappingFix_reloc kernel-mapping-fixctl
KernelMappingFix.o: KernelMappingFix.m patch-inputs.h sha256.h Makefile
	$(CC) $(CFLAGS) -c KernelMappingFix.m -o KernelMappingFix.o
KernelMappingFix.config/KernelMappingFix_reloc: KernelMappingFix.o Default.table Load_Commands.sect English.lproj/Localizable.strings
	test -d KernelMappingFix.config || mkdir KernelMappingFix.config
	cp Default.table KernelMappingFix.config/Default.table
	cp Default.table KernelMappingFix.config/Instance0.table
	test -d KernelMappingFix.config/English.lproj || mkdir KernelMappingFix.config/English.lproj
	cp English.lproj/Localizable.strings KernelMappingFix.config/English.lproj/Localizable.strings
	kl_ld -o KernelMappingFix.config/KernelMappingFix_reloc KernelMappingFix.o -n KernelMappingFix -l Load_Commands.sect -i KernelMappingFix_instance

kernel-mapping-fixctl: kernel-mapping-fixctl.m Makefile
	$(CC) -O2 -Wall -Wl,-segprot,__TEXT,rwx,rwx kernel-mapping-fixctl.m -o $@ -lDriver
