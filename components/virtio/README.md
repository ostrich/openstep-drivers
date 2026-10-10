# Virtio drivers and services

Legacy PCI transport and split queues shared by VirtioRNG, VirtioNet, VirtioBlk
and VirtioConsole. Guest services provide a QEMU guest agent and a separate
interactive PTY port. Keep `src/`, `drivers/` and `services/` together when
building. See [build instructions](../../docs/build.md).
