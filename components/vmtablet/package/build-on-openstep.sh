#!/bin/sh
# Build native DriverKit code and Installer metadata on OPENSTEP 4.2.
set -e
if [ "$#" != 3 ]; then
    echo 'Usage: build-on-openstep.sh SOURCE_DIR INFO_FILE NEW_WORK_DIR (absolute paths)' >&2
    exit 2
fi
[ "`/usr/ucb/whoami`" = root ]
source=$1
info=$2
work=$3
[ -f "$source/Makefile" ]
/bin/mkdir "$work"
/bin/cp -R "$source" "$work/source"
cd "$work/source"
make
/bin/mkdir "$work/stage"
/bin/mkdir "$work/stage/private"
/bin/mkdir "$work/stage/private/Drivers"
/bin/mkdir "$work/stage/private/Drivers/i386"
/bin/cp -R VMTablet.config "$work/stage/private/Drivers/i386/VMTablet.config"
/bin/chgrp -R wheel "$work/stage"
/bin/cp "$info" "$work/VMTablet.info"
cd "$work"
/NextAdmin/Installer.app/package stage VMTablet.info
[ -f VMTablet.pkg/VMTablet.bom ]
[ -f VMTablet.pkg/VMTablet.tar.Z ]
/usr/ucb/zcat VMTablet.pkg/VMTablet.tar.Z > payload.tar
/NextAdmin/Installer.app/installer_tar tf payload.tar > payload-files.txt
/usr/local/ssl/bin/openssl dgst -sha256 "$work/source/VMTablet.config/VMTablet_reloc"
