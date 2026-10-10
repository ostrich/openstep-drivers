# Building drivers and packages

Use OPENSTEP 4.2 Intel with Developer Tools installed. Build in a copy of the
source tree, keeping generated files out of the checkout.

| Component | Run `make` in | Native package recipe |
| --- | --- | --- |
| VMTablet | `vmtablet` | `vmtablet/package/build-on-openstep.sh` |
| VMWareFB | `vmwarefb` | `vmwarefb/package/build-on-openstep.sh` |
| TCPBuffers | `tcp-buffers/TCPBuffers` | `tcp-buffers/package/build-on-openstep.sh` |
| VirtioRNG | `virtio/VirtioRNG` | `virtio/package/build-on-openstep.sh` |
| VirtioNet | `virtio/VirtioNet` | `virtio/package-net/build-on-openstep.sh` |
| VirtioBlk | `virtio/VirtioBlk` | `virtio/package-blk/build-on-openstep.sh` |
| VirtioConsole | `virtio/VirtioConsole` | `virtio/package-console/build-on-openstep.sh` |
| Guest services | `virtio/services` | `virtio/package-services/build-on-openstep.sh` |

Keep `virtio` together: its drivers include the shared `src/` files
by relative paths. Pass that entire directory as SOURCE_ROOT to its native
package recipes. VMTablet and VMWareFB recipes take their individual component
directories. Each recipe prints its usage; arguments are absolute guest paths,
and its work directory must not already exist. Run package creation as root.
Use the matching `.info` file beside the recipe.

Host-side `distribute.py` scripts validate the native package before wrapping it
in an OPENSTEP-readable USTAR `.tar.gz`. Run without Python's `-O` option,
which disables assertions. Some require tested binaries, source snapshots or
firmware as explicit inputs; inspect `--help` before assembly. The combined
services distribution contains both VirtioConsole.pkg and
OpenStepVirtioServices.pkg. The console's standalone package is a build input.

EIDE is a binary patch, not a source driver. Its patcher requires the exact
original EIDE 4.03 executable, Python 3 and GNU `as`. See its component README
for input and output hashes. The original executable is not in this repository.

Run portable checks on a Linux or macOS host:

```sh
python3 scripts/check.py
```

These checks cover shared queue behavior, framebuffer policy and host client
protocols. Native compilation, installation, reboot, recovery and sustained I/O
validation still require an OPENSTEP guest.

CI runs the full portable suite on Linux and host-client protocol/terminal tests
on macOS. To run only the host-client checks locally:

```sh
python3 scripts/check-host-clients.py
```

The macOS terminal test allows XNU's transient PENDIN state after restoring
canonical input; it still compares all other terminal settings, descriptor
flags and successful line input. CI does not compile or boot native drivers.
