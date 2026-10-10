# Combined virtio device DMA allocation

Verified 2026-10-10 in OPENSTEP 4.2 guests with the combined virtio device configuration.

Loading VirtioBlk, VirtioRNG, VirtioConsole and VirtioNet together exhausted
OPENSTEP's conventional-memory DMA allocator. VirtioNet could not allocate its
12 KiB ring. After reducing allocations enough to initialize networking, SB16
still could not allocate its audio buffers. Increasing guest RAM did not help.

The original kernel's `IOMallocLow` routes through `dma_buf_alloc`. Requests
larger than its 8192-byte native page consume a 64 KiB conventional-memory block.
The conventional-memory allocator advances a cursor without reclaiming that
address space. A captured cursor of 0x90000 with an end of 0x9e000 explains why
another 64 KiB allocation failed, despite apparently available guest RAM.

The driver changes keep the original kernel unchanged:

- Allocate page-sized PCI DMA regions from wired `IOMalloc`, align within the
  owned allocation, and verify physical continuity. Larger contiguous regions
  retain `IOMallocLow`, without redundant alignment padding. Free with the
  matching allocator and original owner pointer/size.
- Configure VirtioBlk with a 128-entry queue, making its ring one native page.
  The existing 64 KiB data optimization remains enabled.
- Pack each VirtioNet ring and its packet arena into one 63,488-byte allocation.
  Both queues retain 256 entries, the QEMU RX minimum. Two large owners replace
  four. Reset acknowledgement and worker teardown still precede freeing.
- Allocate VirtioConsole pools from wired general memory. Its existing physical
  validation of each ring and packet slot handles noncontiguous pool pages.

Production native builds were installed and cold booted. KVM and TCG tests
covered Workspace at 1600x1200, simultaneous block/network/file transfers with
SHA256 verification, 1 MiB of entropy, interactive PTY commands, SSH/SFTP and
three captured SB16 tones. Driver error counters stayed zero. Three absolute
pointer coordinates matched exactly on KVM. A host allocator test covers
allocation failures, discontinuity, alignment, bounds and paired frees.

The native package binaries in this release are the binaries installed for
these tests. Package payload hashes and allocator test coverage are recorded
in the build records. Package versions remain unchanged for this replacement
of the 2026.10.10 release assets.
