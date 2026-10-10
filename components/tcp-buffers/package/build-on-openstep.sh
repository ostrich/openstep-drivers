#!/bin/sh
# Root, native OPENSTEP 4.2 Developer Tools. All arguments are absolute paths.
set -e
[ "$#" = 3 ] || { echo 'Usage: build-on-openstep.sh SOURCE_ROOT INFO_FILE NEW_WORK_DIR' >&2; exit 2; }
[ "`/usr/ucb/whoami`" = root ]
source=$1
info=$2
work=$3
case "$work/" in "$source/"*) echo "Build output must be outside SOURCE_ROOT." >&2; exit 2;; esac
/bin/mkdir "$work"
/bin/cp -R "$source" "$work/source"
cd "$work/source/TCPBuffers"
make TESTFLAGS=
/bin/mkdir "$work/stage"
/bin/mkdir "$work/stage/private" "$work/stage/usr"
/bin/mkdir "$work/stage/private/Drivers" "$work/stage/usr/local"
/bin/mkdir "$work/stage/private/Drivers/i386" "$work/stage/usr/local/bin" "$work/stage/usr/local/sbin"
/bin/cp -R TCPBuffers.config "$work/stage/private/Drivers/i386/"
/bin/cp tcp-buffersctl "$work/stage/usr/local/bin/"
/bin/cp "$source/package/configure-guest.sh" "$work/stage/usr/local/sbin/tcp-buffers-configure"
/bin/chgrp -R wheel "$work/stage"
/bin/chmod 755 "$work/stage/usr/local/bin/tcp-buffersctl" "$work/stage/usr/local/sbin/tcp-buffers-configure"
/bin/cp "$info" "$work/TCPBuffers.info"
cd "$work"
/NextAdmin/Installer.app/package stage TCPBuffers.info
[ -s TCPBuffers.pkg/TCPBuffers.bom ]
[ -s TCPBuffers.pkg/TCPBuffers.tar.Z ]
/usr/ucb/zcat TCPBuffers.pkg/TCPBuffers.tar.Z > payload.tar
/NextAdmin/Installer.app/installer_tar tf payload.tar > payload-files.txt
