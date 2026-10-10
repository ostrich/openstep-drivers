SeaBIOS 1.17.0-openstep-lowqueue1

This optional BIOS keeps virtio queues in low memory when explicitly enabled.
The original OPENSTEP booter overwrites high-memory BIOS queues during its
memory test. No original OPENSTEP executable is modified.

Use with QEMU's pc/i440fx machine:
    -bios VirtioBlk-firmware/bios.bin
    -fw_cfg name=etc/virtio-low-queues,string=on
These paths are relative to the extracted driver archive on the host.
The driver archive's main README covers guest installation and disk migration.
Without the fw_cfg option, ordinary SeaBIOS queue allocation is unchanged.

License and source
SeaBIOS is licensed under LGPL version 3; COPYING.LESSER and COPYING are
included. The driver's separate MIT license does not replace these terms.
SeaBIOS-source.tar.gz contains the complete corresponding source, applied
queue patch, build configuration and version file. BUILD.json identifies
the upstream revision and tested ROM checksum. A clean rebuild matched the
supplied ROM byte for byte with the recorded build tools.

Build on a host with GNU make, GCC, binutils and Python:
    tar -xzf SeaBIOS-source.tar.gz
    cd SeaBIOS-source
    make EXTRAVERSION=-openstep-lowqueue1
The ROM is out/bios.bin. Different toolchain versions may produce different
bytes. The standalone 0004-virtio-pci-allow-opt-in-low-memory-queues.patch is also included for review;
it is already applied to the bundled source.
