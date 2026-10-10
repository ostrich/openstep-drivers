#!/bin/sh
# Change only the active-driver list; never load/unload a live driver.
set -e
[ "`/usr/ucb/whoami`" = root ] || { echo 'Run as root.' >&2; exit 1; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'Usage: configure-guest.sh enable|disable [1|2 ports]' >&2; exit 2; }
mode=$1
ports=${2-1}
case "$mode" in enable|disable) ;; *) echo 'Unknown mode.' >&2; exit 2;; esac
case "$ports" in 1|2) ;; *) echo 'Port count must be 1 or 2.' >&2; exit 2;; esac
table=/usr/Devices/System.config/Instance0.table
saved=$table.virtio-console-backup
tmp=$table.virtio-console-tmp.$$
trap '/bin/rm -f "$tmp"; exit 1' 1 2 3 15
if [ "$mode" = enable ]; then
    [ -f /private/Drivers/i386/VirtioConsole.config/VirtioConsole_reloc ] || { echo 'Install VirtioConsole.pkg first.' >&2; exit 1; }
    [ -f /usr/adm/virtio-console.lock ] || { echo 'Package lock file is missing.' >&2; exit 1; }
    if [ "$ports" = 2 ]; then
        [ -f /usr/adm/virtio-console2.lock ] || { echo 'Second-port lock file is missing.' >&2; exit 1; }
    fi
fi
if /bin/awk '
{
    quote=sprintf("%c",34)
    if($0 ~ /^[ \t]*"Active Drivers"[ \t]*=/) {
        active++;fields=split($0,part,quote);if(fields!=5)exit 1
        count=split(part[4],driver," ");list=""
        for(i=1;i<=count;i++) {
            if(driver[i]=="" || driver[i]=="VirtioConsole")continue
            if(list!="")list=list " "
            list=list driver[i]
        }
        if(mode=="enable") {
            if(list!="")list=list " "
            list=list "VirtioConsole"
        }
        print quote "Active Drivers" quote " = " quote list quote ";"
        next
    }
    print
}
END { if(active!=1)exit 1 }
' mode="$mode" "$table" > "$tmp"; then :; else
    /bin/rm -f "$tmp"
    echo 'Unsupported System.config layout; configuration was not changed.' >&2; exit 1
fi
if [ ! -f "$saved" ]; then /bin/cp -p "$table" "$saved"; fi
if [ "$mode" = enable ]; then
    installed=/private/Drivers/i386/VirtioConsole.config
    active=/usr/Devices/VirtioConsole.config
    if [ "$#" = 2 ]; then
    instance=$installed/Instance0.table
    instance_tmp=$instance.ports.$$
    if /bin/awk '
    {
        if($0 ~ /^[ \t]*"VirtioConsole Ports"[ \t]*=/) {
            count++;if(count>1)exit 1
            next
        }
        print
    }
    END { if(count<=1)print "\"VirtioConsole Ports\" = \"" ports "\";" }
    ' ports="$ports" "$instance" > "$instance_tmp"; then :; else
        /bin/rm -f "$instance_tmp" "$tmp"
        echo 'Unsupported port configuration; no active-driver change was made.' >&2; exit 1
    fi
    if [ ! -f "$instance.before-ports" ]; then /bin/cp -p "$instance" "$instance.before-ports"; fi
    /bin/cat "$instance_tmp" > "$instance"
    /bin/rm -f "$instance_tmp"
    fi
    # Avoid copying through driverLoader's symlink to the same installed bundle.
    if /bin/cmp "$installed/VirtioConsole_reloc" "$active/VirtioConsole_reloc" >/dev/null 2>&1 &&
       /bin/cmp "$installed/Default.table" "$active/Default.table" >/dev/null 2>&1 &&
       /bin/cmp "$installed/Instance0.table" "$active/Instance0.table" >/dev/null 2>&1 &&
       /bin/cmp "$installed/English.lproj/Localizable.strings" "$active/English.lproj/Localizable.strings" >/dev/null 2>&1; then :; else
        /bin/cp -R "$installed" /usr/Devices/
    fi
fi
/bin/cat "$tmp" > "$table"
/bin/sync
/bin/rm -f "$tmp"
echo "VirtioConsole $mode configuration saved. Shut down cleanly and restart to apply."
