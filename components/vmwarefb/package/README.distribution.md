# VMware SVGA display driver for OPENSTEP 4.2 Intel

Experimental QEMU driver with true-color modes, CopyBack framebuffer caching,
hardware cursors, and guarded 2D rectangle copy/fill acceleration. Other drawing
uses OPENSTEP's software renderer. VMware and VirtualBox are untested.

See [installation instructions](README.distribution.txt) for device options
and rollback.

## Build from source

With OPENSTEP 4.2 Developer Tools installed, run `make` in this directory.
Outputs are `VMWareFB.config` and `VMWareFB_psdrvr`. The Installer package
places the driver in the driver catalog and the adapter in the system display
module directory; Configure.app activates the selected driver. Cold boot after
replacing a driver. Back up the stopped VM disk before installation.

The default is 1600x1200 true color. 4K requires a QEMU build supporting
3840x2160 VMware SVGA and 32 MiB video memory. Modes are filtered by device
limits and framebuffer capacity. One display is supported.

`VMWare Acceleration` accepts `None`, `Cursor`, or `Default`. `Framebuffer
Cache` accepts `CopyBack`, `WriteThrough`, or `Off`; CopyBack is tested with
QEMU's coherent framebuffer RAM. Optional upload conversion, tracing and
profiling are disabled in the distributed binaries.

## Diagnostics

Build the included diagnostic client on OPENSTEP:

```
cc tests/probe.m -o probe -lDriver
./probe
```

The probe's fill/copy options change visible pixels; use a disposable VM.
Host bounds/FIFO checks can be built with a modern C compiler:

```
cc -std=gnu89 tests/policy-tests.c -o policy-tests
./policy-tests
```

Framebuffer bounds and stride are validated. Software fallback is permitted
only before FIFO publication. A published command that cannot complete within
one second triggers a guest panic, avoiding an unsafe duplicate overlapping
copy. QEMU normally completes SYNC synchronously.

## Origin and license

Based on Atomic Object's VMWareFB_OpenStep driver, revision
788d6dcb36223abf4118771c556077017b61c2b5. Original copyright and XFree86 license
notices are retained in the source and `LICENSE.html`. `README.vmware` is a
historical device-protocol reference, not installation guidance for this port.

Release builds log one initialization summary plus warnings/errors. Kernel
development logging requires VMWAREFB_DEBUG and is disabled by default.
