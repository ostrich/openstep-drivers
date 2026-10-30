#!/bin/sh
# Change next-boot registration only; never undo a live memory patch.
case "$1" in enable|disable|status) mode=$1;; *) echo 'Usage: kernel-mapping-fix-configure enable|disable|status' >&2; exit 2;; esac
table=/usr/Devices/System.config/Instance0.table
installed=/private/Drivers/i386/KernelMappingFix.config
active=/usr/Devices/KernelMappingFix.config
test -f "$table" || { echo 'System configuration is missing.' >&2; exit 1; }
if test "$mode" != status; then
 test "`/usr/ucb/whoami`" = root || { echo 'Run as root.' >&2; exit 1; }
fi
if test "$mode" = enable; then
 test -f "$installed/KernelMappingFix_reloc" || { echo 'Install the driver first.' >&2; exit 1; }
 test -f "$installed/Instance0.table" || { echo 'Driver configuration is missing.' >&2; exit 1; }
fi
if test "$mode" = status; then
 /bin/awk '
 /^[ \t]*"Boot Drivers"[ \t]*=/ {
  seen++;q=sprintf("%c",34);n=split($0,p,q);if(n!=5)exit 1
  n=split(p[4],d," ");present=0
  for(i=1;i<=n;i++)if(d[i]=="KernelMappingFix")present=1
  if(present)print "enabled for next boot";else print "disabled for next boot"
 }
 END {if(seen!=1)exit 1}
 ' "$table"
 exit $?
fi
umask 077
lock=$table.mapping-fix-lock
if /bin/mkdir "$lock"; then :; else echo 'Configuration is busy.' >&2; exit 1; fi
trap '/bin/rmdir "$lock"; exit 1' 1 2 3 15
tmp=$table.mapping-fix.$$
test ! -f "$tmp" || { /bin/rmdir "$lock"; echo 'Temporary file already exists.' >&2; exit 1; }
if /bin/awk '
{
 q=sprintf("%c",34)
 if($0 ~ /^[ \t]*"Boot Drivers"[ \t]*=/) {
  seen++;n=split($0,p,q);if(n!=5)exit 1
  n=split(p[4],d," ");list="";present=0
  for(i=1;i<=n;i++)if(d[i]!="") {
   if(d[i]=="KernelMappingFix") {present=1;continue}
   if(list!="")list=list " ";list=list d[i]
  }
  if(mode=="enable") {if(list!="")list="KernelMappingFix " list;else list="KernelMappingFix"}
  print q "Boot Drivers" q " = " q list q ";";next
 }
 if(mode!="status")print
}
END {if(seen!=1)exit 1}
' mode="$mode" "$table" > "$tmp"; then :; else
 /bin/rm "$tmp"; echo 'Unsupported Boot Drivers format; unchanged.' >&2; /bin/rmdir "$lock"; exit 1
fi
if test "$mode" = enable; then
 # DriverLoader normally creates the active copy. Boot loading also needs it.
 if test -d "$active"; then
  /bin/cmp "$installed/KernelMappingFix_reloc" "$active/KernelMappingFix_reloc" >/dev/null 2>&1 || { /bin/rm "$tmp"; echo 'Active driver differs; not overwriting it.' >&2; /bin/rmdir "$lock"; exit 1; }
 else
  /bin/cp -R "$installed" "$active" || { /bin/rm "$tmp"; /bin/rmdir "$lock"; exit 1; }
 fi
fi
backup=$table.before-kernel-mapping-fix
if test ! -f "$backup"; then /bin/cp -p "$table" "$backup" || { /bin/rm "$tmp"; /bin/rmdir "$lock"; exit 1; }; fi
# Preserve metadata on the replacement without truncating the existing table.
copy=$table.mapping-copy.$$
test ! -f "$copy" || { /bin/rm "$tmp"; /bin/rmdir "$lock"; exit 1; }
/bin/cp -p "$table" "$copy" || { /bin/rm "$tmp"; /bin/rmdir "$lock"; exit 1; }
/bin/cat "$tmp" > "$copy" || { /bin/rm "$tmp" "$copy"; /bin/rmdir "$lock"; exit 1; }
/bin/mv "$copy" "$table" || { /bin/rm "$tmp" "$copy"; /bin/rmdir "$lock"; exit 1; }
/bin/rm "$tmp"
/bin/sync
echo "KernelMappingFix $mode saved. Reboot to apply this boot configuration."
echo 'An existing in-memory fix remains active until reboot.'

/bin/rmdir "$lock" || exit 1
exit 0
