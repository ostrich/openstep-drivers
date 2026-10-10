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
/usr/ucb/zcat "$original/EIDE.tar.Z" > "$work/original.tar"
cd "$work/stage"
gnutar xf "$work/original.tar"
bundle="$work/stage/private/Drivers/i386/EIDE.config"
[ -s "$bundle/EIDE_reloc" ]
# Finder directory caches are not driver inputs.
/bin/rm -f "$bundle/.dir3_0.wmd"
/bin/cp "$bundle/EIDE_reloc" "$bundle/EIDE_reloc.original"
/bin/cp "$patched" "$bundle/EIDE_reloc"
/bin/chmod 644 "$bundle/EIDE_reloc" "$bundle/EIDE_reloc.original"
/bin/chgrp -R wheel "$work/stage"
cd "$work"
/NextAdmin/Installer.app/package stage EIDEBusMaster.info
[ -f "$work/EIDEBusMaster.pkg/EIDEBusMaster.bom" ]
[ -f "$work/EIDEBusMaster.pkg/EIDEBusMaster.tar.Z" ]
/usr/ucb/zcat "$work/EIDEBusMaster.pkg/EIDEBusMaster.tar.Z" > "$work/payload.tar"
/NextAdmin/Installer.app/installer_tar tf "$work/payload.tar" > "$work/payload-files.txt"
# The package tool can succeed after a failed/empty extraction. Require both
# executables in the generated native payload, not only in the staging tree.
/bin/grep 'private/Drivers/i386/EIDE.config/EIDE_reloc[ 	]*$' "$work/payload-files.txt"
/bin/grep 'private/Drivers/i386/EIDE.config/EIDE_reloc.original[ 	]*$' "$work/payload-files.txt"
/usr/local/ssl/bin/openssl dgst -sha256 "$bundle/EIDE_reloc" "$bundle/EIDE_reloc.original"
