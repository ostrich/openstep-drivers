#!/bin/sh
# Run as root with native OPENSTEP 4.2 Developer Tools.
set -e
[ "$#" = 3 ] || { echo 'Usage: build-on-openstep.sh SOURCE_DIR INFO_FILE NEW_WORK_DIR' >&2; exit 2; }
[ "`/usr/ucb/whoami`" = root ]
source=$1
info=$2
work=$3
/bin/mkdir "$work"
/bin/cp -R "$source" "$work/source"
cd "$work/source"
make clean
make
/bin/mkdir "$work/stage"
/bin/mkdir "$work/stage/private" "$work/stage/usr"
/bin/mkdir "$work/stage/private/Drivers" "$work/stage/usr/lib"
/bin/mkdir "$work/stage/private/Drivers/i386" "$work/stage/usr/lib/NextStep"
/bin/mkdir "$work/stage/usr/lib/NextStep/Displays"
/bin/cp -R VMWareFB.config "$work/stage/private/Drivers/i386/VMWareFB.config"
/bin/cp VMWareFB_psdrvr "$work/stage/usr/lib/NextStep/Displays/VMWareFB_psdrvr"
/bin/chgrp -R wheel "$work/stage"
/bin/chmod -R go-w "$work/stage"
/bin/cp "$info" "$work/VMWareFB.info"
cd "$work"
/NextAdmin/Installer.app/package stage VMWareFB.info
[ -s VMWareFB.pkg/VMWareFB.bom ]
[ -s VMWareFB.pkg/VMWareFB.tar.Z ]
/usr/ucb/zcat VMWareFB.pkg/VMWareFB.tar.Z > payload.tar
/NextAdmin/Installer.app/installer_tar tf payload.tar > payload-files.txt
