# Release preparation

The 2026-10-10 rebuild uses the flattened source tree and current installation
READMEs. All eight native driver/service packages were rebuilt with OPENSTEP's
Developer Tools; EIDE was repackaged from the verified original driver and
reproducible binary patch. See [rebuild records](rebuild-20261010.json).

Every installed file matches its previously tested release byte for byte.
Existing KVM/TCG boot, integrity and sustained-load validation therefore applies
to the rebuilt binaries. No new runtime or sustained-load tests were performed
for this rebuild. Portable checks and native payload inspection were rerun.
The separately validated SeaBIOS binary and corresponding source were reused.

Future release work:

1. Declare reuse licenses for VMTablet and EIDE patch tooling; see
   [current licensing](licenses.md).
2. Broaden installation/rollback coverage.
3. Decide whether VirtioBlk should continue bundling firmware or use only the
   firmware shipped by openstep-qemu.

Versions remain unchanged. Local downloads are under `dist/`; binary downloads
belong in Releases, not Git history. The older [package reconciliation record](package-reconciliation.json)
describes the earlier EIDE/services repair, not this rebuilt release.

## Efficient rebuilds

Freeze the source and hash every input before transferring it. Boot one
reflink copy of a stopped Developer Tools guest under KVM, upload once, and
run each component's native package recipe sequentially in a separate new
build directory. Capture compiler output and retrieve packages and build source
in one archive per component. Build VirtioConsole as an input to the combined
services archive; do not publish a redundant standalone console archive.

Compare decompressed installed payloads with the tested release, then validate
source hashes and assemble archives on the host. If executable or device
configuration bytes differ, run the affected guest tests before promotion.
When every installed byte matches, retain prior runtime evidence and state
explicitly that it was reused. Record a shared source snapshot identifier,
per-package payload and content hashes, then promote all archives together.
Keep the old downloads in ignored `work/` until the new set is validated.
