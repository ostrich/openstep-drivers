#!/bin/sh
# Run as root on OPENSTEP 4.2. All output stays under the supplied work dir.
set -e
if [ "$#" != 4 ]; then
    echo 'Usage: build-package-on-openstep.sh ORIGINAL.pkg PATCHED_EIDE_reloc INFO_FILE NEW_WORK_DIR' >&2
    exit 2
fi
if [ "`/usr/ucb/whoami`" != root ]; then
    echo 'Run as root so package ownership and its bill of materials are correct.' >&2
    exit 1
fi
original=$1
patched=$2
info=$3
work=$4
[ -f "$original/EIDE.tar.Z" ]
[ -f "$patched" ]
[ -f "$info" ]
# mkdir must fail if work already exists; never reuse a stale stage/package.
/bin/mkdir "$work"
/bin/mkdir "$work/stage"
/bin/chgrp wheel "$work/stage"
/bin/cp "$info" "$work/EIDEBusMaster.info"
cd "$work/stage"
/usr/ucb/zcat "$original/EIDE.tar.Z" | /NextAdmin/Installer.app/installer_bigtar xf -
bundle="$work/stage/private/Drivers/i386/EIDE.config"
[ -f "$bundle/EIDE_reloc" ]
/bin/cp "$bundle/EIDE_reloc" "$bundle/EIDE_reloc.original"
/bin/cp "$patched" "$bundle/EIDE_reloc"
/bin/chmod 644 "$bundle/EIDE_reloc" "$bundle/EIDE_reloc.original"
cd "$work"
/NextAdmin/Installer.app/package stage EIDEBusMaster.info
[ -f "$work/EIDEBusMaster.pkg/EIDEBusMaster.bom" ]
[ -f "$work/EIDEBusMaster.pkg/EIDEBusMaster.tar.Z" ]
/usr/ucb/zcat "$work/EIDEBusMaster.pkg/EIDEBusMaster.tar.Z" > "$work/payload.tar"
/NextAdmin/Installer.app/installer_tar tf "$work/payload.tar" > "$work/payload-files.txt"
/usr/local/ssl/bin/openssl dgst -sha256 "$bundle/EIDE_reloc" "$bundle/EIDE_reloc.original"
