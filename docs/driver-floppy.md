# VirtioBlk installation floppy

The builder adds the released VirtioBlk driver to a copy of an OPENSTEP 4.2
1.44 MiB driver floppy. It preserves the stock boot drivers and EIDE support,
removing the unused S3 display and DPT SCSI drivers to make room. The source
repository does not contain the original OPENSTEP disk image.

On Linux with writable nextufs/FUSE support:

```sh
python3 scripts/make-virtio-blk-floppy.py \
  --base /path/to/4.2_Driver_Disk.floppyimage.img \
  --package /path/to/VirtioBlk-0.1.pkg.I.tar.gz \
  --nextufs /path/to/nextufs \
  --output dist/VirtioBlk-0.1-driver.img
```

The original floppy is unchanged. Existing output files are refused. The
builder checks the copied driver files and runs read-only fsck after unmounting.

## Hardware configuration

Use the patched QEMU and SeaBIOS from openstep-qemu, one Pentium virtual CPU,
64 MiB RAM and a transitional virtio block device at PCI slot 7:

```sh
-drive file=SYSTEM.raw,format=raw,if=none,id=system,cache=writeback
-device virtio-blk-pci-transitional,addr=7,drive=system,bootindex=1
-fw_cfg name=etc/virtio-low-queues,string=on
-drive file=Openstep-4.2-Intel-User.iso,format=raw,media=cdrom,if=ide,index=0,readonly=on
```

Use the supplied patched BIOS with `-bios`. The CD must be primary IDE master
for this route. There is no IDE hard disk. Start with the original installation
floppy, then switch to the generated driver floppy when prompted.

## Controller selection

Load VirtioBlk before EIDE. The stock installer uses `/dev/sg0` to inspect SCSI
disks; if the ATAPI CD controller becomes sc0, it fails to offer the virtio disk.
The prompt labels describe intended use, but these selections establish the
order in which the controllers load:

1. At the CD-controller prompt, select Virtio Block Controller.
2. At the hard-disk-controller prompt, select EIDE and ATAPI Device Controller,
   the single-controller variant, not Primary/Secondary(Dual) EIDE.
3. Continue without additional drivers.
4. The kernel registers VirtioBlk as sc0/sd0 and the CD as sc1/sd1, mounts the CD,
   and the installer offers the 2048 MiB VIRTIO Block Disk.

The generated floppy's menus have VirtioBlk on the fourth page, option 3.
EIDE's single-controller entry is on the third page, option 2. Check the labels;
these positions apply only to this generated catalog. Keep the floppy available
for subsequent prompts to load or install the custom driver.

## First hard-disk boot

The stock first stage records VirtioBlk in Boot Drivers but does not copy this
new driver into its installed catalog. On the first disk boot, stock EIDE loads
first and the requested VirtioBlk driver is supplied from floppy afterward.
That makes the installed disk sd1 temporarily.

1. When base copying finishes, remove the floppy and press Return to reboot.
2. At the hard-disk booter's `boot:` prompt, enter `-s rootdev=sd1a`.
3. When asked for Virtio Block Controller, insert this driver floppy and type 1.
4. At the single-user shell, run:

```sh
/usr/etc/mount -o remount /dev/sd1a /
/bin/mkdir /private/tmp/vfd
/usr/etc/mount -r /dev/fd0a /private/tmp/vfd
/bin/sh /private/tmp/vfd/configure-install.sh /dev/sd1a
/usr/etc/umount /private/tmp/vfd
sync
/usr/etc/halt
```

Wait for the safe-to-turn-off screen. Remove the floppy and boot from disk.
The helper copies the driver into the catalog, preserves the installer's boot
driver order, and sets `rootdev=sd0a`. Once the driver is available on disk,
the installed root is sd0 and the original installer-created fstab is correct.
The second-stage graphical installer can then finish normally.

The script uses OPENSTEP's native shell and utilities. It needs neither GNU tar
nor Developer Tools. Its configuration backup is saved beside the table as
`.virtio-install-backup`. Keep a stopped-disk backup for full rollback.

## Validation

Tested 2026-10-10 using the released VirtioBlk 0.1 binary, stock OPENSTEP 4.2
User CD, stock EIDE 4.01 for the CD, and patched QEMU/SeaBIOS under KVM.
The blank 2 GiB virtio-only disk was detected, partitioned, formatted, and
received the base copy. The graphical installer reported successful completion
and the system reached Workspace without a floppy. The native setup helper
and file copy/compare were checked on a separate copy of that installed disk.
Clean guest shutdowns and read-only filesystem checks passed.

The [validation record](virtio-install-validation.json) contains exact driver,
firmware and floppy hashes.

TCG already has existing VirtioBlk boot coverage, but this direct-install
floppy route has not been tested end to end under TCG.
