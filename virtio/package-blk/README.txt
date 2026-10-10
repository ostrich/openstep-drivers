VirtioBlk 0.1 - block storage for OPENSTEP 4.2 Intel

Run your system and data disks on QEMU's virtio storage interface. The driver
supports direct system boot, so you can use virtio for the whole installation.
Its 64 KiB transfers delivered faster reads than bus-master EIDE in matched
KVM warm-cache tests. Durable writes in those tests remained faster with EIDE;
application and host-storage results will vary. Keep EIDE for the CD-ROM if
needed, or try a secondary virtio disk before migrating the system disk.

Validated for continued use and direct system boot in the configuration below.
Back up your disks before installation or migration.
Transfers use a 64 KiB scatter/gather buffer; read/write integrity, error
recovery and system boot are verified under KVM and TCG.

Requirements
QEMU pc/i440fx, one virtual CPU, transitional virtio PCI with legacy INTx,
512-byte logical sectors and a backend supporting FLUSH. Use a 128-entry
queue to conserve DMA memory when running several virtio devices together.
One disk per controller; capacity must fit 32-bit sector addressing (under
2 TiB). Validation uses 2 GiB system and 64 MiB data disks; larger filesystems
were not tested. Tests use the project's patched QEMU 11.1.1 under KVM and TCG.
Boot migration below requires an existing hd0a system disk and no
other SCSI disk controller. Live unloading, hotplug and online capacity
changes are unsupported. Developer Tools are needed only to rebuild.

Installation
1. Shut down cleanly and back up the disks and launch configuration on the
   host. Keep this stopped-disk backup for recovery from a failed boot.
2. Extract VirtioBlk-0.1.pkg.I.tar.gz on the host and in the guest using
   gnutar -xzf. Open VirtioBlk.pkg in Installer as root; OpenSesame can
   elevate Installer. Install at /, selecting Intel and English.
3. From the extracted directory in a root guest Terminal, select one mode:
       sh configure-guest.sh secondary
       sh configure-guest.sh boot
   Secondary adds the driver while keeping the existing boot controller.
   Boot selects early loading after PCIBus, removes EIDE from Boot Drivers,
   sets rootdev=sd0a and changes the root fstab entry to /dev/sd0a. Other
   drivers and kernel flags are preserved. Both modes save the original
   System.config table and fstab as .virtio-ide-backup files beside them.
4. Shut down cleanly before changing the host launch command.

Host configuration
PCI slot 7 must be free. Instance0.table's Location must match
"Dev:7 Func:0 Bus:0". For a secondary disk, add:
    -drive if=none,id=vdisk,file=DATA.raw,format=raw,cache=writeback
    -device virtio-blk-pci-transitional,addr=7,queue-size=128,drive=vdisk
For system boot, replace the IDE hard-disk attachment with:
    -drive if=none,id=vdisk,file=SYSTEM.raw,format=raw,cache=writeback
    -device virtio-blk-pci-transitional,addr=7,queue-size=128,drive=vdisk,bootindex=1
    -bios VirtioBlk-firmware/bios.bin
    -fw_cfg name=etc/virtio-low-queues,string=on
Keep the remaining machine/device options. Do not attach the same image
through IDE as well. The BIOS path is relative to the extracted host archive.
Its low-memory queues avoid the original booter's destructive RAM test;
no original OPENSTEP executable is patched. Both KVM and TCG are supported.

Verification and recovery
Boot messages identify the actual scN/sdN device. Secondary disk numbering
varies; identify the disk before formatting it. System boot should mount
/dev/sd0a at /. Check status with /usr/local/bin/virtio-blkctl --stats.

A failed or timed-out write may have changed disk contents. The driver
returns an error, blocks further I/O and does not replay uncertain writes.
Fix the underlying backend failure before recovery. Unmount secondary
filesystems before an administrative virtio-blkctl --reset (root), then fsck
before remounting. For a failed root disk, fix the backend and cold boot with
-s rootdev=sd0a at the boot prompt. Confirm /dev/sd0a with df /, then run:
    /usr/etc/fsck -y /dev/sd0a
    /usr/etc/reboot -n
OPENSTEP remounts root read-write in single-user mode. This root repair route
is for the single-user console before background services start. Reboot
immediately afterward; if fsck requests REBOOT THE SYSTEM (NO SYNC), do not
run sync or continue into multiuser mode. Unmount secondary filesystems before
checking them; do not repair root from a multiuser session.
Logging covers startup and actionable failures, not
individual requests.

Rollback
In the root guest Terminal, run sh configure-guest.sh rollback. Shut down
cleanly, restore the original IDE attachment and BIOS options, then restart.
For a boot failure that prevents this, restore the stopped-disk backup and
original launch configuration. Keep the failed image separately for recovery.

Source and licenses
The native driver source and MIT license are in VirtioBlk-source/:
    cd VirtioBlk-source/VirtioBlk
    make
Outputs are VirtioBlk.config and virtio-blkctl. SeaBIOS has separate LGPLv3
terms; VirtioBlk-firmware/ includes its licenses, complete corresponding
source, applied patch, configuration, build instructions and checksum.
