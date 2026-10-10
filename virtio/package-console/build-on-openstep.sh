#!/bin/sh
# Native OPENSTEP 4.2 Developer Tools, as root; absolute arguments.
set -e
[ "$#" = 3 ] || { echo 'Usage: build-on-openstep.sh SOURCE_ROOT INFO_FILE NEW_WORK_DIR' >&2; exit 2; }
[ "`/usr/ucb/whoami`" = root ]
source=$1
info=$2
work=$3
/bin/mkdir "$work"
/bin/cp -R "$source" "$work/source"
cd "$work/source/VirtioConsole"
make clean
make TESTFLAGS=
/bin/mkdir "$work/stage"
/bin/mkdir "$work/stage/private" "$work/stage/usr"
/bin/mkdir "$work/stage/private/Drivers" "$work/stage/usr/local" "$work/stage/usr/adm"
/bin/mkdir "$work/stage/private/Drivers/i386" "$work/stage/usr/local/bin"
/bin/cp -R VirtioConsole.config "$work/stage/private/Drivers/i386/"
/bin/cp virtio-console "$work/stage/usr/local/bin/"
: > "$work/stage/usr/adm/virtio-console.lock"
: > "$work/stage/usr/adm/virtio-console2.lock"
/bin/chgrp -R wheel "$work/stage"
/bin/chmod 644 "$work/stage/usr/adm/virtio-console.lock"
/bin/chmod 644 "$work/stage/usr/adm/virtio-console2.lock"
/bin/chmod 755 "$work/stage/usr/local/bin/virtio-console"
/bin/cp "$info" "$work/VirtioConsole.info"
cd "$work"
/NextAdmin/Installer.app/package stage VirtioConsole.info
[ -s VirtioConsole.pkg/VirtioConsole.bom ]
[ -s VirtioConsole.pkg/VirtioConsole.tar.Z ]
/usr/ucb/zcat VirtioConsole.pkg/VirtioConsole.tar.Z > payload.tar
/NextAdmin/Installer.app/installer_tar tf payload.tar > payload-files.txt
