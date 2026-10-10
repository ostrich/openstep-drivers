# Release preparation

The source export preserves native driver inputs. The existing distribution
packages are reference artifacts, not a rebuild from this checkout.

Before publishing driver downloads:

1. Resolve VMTablet and EIDE patch-tool licensing.
2. Rebuild packages from a clean source snapshot and record compiler versions,
   native source hashes, payload hashes and guest validation results.
3. Reconcile the host agent client's newer synchronization behavior with the
   existing services archive. Test the resulting client and guest as a pair.
4. Resolve the EIDE distributor's rejection of the package's top-level `.`
   entry with gid 20. Preserve the exact original and patched driver hashes.
5. Update VirtioBlk boot instructions to use firmware from openstep-qemu;
   remove duplicate host patch payloads from the services distribution.
6. Validate installation and rollback, quiet release diagnostics, KVM and TCG,
   and a complete source-to-package manifest for each promoted artifact.

Do not change tested driver version numbers merely for this source export.
Binary downloads belong in Releases, not Git history. Guest build inputs and
host runtime artifacts stay outside the source tree.
