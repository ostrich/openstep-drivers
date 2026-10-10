#!/bin/sh
# MIT license. Build using native Developer Tools and Installer.app/package.
set -e
[ "$#" = 3 ] || { echo 'Usage: build-on-openstep.sh SOURCE_ROOT INFO_FILE NEW_WORK_DIR' >&2; exit 2; }
[ "`/usr/ucb/whoami`" = root ]
source=$1
info=$2
work=$3
/bin/mkdir "$work"
/bin/cp -R "$source" "$work/source"
cd "$work/source/services"
make clean
make
/bin/mkdir "$work/stage"
/bin/mkdir "$work/stage/usr" "$work/stage/usr/local"
/bin/mkdir "$work/stage/usr/local/sbin" "$work/stage/usr/local/libexec" "$work/stage/usr/local/etc"
/bin/cp openstep-qga openstep-pty openstep-services "$work/stage/usr/local/sbin/"
/bin/cp openstep-agent-file "$work/stage/usr/local/libexec/"
/bin/cp configure-service-boot.sh "$work/stage/usr/local/libexec/"
/bin/cp openstep-services.conf "$work/stage/usr/local/etc/openstep-services.conf.example"
/bin/chgrp -R wheel "$work/stage"
/bin/chmod 755 "$work/stage/usr/local/sbin/openstep-qga" "$work/stage/usr/local/sbin/openstep-pty" "$work/stage/usr/local/sbin/openstep-services"
/bin/chmod 755 "$work/stage/usr/local/libexec/openstep-agent-file" "$work/stage/usr/local/libexec/configure-service-boot.sh"
/bin/chmod 644 "$work/stage/usr/local/etc/openstep-services.conf.example"
/bin/cp "$info" "$work/OpenStepVirtioServices.info"
cd "$work"
/NextAdmin/Installer.app/package stage OpenStepVirtioServices.info
[ -s OpenStepVirtioServices.pkg/OpenStepVirtioServices.bom ]
[ -s OpenStepVirtioServices.pkg/OpenStepVirtioServices.tar.Z ]
/usr/ucb/zcat OpenStepVirtioServices.pkg/OpenStepVirtioServices.tar.Z > payload.tar
/NextAdmin/Installer.app/installer_tar tf payload.tar > payload-files.txt
