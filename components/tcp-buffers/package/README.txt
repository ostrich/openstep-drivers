TCPBuffers 0.1 for OPENSTEP 4.2 Intel

Optional 32 KiB send/receive defaults for newly created TCP sockets, independent
of the network adapter. Existing connections keep their buffers; applications
can still request other sizes. No original kernel executable is modified.

Requirements
OPENSTEP 4.2 Patch 4 Intel, one virtual CPU. Tested on QEMU under KVM and TCG.
SMP, other kernel versions and live module unloading are unsupported.

Install and enable
1. Back up the VM, then extract TCPBuffers-0.1.pkg.I.tar.gz with gnutar -xzf.
2. Open TCPBuffers.pkg in Installer as root (OpenSesame can elevate it).
   Install at /, selecting Intel and English. Installation leaves tuning disabled.
3. In a root Terminal:
       /usr/local/bin/tcp-buffersctl --enable
4. Shut down cleanly and cold boot. Check:
       /usr/local/bin/tcp-buffersctl --status
   Expected: send=32768 receive=32768 and applied=1.

Disable
Run tcp-buffersctl --disable as root, then shut down cleanly and cold boot.
Disabling changes next-boot configuration; current connections and defaults
remain untouched until restart. The original kernel then supplies its defaults
(normally 4096). Both commands preserve other boot drivers and save first-use
configuration backups beside System.config/Instance0.table and the module table.
After reinstalling the package, run --enable again if tuning is wanted.

Only startup and actionable configuration failures are logged. Larger defaults
permit more queued network data and increase potential kernel memory use.
TCP remains responsible for recovering from packet loss during congestion.

Source
TCPBuffers-source/ contains matching native source, configuration tools and
MIT license. With OPENSTEP Developer Tools:
    cd TCPBuffers-source/TCPBuffers
    make
Outputs: TCPBuffers.config and tcp-buffersctl. The executable configure helper
is also included as configure-guest.sh; run it as root with enable or disable.
