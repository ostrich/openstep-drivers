# VMTablet

VMTablet gives OPENSTEP seamless mouse integration, like a modern Windows or
Linux guest. With QEMU's GTK display, move the pointer into the VM to use
OPENSTEP, then move it back out to the host without clicking to capture it or
pressing a release shortcut. The guest pointer stays aligned with the host
pointer, avoiding the drift of a relative PS/2 mouse.

VMTablet works with both OPENSTEP's stock VGA/VESA display driver and the
VMWareFB display driver.

VMTablet uses QEMU's VMware mouse interface. It supports one display and
left/right buttons; wheel and middle-button input are not implemented.

See the [installation README](package/README.distribution.txt) and [build instructions](../docs/build.md).
