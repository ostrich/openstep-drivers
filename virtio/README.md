# Virtio drivers and services

Use VM-oriented devices for disks, networking and host communication. VirtioBlk
can boot the system directly and improves read throughput in matched tests;
VirtioNet replaces PCnet while preserving the usual network configuration.
The console services let you transfer files and use a shell without guest
networking. VirtioRNG supplies host entropy to an explicit command-line reader.

The drivers share legacy PCI transport and split queues. Performance depends
on the workload and host; installation READMEs describe each device's limits. Keep the driver directories, `src/` and `services/` together when
building. See [build instructions](../docs/build.md).
