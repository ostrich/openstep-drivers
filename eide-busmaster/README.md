# EIDE 4.03 bus-master initialization patch

Get DMA disk transfers while keeping your existing IDE disk and ATAPI CD-ROM
setup. This patch fixes EIDE 4.03's missing PCI bus-master initialization on
QEMU's PIIX3 controller, so enabling Bus Master DMA in Configure works across
cold boots and resets without a host-side launcher workaround. DMA lets the
controller move disk data instead of making the CPU transfer it through PIO.
It is the simplest upgrade if you want to keep an IDE system disk; migrating
to virtio storage is optional.

[Install the packaged driver](README.distribution.txt), or use the patcher below
to modify your own copy of the exact supported EIDE 4.03 binary. Physical
hardware and other controllers have not been tested.

## Building the patch

Enables PCI bus mastering through the original driver's PCI configuration API
when its Bus Master option starts with Y/y. Failed reads, writes or verification
leave software DMA disabled. Existing command bits are preserved and PCI status
bits are not acknowledged accidentally.

Download the original [EIDE 4.03 archive](https://www.nextcomputers.org/NeXTfiles/Software/OPENSTEP/Drivers/Third_Party/i386/other/EIDE-4.03.tar.gz)
from NeXTComputers.org. From this repository's root, extract it into a new
working directory and patch its `EIDE.config/EIDE_reloc` executable:

```sh
mkdir -p work/eide-4.03
tar -xzf /path/to/EIDE-4.03.tar.gz -C work/eide-4.03
python3 eide-busmaster/patch.py \
  work/eide-4.03/EIDE.config/EIDE_reloc \
  work/eide-4.03/EIDE_reloc.patched
```

The output is a patched executable, not an Installer package. For installation,
use the packaged release and its [instructions](README.distribution.txt).
The native package recipe accepts the original and patched executables.

The tested original archive has SHA256
`a201c01e7889c212cbea8f3ee5c465b751e9e34cfd2597c21405e6e4c5c13ada`.
Its executable matches the original hash below, and patching it produces the
listed patched hash.

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
[release preparation](../docs/release-preparation.md) for package repair and validation details.
