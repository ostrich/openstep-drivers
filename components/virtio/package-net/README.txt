VirtioNet 0.1 - Ethernet for OPENSTEP 4.2 Intel

Requirements
An existing working OPENSTEP 4.2 Intel VM.
QEMU pc/i440fx, one virtual CPU, transitional virtio PCI, legacy INTx,
standard 256-entry queues and MTU 1500. No MSI-X, multiqueue, jumbo frames
or checksum/segmentation offloads. No polled kernel-debugger transport.
Live driver unloading/hotplug are untested; use clean cold boots.
Developer Tools are needed only to build.

Installation
1. Shut down cleanly and back up the VM disk.
2. Extract: gnutar -xzf VirtioNet-0.1.pkg.I.tar.gz
3. Open VirtioNet.pkg in Installer as root (OpenSesame can elevate Installer).
   Install at /, selecting Intel and English.
4. As root, copy /private/Drivers/i386/VirtioNet.config to /usr/Devices/.
   Back up /usr/Devices/System.config/Instance0.table. In its "Active Drivers"
   list, replace AMDPCnet32NetworkDriver with VirtioNet; keep other entries.
5. Shut down cleanly. Replace QEMU's PCnet device with:
       -device virtio-net-pci-transitional,netdev=net0,addr=6
   Keep your existing net0 backend and IP settings. PCI slot 6 must be free;
   Instance0.table's "Location" must match "Dev:6 Func:0 Bus:0".
   With TCG, append ,tx=timer to the device option. This setting improved
   transfer performance in testing; performance still varies by workload.
6. Restart. As the only Ethernet adapter, VirtioNet registers as en0 and uses
   the existing network configuration. Confirm the address and connectivity.

Diagnostics
    /usr/local/bin/virtio-netctl --stats
    /usr/local/bin/virtio-netctl --reset
Reset discards outstanding packets; the network stack handles retransmission.
Release logging covers startup and actionable failures, not individual packets.
Other devices sharing its IRQ must also support OPENSTEP IRQ sharing correctly.

Rollback
Restore the saved System.config table, shut down cleanly, restore the PCnet
QEMU device and restart. For a boot failure, restore the stopped-disk backup.

Source
MIT license in VirtioNet-source/LICENSE. With native Developer Tools:
    cd VirtioNet-source/drivers/VirtioNet
    make
The resulting VirtioNet.config and virtio-netctl correspond to the package.
