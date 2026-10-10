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
cd "$work/source/drivers/VirtioBlk"
make clean
make TESTFLAGS=
/bin/mkdir "$work/stage"
/bin/mkdir "$work/stage/private" "$work/stage/usr"
/bin/mkdir "$work/stage/private/Drivers" "$work/stage/usr/local"
/bin/mkdir "$work/stage/private/Drivers/i386" "$work/stage/usr/local/bin"
/bin/cp -R VirtioBlk.config "$work/stage/private/Drivers/i386/"
/bin/cp virtio-blkctl "$work/stage/usr/local/bin/"
/bin/chgrp -R wheel "$work/stage"
/bin/chmod 755 "$work/stage/usr/local/bin/virtio-blkctl"
/bin/cp "$info" "$work/VirtioBlk.info"
cd "$work"
/NextAdmin/Installer.app/package stage VirtioBlk.info
[ -s VirtioBlk.pkg/VirtioBlk.bom ]
[ -s VirtioBlk.pkg/VirtioBlk.tar.Z ]
/usr/ucb/zcat VirtioBlk.pkg/VirtioBlk.tar.Z > payload.tar
/NextAdmin/Installer.app/installer_tar tf payload.tar > payload-files.txt
