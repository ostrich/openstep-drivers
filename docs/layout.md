# Repository layout

Each component lives at the repository root:

```text
vmtablet/          Absolute pointer driver and package
vmwarefb/          SVGA driver, package and graphics tests
virtio/
  VirtioBlk/       Storage driver
  VirtioConsole/   Console driver
  VirtioNet/       Network driver
  VirtioRNG/       Entropy driver
  src/            Shared PCI transport, queues and protocol helpers
  services/       Guest agent and PTY services
  tools/          Host clients and distribution assembly
  tests/          Queue and host-client tests
  package*/       Native Installer recipes and installation READMEs
tcp-buffers/       TCP defaults module and package
eide-busmaster/    Binary patcher, package recipe and tests
scripts/          Repository checks and driver-floppy builder
docs/             Build, installation and release documentation
dist/             Generated downloads, ignored by Git
work/             Temporary builds and test outputs, ignored by Git
```

Tests live with the component they exercise. `scripts/check.py` runs the
portable suite from one command. `manifest.json` indexes native build and
package entry points.

Keep the virtio family together when copying it to an OPENSTEP build guest.
Its driver Makefiles and includes use `../src/`; there is no dependency on the
private development lab. Firmware builds take their SeaBIOS patch explicitly
from the separate openstep-qemu repository.

Recorded export and validation receipts describe their original inputs and
retain historical paths. The [2026-10-10 rebuild](rebuild-20261010.json) records native builds and
packages from the flattened tree. Older receipts remain historical evidence.
