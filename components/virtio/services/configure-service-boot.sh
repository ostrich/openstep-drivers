#!/bin/sh
# MIT license. Preserve unrelated rc.local entries and the first pre-change copy.
set -e
[ "`/usr/ucb/whoami`" = root ] || { echo 'Run as root.' >&2; exit 1; }
[ "$#" = 1 ] || { echo 'Usage: configure-service-boot.sh enable|disable' >&2; exit 2; }
mode=$1
case "$mode" in enable|disable) ;; *) echo 'Unknown boot action.' >&2; exit 2;; esac
rc=/etc/rc.local
saved=$rc.before-virtio-services
tmp=$rc.virtio-services.$$
if [ "$mode" = enable ]; then
    [ -x /usr/local/sbin/openstep-services ] && [ -f /usr/local/etc/openstep-services.conf ] || {
        echo 'Install the service programs and configuration first.' >&2; exit 1;
    }
fi
trap '/bin/rm -f "$tmp"; exit 1' 1 2 3 15
trap '/bin/rm -f "$tmp"' 0
/bin/cp -p "$rc" "$tmp"
if /bin/awk '
{
    if($0 == "# BEGIN OPENSTEP VIRTIO SERVICES") {
        blocks++
        if(inside || blocks>1)exit 1
        inside=1;next
    }
    if($0 == "# END OPENSTEP VIRTIO SERVICES") {
        if(inside==0)exit 1
        inside=0;next
    }
    if(inside==0)print
}
END {
    if(inside)exit 1
    if(mode=="enable") {
        print "# BEGIN OPENSTEP VIRTIO SERVICES"
        print "if [ -x /usr/local/sbin/openstep-services ]; then"
        print "    if /usr/local/sbin/openstep-services start; then :; else"
        print "        echo \"OPENSTEP virtio services failed to start; inspect /usr/adm/openstep-*.log.\" >&2"
        print "    fi"
        print "fi"
        print "# END OPENSTEP VIRTIO SERVICES"
    }
}
' mode="$mode" "$rc" > "$tmp"; then :; else
    /bin/rm -f "$tmp"
    echo 'Malformed existing service block; rc.local was not changed.' >&2; exit 1
fi
# OPENSTEP's old Bourne shell can loop under -n on existing loop constructs.
# The generated block is fixed; preserve unrelated content without executing it.
if [ ! -f "$saved" ]; then /bin/cp -p "$rc" "$saved"; fi
/bin/mv "$tmp" "$rc"
/bin/sync
echo "Service boot startup $mode saved."
