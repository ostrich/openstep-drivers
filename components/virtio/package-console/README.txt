VirtioConsole 0.1 - binary channel for OPENSTEP 4.2 Intel

Requirements
An existing working OPENSTEP 4.2 Intel VM.
QEMU pc/i440fx, one virtual CPU, transitional virtio PCI with legacy INTx,
32-entry control queues and 128-entry data queues. One controller and one
virtserialport at port 1, PCI slot 9. Native VM pages must be 8192 bytes.
No guest networking is needed. No TTY, command execution, clipboard or file
service is provided. Live unloading and hotplug are unsupported; cold boot
for hardware or driver changes. Developer Tools are needed only to build.

Installation
1. Shut down cleanly and back up the VM disk. Install or upgrade only with
   the channel unused: replacing its lock inode during a transfer breaks
   consumer exclusion. Restart after installation before using the channel.
2. Extract with gnutar -xzf VirtioConsole-0.1.pkg.I.tar.gz.
3. Open VirtioConsole.pkg in Installer as root (OpenSesame can elevate it).
   Install at /, selecting Intel and English.
4. From this archive's extracted directory, as root:
       sh configure-guest.sh enable
   This preserves unrelated Active Drivers and saves an original table at
   /usr/Devices/System.config/Instance0.table.virtio-console-backup.
5. Shut down cleanly. Add these QEMU options, with an unused PCI slot 9:
       -chardev socket,id=console0,path=/path/to/console.sock,server=on,wait=off
       -device virtio-serial-pci-transitional,id=vserial,addr=9,max_ports=2,vectors=0
       -device virtserialport,bus=vserial.0,nr=1,chardev=console0,name=org.openstep.channel
   Choose a private host socket directory accessible only to trusted users.
   max_ports=2 reserves port 0; this driver still supports only port 1.
6. Restart. Check /usr/local/bin/virtio-console --stats. online=1 indicates
   driver readiness; host_open=1 requires a connected host client.

Binary echo check
On the host, make a 16384-byte binary fixture and start the included client:
    python3 -c 'open("input.bin","wb").write(bytes(range(256))*64)'
    python3 console-client.py --socket /path/to/console.sock --input input.bin --timeout 120
While it waits, run in a root Terminal in the guest:
    /usr/local/bin/virtio-console --echo 16384
The host compares every reply byte. An echo verifies delivery through the
channel, not storage, authentication or application processing.

Native utility
Run --write, --echo and --reset as root; OPENSTEP protects their write RPCs.
Unprivileged users may run --read and --stats. The utility rejects privileged
commands before consuming input when the caller is not root.
    virtio-console --stats
    virtio-console --read N > output.bin
    virtio-console --write N < input.bin
    virtio-console --echo N
N is 1..16777216. Transfer commands have a 30-second deadline, including
local pipe I/O, and support partial I/O and binary data. A stalled pipe,
short input, broken output, absent/disconnected host or stale session fails
nonzero. stdout is binary for --read; diagnostics go to stderr and may be
dropped if stderr is blocked. Normal exit and caught interruption restore
inherited descriptor flags. SIGKILL cannot perform that restoration.

One transfer utility owns the channel at a time through an advisory BSD lock
on the installed root-owned /usr/adm/virtio-console.lock. Never remove or
replace that inode while running. --stats is allowed concurrently; --reset
is excluded during a transfer. Custom raw DriverKit RPC clients must honor
the same lock contract. The channel is a shared raw stream, not a secure
service or a boundary between mutually untrusted guest users.

A successful write means local acceptance, not acknowledgment by the peer.
On failure, already accepted output is uncertain: do not replay it blindly.
Stop the old guest operation before reconnecting, then establish a new
application session. Connection notifications are asynchronous; this raw
channel does not provide application session authentication or acknowledgment. A driver
transport fault fences the channel; with transfers stopped, explicitly run
    /usr/local/bin/virtio-console --reset
then reconnect the host. Reset discards buffered data and outstanding output.
If the driver cannot reset, shut down cleanly and cold boot. Release logs
contain startup and actionable faults, not per-packet diagnostics.

Rollback
As root, run sh configure-guest.sh disable, then shut down cleanly. Remove
the three QEMU channel options and restart. Disable removes only this driver
from Active Drivers. If the guest cannot boot, restore the stopped-disk
backup or the saved System.config table. Keep original disks unchanged.

Source
MIT license in VirtioConsole-source/LICENSE. With native Developer Tools:
    cd VirtioConsole-source/drivers/VirtioConsole
    make
This builds VirtioConsole.config and virtio-console. The included host client
requires Python 3. Source and binaries in this archive belong to the same
release; test fault hooks and verbose probe diagnostics are not enabled.
