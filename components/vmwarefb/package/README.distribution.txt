VMWareFB 0.1 - experimental display driver for OPENSTEP 4.2 Intel

True-color QEMU VMware SVGA driver with CopyBack framebuffer caching,
hardware cursors and guarded 2D rectangle copy/fill acceleration. Other
operations use the software renderer. One display is supported; VMware and
VirtualBox are untested. Default mode: 1600x1200 true color.

QEMU requirements
Use -vga vmware. GTK OpenGL output (-display gtk,gl=on) is recommended.
4K requires a QEMU build supporting 3840x2160 VMware SVGA and:
    -global vmware-svga.vgamem_mb=32
Device dimensions and video memory determine the available modes.

Installation
1. Back up your VM disk while QEMU is stopped.
2. Extract: gnutar -xzf VMWareFB-0.1.pkg.I.tar.gz
3. Open VMWareFB.pkg in Installer as root; install at / (Intel, English).
   This installs the driver catalog bundle and WindowServer adapter.
4. In Configure.app as root, replace the current display with VMware Display
   Adapter (Show All Installed Drivers), choose a mode and Save.
5. Shut down cleanly and restart QEMU with -vga vmware.

Rollback
Select your previous display driver in Configure and Save. Shut down cleanly,
then restart with its QEMU graphics device (usually -vga std for VESA).
If the guest cannot boot, restore the stopped-disk backup.

Source and original license are included in VMWareFB-source; its README.md
covers building, settings and diagnostics. PAYLOAD-SHA256.json lists checksums
of installed files. With OPENSTEP Developer Tools installed:
    cd VMWareFB-source; make

Release builds log initialization and warnings/errors. Drawing diagnostics
and profiling are disabled; read-only diagnostic counters remain available.
