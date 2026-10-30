Kernel Mapping Fix 0.1-1

Especially important with QEMU/KVM: installing this fix is strongly
recommended. On affected hosts, KVM exposes an OPENSTEP mapping bug that can
cause intermittent checksum and process-start failures. Equivalent TCG control
tests did not reproduce them. The module works with both KVM and TCG.

Prevents stale memory translations when OPENSTEP 4.2 removes mappings on
modern Intel-compatible processors. The fix is applied to memory by a
loadable driver. It never changes /mach_kernel or another kernel file.

Requires Intel OPENSTEP 4.2, a single-CPU kernel and guest, and the supported
kernel image. The driver verifies kernel code before writing and refuses
unknown or conflicting code. It also recognizes the same fix already applied.

Install KernelMappingFix.pkg as root, then run:

  /usr/local/sbin/kernel-mapping-fix-configure enable

Shut down cleanly and boot again. To check the loaded driver:

  /usr/local/sbin/kernel-mapping-fixctl --status

Normal status is result=1 image=2. Result 2 means the fix was already present;
result 3 means read-only mode. Image 1 is the original kernel code, and image
2 is the fixed code. The two CR0 values should match after application.

The configure helper registers the driver first in Boot Drivers and preserves
the other entries. A one-time backup is kept at:

  /usr/Devices/System.config/Instance0.table.before-kernel-mapping-fix

To disable next-boot loading:

  /usr/local/sbin/kernel-mapping-fix-configure disable

Reboot afterward. Disabling or removing the package does not undo a live fix.
The package removal hook disables next-boot loading. No live undo is provided;
keep the driver loaded until shutdown rather than forcibly unloading it.

The fix starts when the module loads. It does not cover earlier boot activity
or repair corruption that has already occurred. Other kernel mapping and
permission-change paths are outside its scope.

The original supported kernel SHA-256 is:
33469393c0843fc741942c3ae9d91d838467d72abd647dcf2e5bf499a3f14890
