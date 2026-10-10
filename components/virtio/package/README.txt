VirtioRNG 0.1 - experimental entropy driver for OPENSTEP 4.2 Intel

Reads bytes from QEMU's transitional virtio PCI entropy device. Includes a
bounded command-line client; it does not feed PRNGD, expose /dev/random, or
change OpenSSH/OpenSSL configuration. Keep your existing PRNGD setup.

QEMU requirements
Add these options to the host launch command:
    -object rng-random,id=rng0,filename=/dev/urandom
    -device virtio-rng-pci-transitional,addr=5,rng=rng0
PCI slot 5 must be free. Uses legacy PCI I/O and INTx, with one entropy
device and one queue on a single-vCPU guest. Tested
with pc/i440fx under KVM and TCG. Other hypervisors and modern-only devices
are untested.
This build supports shared INTx with VirtioNet. When upgrading an earlier
0.1 package, replace both the driver binary and its Instance0.table; the table
must enable "Share IRQ Levels". The version number remains 0.1.

Installation
1. Back up the VM disk while QEMU is stopped.
2. Extract: gnutar -xzf VirtioRNG-0.1.pkg.I.tar.gz
3. Open VirtioRNG.pkg in Installer as root. Install at / (Intel, English).
4. As root, copy /private/Drivers/i386/VirtioRNG.config to /usr/Devices/.
   Back up /usr/Devices/System.config/Instance0.table, then append VirtioRNG
   inside its existing "Boot Drivers" quoted list. Keep all other entries.
5. Shut down cleanly and restart QEMU with the entropy device options above.

Use
    /usr/local/bin/virtio-rng-read --stats
    /usr/local/bin/virtio-rng-read 4096 > bytes.bin
    /usr/local/bin/virtio-rng-read --reset
The client accepts 1..1048576 bytes per invocation; each driver read is at
most 256 bytes. A stalled read stops the device and returns an error. Reset
it explicitly before retrying. Diagnostics go to the system log only for
initialization and errors. Counters remain available through --stats.

Rollback
Remove VirtioRNG from the System table's "Boot Drivers" list, preserving other
entries (or restore the saved table). Shut down cleanly, then
remove its QEMU device options and restart. Restore the stopped-disk backup
if the guest cannot boot. Avoid live driver unloading.

Source and MIT license are included in VirtioRNG-source. With native
Developer Tools installed:
    cd VirtioRNG-source/drivers/VirtioRNG; make
