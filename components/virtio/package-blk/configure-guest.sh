#!/bin/sh
# Configure an installed driver on OPENSTEP. Never formats or moves disk data.
set -e
[ "`/usr/ucb/whoami`" = root ] || { echo 'Run as root.' >&2; exit 1; }
[ "$#" = 1 ] || { echo 'Usage: configure-guest.sh secondary|boot|rollback' >&2; exit 2; }
mode=$1
case "$mode" in secondary|boot|rollback) ;; *) echo 'Unknown mode.' >&2; exit 2;; esac
table=/usr/Devices/System.config/Instance0.table
fstab=/etc/fstab
saved_table=$table.virtio-ide-backup
saved_fstab=$fstab.virtio-ide-backup
if [ "$mode" = rollback ]; then
    [ -f "$saved_table" ] && [ -f "$saved_fstab" ] || { echo 'Both original backups are required.' >&2; exit 1; }
    /bin/cp -p "$saved_table" "$table"
    /bin/cp -p "$saved_fstab" "$fstab"
    /bin/sync
    echo 'Original configuration restored. Shut down cleanly, restore the IDE host disk attachment and restart.'
    exit 0
fi
[ -f /private/Drivers/i386/VirtioBlk.config/VirtioBlk_reloc ] || { echo 'Install VirtioBlk.pkg first.' >&2; exit 1; }
if [ "$mode" = boot ]; then
    baseline=$fstab
    if [ -f "$saved_fstab" ]; then baseline=$saved_fstab; fi
    if /bin/awk '$1=="/dev/hd0a" && $2=="/" { roots++ } END { if(roots!=1)exit 1 }' "$baseline"; then :; else
        echo 'Boot migration requires an original hd0a root configuration.' >&2; exit 1
    fi
fi
tmp=$table.virtio-tmp.$$
fstmp=$fstab.virtio-tmp.$$
trap '/bin/rm -f "$tmp" "$fstmp"; exit 1' 1 2 3 15
# Require one-line ordinary DriverKit settings; preserve every unrelated key.
if /bin/awk '
{
    quote=sprintf("%c",34)
    fields=split($0,part,quote)
    if($0 ~ /^[ \t]*"Active Drivers"[ \t]*=/) {
        active++;if(fields!=5)exit 1
        count=split(part[4],driver," ");list=""
        for(i=1;i<=count;i++) {
            if(driver[i]=="" || driver[i]=="VirtioBlk")continue
            if(list!="")list=list " "
            list=list driver[i]
        }
        if(mode=="secondary") {
            if(list!="")list=list " "
            list=list "VirtioBlk"
        }
        print quote "Active Drivers" quote " = " quote list quote ";"
        next
    }
    if($0 ~ /^[ \t]*"Boot Drivers"[ \t]*=/) {
        boot++;if(fields!=5)exit 1
        if(mode=="boot") {
            count=split(part[4],driver," ");list=""
            for(i=1;i<=count;i++) {
                if(driver[i]=="" || driver[i]=="EIDE" || driver[i]=="VirtioBlk")continue
                if(list!="")list=list " "
                list=list driver[i]
                if(driver[i]=="PCIBus") { pci++;list=list " VirtioBlk" }
            }
            print quote "Boot Drivers" quote " = " quote list quote ";"
            next
        }
        if(part[4] ~ /(^|[ \t])VirtioBlk([ \t]|$)/)exit 1
    }
    if($0 ~ /^[ \t]*"Kernel Flags"[ \t]*=/ && mode=="boot") {
        flags++;if(fields!=5)exit 1
        count=split(part[4],flag," ");list=""
        for(i=1;i<=count;i++) {
            if(flag[i]=="" || flag[i] ~ /^rootdev=/)continue
            if(list!="")list=list " "
            list=list flag[i]
        }
        if(list!="")list=list " "
        list=list "rootdev=sd0a"
        print quote "Kernel Flags" quote " = " quote list quote ";"
        next
    }
    if($0 ~ /^[ \t]*"Boot Graphics"[ \t]*=/ && mode=="boot") {
        print quote "Boot Graphics" quote " = " quote "No" quote ";"
        next
    }
    print
}
END { if(active!=1 || boot!=1 || (mode=="boot" && (flags!=1 || pci!=1)))exit 1 }
' mode="$mode" "$table" > "$tmp"; then :; else
    /bin/rm -f "$tmp" "$fstmp"
    echo 'Unsupported System.config layout; configuration was not changed.' >&2; exit 1
fi
if [ "$mode" = boot ]; then
    if /bin/awk '
    ($1=="/dev/hd0a" || $1=="/dev/sd0a") && $2=="/" { roots++;$1="/dev/sd0a";print;next }
    { print }
    END { if(roots!=1)exit 1 }
    ' "$fstab" > "$fstmp"; then :; else
        /bin/rm -f "$tmp" "$fstmp"
        echo 'Expected one hd0a or sd0a root entry in fstab; configuration was not changed.' >&2; exit 1
    fi
fi
if [ -f "$saved_table" ] || [ -f "$saved_fstab" ]; then
    [ -f "$saved_table" ] && [ -f "$saved_fstab" ] || { /bin/rm -f "$tmp" "$fstmp"; echo 'Incomplete original backup pair; configuration was not changed.' >&2; exit 1; }
else
    /bin/cp -p "$table" "$saved_table"
    /bin/cp -p "$fstab" "$saved_fstab"
fi
installed=/private/Drivers/i386/VirtioBlk.config
active=/usr/Devices/VirtioBlk.config
# driverLoader may already have created a symlink to the installed bundle.
if /bin/cmp "$installed/VirtioBlk_reloc" "$active/VirtioBlk_reloc" >/dev/null 2>&1 &&
   /bin/cmp "$installed/Default.table" "$active/Default.table" >/dev/null 2>&1 &&
   /bin/cmp "$installed/Instance0.table" "$active/Instance0.table" >/dev/null 2>&1 &&
   /bin/cmp "$installed/English.lproj/Localizable.strings" "$active/English.lproj/Localizable.strings" >/dev/null 2>&1; then :; else
    /bin/cp -R "$installed" /usr/Devices/
fi
/bin/cat "$tmp" > "$table"
if [ "$mode" = boot ]; then /bin/cat "$fstmp" > "$fstab"; fi
/bin/sync
/bin/rm -f "$tmp" "$fstmp"
echo "VirtioBlk $mode configuration saved. Shut down cleanly before changing the host disk attachment."
