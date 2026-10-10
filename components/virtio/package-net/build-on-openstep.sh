#!/bin/sh
# Root, native OPENSTEP 4.2 Developer Tools. All arguments are absolute paths.
set -e
[ "$#" = 3 ] || { echo 'Usage: build-on-openstep.sh SOURCE_ROOT INFO_FILE NEW_WORK_DIR' >&2; exit 2; }
[ "`/usr/ucb/whoami`" = root ]
source=$1
info=$2
work=$3
/bin/mkdir "$work"
/bin/cp -R "$source" "$work/source"
cd "$work/source/drivers/VirtioNet"
make clean
make TESTFLAGS=
/bin/mkdir "$work/stage"
/bin/mkdir "$work/stage/private" "$work/stage/usr"
/bin/mkdir "$work/stage/private/Drivers" "$work/stage/usr/local"
/bin/mkdir "$work/stage/private/Drivers/i386" "$work/stage/usr/local/bin"
/bin/cp -R VirtioNet.config "$work/stage/private/Drivers/i386/"
/bin/cp virtio-netctl "$work/stage/usr/local/bin/"
/bin/chgrp -R wheel "$work/stage"
/bin/chmod 755 "$work/stage/usr/local/bin/virtio-netctl"
/bin/cp "$info" "$work/VirtioNet.info"
cd "$work"
/NextAdmin/Installer.app/package stage VirtioNet.info
[ -s VirtioNet.pkg/VirtioNet.bom ]
[ -s VirtioNet.pkg/VirtioNet.tar.Z ]
/usr/ucb/zcat VirtioNet.pkg/VirtioNet.tar.Z > payload.tar
/NextAdmin/Installer.app/installer_tar tf payload.tar > payload-files.txt
