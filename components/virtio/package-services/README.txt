OPENSTEP 4.2 Virtio Services 0.1

This archive provides VirtioConsole.pkg (driver 0.2),
OpenStepVirtioServices.pkg, host clients, matching source and licenses.
The guest agent implements standard QEMU commands; the terminal uses its own
port and protocol. Both services run as root and can be enabled independently.

Host setup
Use a compatible QEMU build. Testing used QEMU 11.1.1 with the two fixes in
https://github.com/ostrich/openstep-qemu. Use its patched host build;
the unpatched close behavior is not supported for continued use.

Set AGENT_SOCKET and PTY_SOCKET to two unused local Unix-socket paths. Add
these options to your existing OPENSTEP VM command:

  -device virtio-serial-pci-transitional,id=vserial,addr=9,max_ports=3,vectors=0
  -chardev socket,id=qga,path="$AGENT_SOCKET",server=on,wait=off
  -device virtserialport,bus=vserial.0,nr=1,chardev=qga,name=org.qemu.guest_agent.0
  -chardev socket,id=pty,path="$PTY_SOCKET",server=on,wait=off
  -device virtserialport,bus=vserial.0,nr=2,chardev=pty,name=org.openstep.pty

Guest installation
Install both included .pkg bundles at / using Installer as root. For an
upgrade, stop existing services first with openstep-services stop. Installation
updates programs and the example configuration, preserving active settings.

From a root Terminal, run:

  sh scripts/configure-guest.sh enable 2
  cp /usr/local/etc/openstep-services.conf.example /usr/local/etc/openstep-services.conf
  chmod 600 /usr/local/etc/openstep-services.conf

Run enable 2 after every driver reinstall, including upgrades.
Skip the cp command when retaining an existing configuration. Edit that file:
OPENSTEP_GUEST_AGENT=YES/NO, OPENSTEP_PTY=YES/NO and
OPENSTEP_PTY_SHELL=/bin/csh. Then register startup:

  /usr/local/libexec/configure-service-boot.sh enable

Shut down cleanly and restart with the host options above. Never replace or
reload the live kernel driver. Check services with:

  /usr/local/sbin/openstep-services status

Host use (Python 3)
  python3 host/agent-client.py --socket "$AGENT_SOCKET" guest-info
  python3 host/agent-client.py --socket "$AGENT_SOCKET" upload LOCAL_FILE /GUEST_FILE
  python3 host/agent-client.py --socket "$AGENT_SOCKET" download /GUEST_FILE LOCAL_FILE
  python3 host/agent-client.py --socket "$AGENT_SOCKET" exec /bin/echo hello
  python3 host/pty-client.py --socket "$PTY_SOCKET"

Ctrl-] disconnects the terminal; Ctrl-C and Ctrl-Z reach the guest. Resizing
updates its terminal size. Disconnect terminates terminal-attached jobs. Deliberately detached jobs are
not guaranteed to be terminated; stop those separately.
Keepalives detect a silent daemon; the host restores terminal settings on exit.
Transfers verify contents before replacing the destination. Interrupted
uploads leave the prior destination intact; failed cleanup may leave a private
.qga-upload-* temporary file. No mutating request is automatically replayed.

Limits
Use guest-info for supported commands. Files must be regular files; transfers
and seeks use native 32-bit limits. Exec captures up to 16 KiB per output stream
and marks truncation. Freeze/thaw, suspend and powerdown are unsupported;
shutdown supports halt and reboot. Halt reaches OPENSTEP's safe-to-power-off
state; it does not promise automatic QEMU exit. A hardware controller reset
invalidates both ports and their active sessions; both services recover for
fresh connections. Private PTY input/framing and stalled-output waits are
bounded; quiet idle sessions remain supported.

After a driver transport fault, stop both services, then run as root:
  /usr/local/bin/virtio-console --reset
  /usr/local/sbin/openstep-services start
If reset fails, shut down cleanly and reboot. Do not retry an uncertain file
mutation automatically; reconnect and check its result first.

Rollback
Stop services, run configure-service-boot.sh disable, and set both service
settings to NO. To remove the driver from startup, run
sh scripts/configure-guest.sh disable. Shut down cleanly before changing the
host devices or reinstalling a previous driver. Activation keeps the first
System.config backup and the boot helper keeps the first rc.local backup;
avoid restoring those wholesale over unrelated later edits.

Source
source/ contains the native code and package build scripts. Build on OPENSTEP
with its Developer Tools. From the extracted archive, provide absolute paths
for ARCHIVE_DIR and two new, unused build directories, then run as root:

  sh source/package-console/build-on-openstep.sh "$ARCHIVE_DIR/source" "$ARCHIVE_DIR/source/package-console/VirtioConsole.info" "$DRIVER_BUILD"
  sh source/package-services/build-on-openstep.sh "$ARCHIVE_DIR/source" "$ARCHIVE_DIR/source/package-services/OpenStepVirtioServices.info" "$SERVICE_BUILD"

Native code and clients use LICENSE-MIT.txt; the
QEMU patches use the included GPL license. No operating-system media is included.
