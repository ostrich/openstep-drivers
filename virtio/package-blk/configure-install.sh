#!/bin/sh
# Finish a direct installation from single-user mode using this driver floppy.
set -e
[ "$#" = 1 ] || { echo 'Usage: sh configure-install.sh /dev/sd1a' >&2; exit 2; }
[ "`/usr/ucb/whoami`" = root ]
case "$1" in /dev/sd[0-3]a) ;; *) echo 'Expected an installed SCSI root device.' >&2; exit 2;; esac
source=`/bin/expr "$0" : '\(.*\)/[^/]*$'`/private/Drivers/i386/VirtioBlk.config
[ -s "$source/VirtioBlk_reloc" ]
table=/private/Drivers/i386/System.config/Default.table
if [ -s /private/Drivers/i386/System.config/Instance0.table ]; then
    table=/private/Drivers/i386/System.config/Instance0.table
fi
[ -s "$table" ]
echo 'Remounting the installed root filesystem read/write...'
/usr/etc/mount -o remount "$1" /
echo 'Copying VirtioBlk into the installed driver catalog...'
if [ -d /private/Drivers/i386/VirtioBlk.config ]; then
    echo 'VirtioBlk is already present; preserving its files.'
else
    /bin/cp -R "$source" /private/Drivers/i386/
fi
/bin/cmp "$source/VirtioBlk_reloc" /private/Drivers/i386/VirtioBlk.config/VirtioBlk_reloc
if [ ! -f "$table.virtio-install-backup" ]; then
    /bin/cp "$table" "$table.virtio-install-backup"
fi
drivers=`sed -n 's/^"Boot Drivers" = "\(.*\)";.*/\1/p' "$table"`
flags=`sed -n 's/^"Kernel Flags" = "\(.*\)";.*/\1/p' "$table"`
# The installer already records its controller choices. Preserve that order;
# moving entries can change which controller becomes sc0 at the next boot.
ordered="$drivers"
found=no
virtio=no
for driver in $drivers; do
    if [ "$driver" = PCIBus ]; then found=yes; fi
    if [ "$driver" = VirtioBlk ]; then virtio=yes; fi
done
[ "$found" = yes ] || { echo 'PCIBus is missing from Boot Drivers.' >&2; exit 1; }
if [ "$virtio" = no ]; then ordered="VirtioBlk $drivers"; fi
newflags=
for flag in $flags; do
    case "$flag" in rootdev=*|-s) ;; *) newflags="$newflags $flag";; esac
done
newflags="$newflags rootdev=sd0a"
ordered=`echo "$ordered" | sed 's/^ *//'`
newflags=`echo "$newflags" | sed 's/^ *//'`
sed '/"Boot Drivers"/d; /"Kernel Flags"/d' "$table" > /private/tmp/virtio-install.table
echo "\"Boot Drivers\" = \"$ordered\";" >> /private/tmp/virtio-install.table
echo "\"Kernel Flags\" = \"$newflags\";" >> /private/tmp/virtio-install.table
/bin/cp /private/tmp/virtio-install.table "$table"
sync
echo 'VirtioBlk is installed. Unmount the floppy, halt, and boot from disk.'
