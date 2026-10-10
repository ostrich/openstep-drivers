# Release preparation

The source export preserves native driver inputs. Reconciled EIDE and services
archives are assembled from verified native packages, not newly compiled guest
binaries. Their hashes and checks are in [package reconciliation](package-reconciliation.json).

Before publishing driver downloads:

1. Resolve VMTablet and EIDE patch-tool licensing.
2. Rebuild packages from a clean source snapshot and record compiler versions,
   native source hashes, payload hashes and guest validation results.
3. Update VirtioBlk boot instructions to use firmware from openstep-qemu;
   remove duplicate host patch payloads from the services distribution.
4. Validate installation and rollback, quiet release diagnostics, KVM and TCG,
   and a complete source-to-package manifest for each promoted artifact.

Do not change tested driver version numbers merely for this source export.
Binary downloads belong in Releases, not Git history. Guest build inputs and
host runtime artifacts stay outside the source tree.

## Completed package repairs

The previous EIDE archive had only an empty directory in its native payload,
following a directory-checksum extraction error. The complete recorded package
was recovered and validated: it contains 21 files, including the original and
patched executables with their required hashes. Re-running the exported patcher
on the original reproduces the packaged patched executable exactly. The native
build recipe now uses GNU tar for extraction and rejects generated packages
without both executables. Its revised extraction step has not been rerun in a
guest; the repaired archive uses the existing complete native package.

The services archive now includes the current agent and PTY clients. Every
native source hash matches the recorded native builds; all eight native package
files match the previous distribution byte-for-byte. Host socket regressions
cover duplicate synchronization replies, invalid delimiters, fragmentation and
no replay of failed commands. Archive contents and internal checksums validate.
No new guest install or boot test was performed for this archive-only update.

Versions remain unchanged. The repaired archives are local under `dist/`.
