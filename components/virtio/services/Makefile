CC = cc
CFLAGS = -O2 -Wall -DOPENSTEP_NATIVE
QGA_SOURCES = openstep-qga.m console-transport.m agent-json.c agent-protocol.c agent-files.c base64.c agent-exec.c agent-info.c native-shutdown.c service-runtime.c
all: openstep-qga openstep-agent-file openstep-pty
openstep-qga: $(QGA_SOURCES) console-transport.h agent-json.h agent-protocol.h agent-files.h base64.h agent-exec.h agent-info.h native-shutdown.h service-runtime.h
	$(CC) $(CFLAGS) -Wl,-segprot,__TEXT,rwx,rwx $(QGA_SOURCES) -o $@ -lDriver
openstep-agent-file: openstep-agent-file.c
	$(CC) $(CFLAGS) openstep-agent-file.c -o $@
openstep-pty: openstep-pty.m console-transport.m pty-native.c pty-wire.c pty-timeout.c service-runtime.c console-transport.h pty-native.h pty-wire.h pty-timeout.h service-runtime.h
	$(CC) $(CFLAGS) -Wl,-segprot,__TEXT,rwx,rwx openstep-pty.m console-transport.m pty-native.c pty-wire.c pty-timeout.c service-runtime.c -o $@ -lDriver
clean:
	rm -f openstep-qga openstep-agent-file openstep-pty *.o
