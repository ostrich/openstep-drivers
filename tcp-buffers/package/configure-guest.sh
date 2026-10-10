#!/bin/sh
# Change only next-boot configuration. Never unload or retune a live module.
set -e
[ "`/usr/ucb/whoami`" = root ] || { echo 'Run as root.' >&2; exit 1; }
[ "$#" = 1 ] || { echo 'Usage: tcp-buffers-configure enable|disable' >&2; exit 2; }
case "$1" in enable) apply=Yes;; disable) apply=No;; *) echo 'Unknown mode.' >&2; exit 2;; esac
mode=$1
table=/usr/Devices/System.config/Instance0.table
installed=/private/Drivers/i386/TCPBuffers.config
active=/usr/Devices/TCPBuffers.config
if [ "$mode" = enable ]; then
 [ -f "$installed/TCPBuffers_reloc" ] || { echo 'Install TCPBuffers.pkg first.' >&2; exit 1; }
fi
[ -f "$table" ] || { echo 'System configuration is missing.' >&2; exit 1; }
tmp=$table.tcp-buffers-tmp.$$
instance=$installed/Instance0.table
itmp=$instance.tmp.$$
trap '/bin/rm -f "$tmp" "$itmp"; exit 1' 1 2 3 15
if /bin/awk '
{
 quote=sprintf("%c",34)
 if($0 ~ /^[ \t]*"Boot Drivers"[ \t]*=/) {
  seen++;n=split($0,p,quote);if(n!=5)exit 1
  n=split(p[4],drivers," ");list=""
  for(i=1;i<=n;i++)if(drivers[i]!="" && drivers[i]!="TCPBuffers") {
   if(list!="")list=list " ";list=list drivers[i]
  }
  if(mode=="enable") { if(list!="")list=list " ";list=list "TCPBuffers"; }
  print quote "Boot Drivers" quote " = " quote list quote ";";next
 }
 print
}
END { if(seen!=1)exit 1 }
' mode="$mode" "$table" > "$tmp"; then :; else
 /bin/rm -f "$tmp";echo 'Unsupported Boot Drivers layout; unchanged.' >&2;exit 1
fi
if [ -f "$instance" ]; then
if /bin/awk '
{
 if($0 ~ /^[ \t]*"Apply TCP Defaults"[ \t]*=/) { seen++;next }
 print
}
END { if(seen>1)exit 1;print "\"Apply TCP Defaults\" = \"" apply "\";" }
' apply="$apply" "$instance" > "$itmp"; then :; else
 /bin/rm -f "$tmp" "$itmp";echo 'Unsupported module configuration; unchanged.' >&2;exit 1
fi
fi
[ -f "$table.tcp-buffers-backup" ] || /bin/cp -p "$table" "$table.tcp-buffers-backup"
if [ -f "$instance" ]; then
[ -f "$instance.before-tcp-buffers" ] || /bin/cp -p "$instance" "$instance.before-tcp-buffers"
/bin/cat "$itmp" > "$instance"
# driverLoader may make active a symlink to installed; avoid self-copy.
if /bin/cmp "$installed/TCPBuffers_reloc" "$active/TCPBuffers_reloc" >/dev/null 2>&1 &&
   /bin/cmp "$installed/Instance0.table" "$active/Instance0.table" >/dev/null 2>&1; then :; else
 /bin/cp -R "$installed" /usr/Devices/
fi
fi
/bin/cat "$tmp" > "$table"
/bin/sync
/bin/rm -f "$tmp" "$itmp"
echo "TCPBuffers $mode saved. Shut down cleanly and cold boot to apply."
