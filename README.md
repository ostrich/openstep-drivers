# OPENSTEP drivers

Drivers and guest services for OPENSTEP 4.2 Intel virtual machines. Make the VM easier to use:
move the mouse freely between desktops, use a larger true-color display,
improve disk and network transfer performance, and copy files or open a shell
directly from the host without setting up guest networking.

Download the installable packages from [GitHub Releases](https://github.com/ostrich/openstep-drivers/releases/latest).
Developer Tools are needed only to build from source.

| Component | What you gain | Installation |
| --- | --- | --- |
| VMTablet 0.2 | Aligned host/guest pointer and natural mouse exit/re-entry in GTK | [README](vmtablet/package/README.distribution.txt) |
| VMWareFB 0.1 | More desktop space, true color and accelerated 2D display paths | [README](vmwarefb/package/README.distribution.txt) |
| VirtioRNG 0.1 | Host-supplied entropy for command-line tools; no automatic PRNGD integration | [README](virtio/package/README.txt) |
| VirtioNet 0.1 | Higher TCP throughput in matched KVM tests, keeping existing en0 settings | [README](virtio/package-net/README.txt) |
| VirtioBlk 0.1 | Faster reads in matched KVM tests and direct virtio system boot | [README](virtio/package-blk/README.txt) |
| OpenStepVirtioServices 0.1 | File transfer, command execution and a shell without guest networking | [README](virtio/package-services/README.txt) |
| TCPBuffers 0.1 | Higher bulk TCP throughput without tuning each application | [README](tcp-buffers/package/README.txt) |
| EIDE 4.03 bus-master patch | DMA transfers on existing IDE disks without a launcher workaround | [README](eide-busmaster/README.distribution.txt) |

Install packages with OPENSTEP's Installer as root, then configure the device
as described in its README. OpenSesame can elevate Installer and Configure.
Back up the stopped VM disk before changing boot or storage drivers, and shut
down cleanly before changing the host's hardware configuration.

The virtio drivers use transitional PCI devices with the legacy interface,
INTx interrupts and one virtual CPU. VirtioBlk boot requires patched SeaBIOS
with low-memory queues enabled. Use the [OPENSTEP QEMU build](https://github.com/ostrich/openstep-qemu)
and the device options in each README. A [VirtioBlk driver floppy](docs/driver-floppy.md)
can expose a blank virtio disk to the installer. Other hypervisors are untested.
VMTablet currently implements the VMware mouse interface, not VirtualBox VMMDev.

## Building

Native drivers and Installer packages require OPENSTEP 4.2 Developer Tools.
Host clients and portable tests use Python 3 and a C compiler. See
[build instructions](docs/build.md), [licenses and attribution](docs/licenses.md)
and the [repository layout](docs/layout.md).
