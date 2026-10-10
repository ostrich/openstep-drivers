# TCPBuffers

Improve TCP file-transfer throughput without changing every application.
OPENSTEP normally gives new TCP sockets only 4 KiB send and receive buffers,
which can limit bulk transfers. TCPBuffers raises both defaults to 32 KiB at
boot, allowing more data in flight. Testing showed substantial throughput
gains with these buffer sizes; results depend on the application and network.

It works independently of the network adapter, so both PCnet and VirtioNet can
benefit. Applications can still choose their own sizes. The module is optional
and does not modify the original kernel executable; larger buffers can use
more kernel memory.

See the [installation README](package/README.txt) and [build instructions](../docs/build.md).
