VMTablet 0.2 - absolute pointer for OPENSTEP 4.2 Intel

Guest coordinates follow the host pointer, and GTK permits pointer exit and
re-entry without manual release. Requires QEMU's VMware mouse interface:
    -machine pc,vmport=on -display gtk

One display and left/right buttons are supported; wheel and middle button
are not implemented. Tested at 1600x1200x32. Other hypervisors are untested.
Version 0.2 adds event-owner recovery following WindowServer restart.

Installation
1. Back up your VM disk while QEMU is stopped.
2. Extract: gnutar -xzf VMTablet-0.2.pkg.I.tar.gz
3. Open VMTablet.pkg in Installer as root; install at / (Intel, English).
4. Back up /usr/Devices/System.config/Instance0.table before changing devices.
5. In Configure.app as root, select the mouse icon. Remove the old mouse
   (or existing VMTablet entry when updating). Choose Add -> Show All Installed
   Drivers -> VMware Absolute Pointer (v0.2) -> Add -> Done -> Save.
   Keep one VMTablet and no PS2Mouse; leave other devices unchanged.
6. Shut down cleanly, quit QEMU and restart. Check movement, clicks and drag.

Rollback
In Configure, remove VMTablet, re-add your previous mouse and Save. Shut down
cleanly and restart QEMU. Restore the stopped-disk backup if needed.

Avoid live driver unloading. Diagnostics are in /usr/adm/messages. GTK
supports natural pointer exit/re-entry; SDL may require Ctrl-Alt-G.

Source is included in VMTablet-source. With Developer Tools installed:
    cd VMTablet-source; make

Release builds log initialization and errors. Packet and owner-lifecycle
diagnostics require VMTABLET_DEBUG and are disabled by default.
