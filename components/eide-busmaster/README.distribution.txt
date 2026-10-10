EIDE 4.03 Bus Master Patch 1 - OPENSTEP 4.2 Intel

This binary patch adds PCI bus-master initialization to EIDE 4.03 so DMA
works without a launcher helper. Tested with QEMU's Intel PIIX3 controller;
physical hardware and other controllers are untested. Source is not included.

Installation
1. Back up your VM disk while QEMU is stopped.
2. Extract: gnutar -xzf EIDE-4.03-BusMaster-1.pkg.I.tar.gz
3. Open EIDEBusMaster.pkg in Installer as root. Install at /, selecting Intel
   and English. An overwrite warning for the existing EIDE catalog is expected.
4. In Configure.app as root, record the existing disk-controller settings.
   Replace the EIDE controller with Intel PIIX PCI EIDE/ATAPI Device Controller
   (v4.03). Enable Bus Master DMA and Multiple Sectors. Check both channels:
   IRQs 14/15, ports 0x1f0-0x1f7 and 0x170-0x177. Leave other devices alone.
5. Save, shut down cleanly and restart.

Installer updates the driver catalog; Configure activates it. The device
version remains 4.03; the package version identifies Bus Master Patch 1.

Rollback
The package includes the unmodified driver as EIDE_reloc.original. As root,
copy it over EIDE_reloc in both /private/Drivers/i386/EIDE.config and
/usr/Devices/EIDE.config. Select Bus Master No and restart cleanly. Restore
the stopped-disk backup to recover the full previous configuration.

SHA256 - patched EIDE_reloc:
aa3582fdafa70ee62f2384ee66632d5879f2ffd70851ce0b2b9f0c37a71f6f12
SHA256 - EIDE_reloc.original:
8d9bc6da3a57f53a57d68e44e3b2a9d67707a5fe881a06477c35f94a217552a5

Cold boots, guest reboot, DMA transfers, checksums and filesystem checks
passed. One Bus Master No boot stalled before services; a retry passed.
That stall remains unexplained.
