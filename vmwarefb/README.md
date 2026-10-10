# VMWareFB

Give OPENSTEP a larger, smoother desktop than the basic VESA setup. VMWareFB
provides true-color modes, hardware cursors, framebuffer caching and 2D
rectangle copy/fill acceleration on QEMU's VMware SVGA adapter. Supported
widescreen modes give applications more room on modern displays; the default
is 1600x1200, with 4K available when QEMU and video memory permit it.

These improvements target desktop drawing and pointer responsiveness. Other
drawing remains software-rendered, so gains vary by operation. One display is
supported; VMware and VirtualBox have not been tested.

See the [installation README](package/README.distribution.txt) and [build instructions](../docs/build.md).
