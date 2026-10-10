/* MIT license. Native nonblocking DriverKit transport for root services. */
#ifndef OS42_AGENT_TRANSPORT_H
#define OS42_AGENT_TRANSPORT_H
struct agent_transport {
    void *master;unsigned object,port,generation,connected;int lock_fd;
};
/* One advisory consumer lock per logical port, held for the daemon lifetime.
 * Caller supplies a zeroed structure. Open returns 0 or -1 (errno set). */
int agent_transport_open(struct agent_transport *t,unsigned port);
void agent_transport_close(struct agent_transport *t);
/* Refresh session state: 1 generation/connection change, 0 unchanged, -1 fault.
 * On change the service must discard old protocol/output state and resources.
 * stats optionally receives the driver's 12-value status array. */
int agent_transport_refresh(struct agent_transport *t,unsigned *stats);
/* Binary read/write up to 512 bytes. Return 0 success, 1 write backpressure,
 * 2 session unavailable, -1 transport error. Read success may have zero bytes.
 * Write success accepts the entire supplied chunk locally, not at the peer. */
int agent_transport_read(struct agent_transport *t,unsigned char *bytes,unsigned *count);
int agent_transport_write(struct agent_transport *t,unsigned char *bytes,unsigned count);
#endif
