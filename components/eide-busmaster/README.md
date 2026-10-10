# EIDE 4.03 bus-master initialization patch

Enables PCI bus mastering through the original driver's PCI configuration API
when its Bus Master option starts with Y/y. Failed reads, writes or verification
leave software DMA disabled. Existing command bits are preserved and PCI status
bits are not acknowledged accidentally.

```sh
python3 components/eide-busmaster/patch.py ORIGINAL_EIDE_reloc PATCHED_EIDE_reloc
```

Requires Python 3 and GNU `as`. The input is checked by SHA256 and never modified;
the output must be a new file. Other EIDE versions and already-patched inputs
are rejected.

- Original: `8d9bc6da3a57f53a57d68e44e3b2a9d67707a5fe881a06477c35f94a217552a5`
- Patched: `aa3582fdafa70ee62f2384ee66632d5879f2ffd70851ce0b2b9f0c37a71f6f12`

The patch redirects seven bytes at `probePCIController:+0x3d5` to a 155-byte
routine in unused `__TEXT` padding. It adds Mach-O relocations while preserving
original section addresses, symbols and methods.

[Installation and rollback](README.distribution.txt) describes the native
package. `build-package-on-openstep.sh` creates it on OPENSTEP;
`distribute-package.py` validates and wraps it. The original driver is not
included in the source checkout. Reinstallation of the original package can
replace the patched executable.

`test-patch.py ORIGINAL_EIDE_reloc` executes the patch under mocked PCI APIs
using Python Unicorn. It supplements guest validation. See
[release preparation](../../docs/release-preparation.md) for package repair and validation details.
