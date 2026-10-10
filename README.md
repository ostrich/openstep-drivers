# OPENSTEP drivers

Drivers and guest services for OPENSTEP 4.2 Intel virtual machines. They add
absolute mouse input, VMware SVGA graphics, virtio storage and networking, and
host-to-guest file transfer and interactive terminals.

| Component | Purpose | Installation |
| --- | --- | --- |
| VMTablet 0.2 | Absolute pointer input through QEMU's VMware mouse interface | [README](components/vmtablet/package/README.distribution.txt) |
| VMWareFB 0.1 | True-color display, hardware cursors and guarded 2D copy/fill acceleration | [README](components/vmwarefb/package/README.distribution.txt) |
| VirtioRNG 0.1 | Host entropy reader | [README](components/virtio/package/README.txt) |
| VirtioNet 0.1 | Legacy virtio PCI network adapter | [README](components/virtio/package-net/README.txt) |
| VirtioBlk 0.1 | Legacy virtio PCI storage, including system boot | [README](components/virtio/package-blk/README.txt) |
| OpenStepVirtioServices 0.1 | Virtio console driver, QEMU guest agent and interactive PTY | [README](components/virtio/package-services/README.txt) |
| TCPBuffers 0.1 | Sets new TCP socket buffers to 32 KiB at boot | [README](components/tcp-buffers/package/README.txt) |
| EIDE 4.03 bus-master patch | Enables PCI bus mastering during driver startup | [README](components/eide-busmaster/README.distribution.txt) |

Install packages with OPENSTEP's Installer as root, then configure the device
as described in its README. OpenSesame can elevate Installer and Configure.
Back up the stopped VM disk before changing boot or storage drivers, and shut
down cleanly before changing the host's hardware configuration.

The virtio drivers use transitional PCI devices with the legacy interface,
INTx interrupts and one virtual CPU. VirtioBlk boot requires patched SeaBIOS
with low-memory queues enabled. Use the [OPENSTEP QEMU build](https://github.com/ostrich/openstep-qemu)
and the device options in each README. Other hypervisors are untested.
VMTablet currently implements the VMware mouse interface, not VirtualBox VMMDev.

## Building

Native drivers and Installer packages require OPENSTEP 4.2 Developer Tools.
Host clients and portable tests use Python 3 and a C compiler. See
[build instructions](docs/build.md), [licenses and attribution](docs/licenses.md)
and the [component index](components/manifest.json).
