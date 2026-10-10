# VirtioRNG development driver

Experimental native OPENSTEP 4.2/i386 DriverKit driver for QEMU's transitional
PCI entropy device. One queue and one bounded direct-buffer request at a time.
Uses the shared split-queue, legacy I/O and checked DMA allocation helpers.
No PRNGD integration or kernel entropy accounting is provided.

Build on OPENSTEP from this directory with Developer Tools: `make`.
Outputs: `VirtioRNG.config` and `virtio-rng-read`.

The native client uses IODeviceMaster against VirtioRNG0:

```
virtio-rng-read --stats
virtio-rng-read 4096 > bytes.bin
virtio-rng-read --reset
```

Reads are limited to 256 bytes per driver call and 1 MiB per client invocation.
A stalled request stops the device and reports an error. Explicit reset is
required to resume; DMA memory is retained if device reset cannot be verified.
The device ISR is acknowledged in the minimal interrupt handler; queue
consumption runs in an owned I/O worker, stopped and joined before object release. Release logging is limited to
initialization and errors. Counters report requests, completions and interrupts.

Status and authoritative test evidence are in ../../ledger.md. This is not yet
an installable release; use the isolated project test guest. Do not unload an
active driver or add it to a production boot configuration during development.
