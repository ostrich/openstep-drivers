/* Experimental legacy split queue, x86 little-endian only. No allocation or I/O.
 * Caller serializes access and stops device DMA before freeing/reinitializing.
 * Direct descriptor chains; no indirect/event-index negotiation. */
#ifndef OS42_SPLIT_QUEUE_H
#define OS42_SPLIT_QUEUE_H
#define VQ_MAX 256
struct vq_desc { unsigned addr_lo, addr_hi, length; unsigned short flags, next; };
struct vq_used { unsigned id, length; };
struct vq_buffer { unsigned lo, hi, length; int device_writes; };
struct vq {
    unsigned char *ring;
    unsigned n, used_offset, bytes;
    unsigned short available, consumed;
    unsigned char busy[VQ_MAX];
    unsigned capacity[VQ_MAX];
    unsigned short chain_next[VQ_MAX], chain_count[VQ_MAX];
    unsigned outstanding, broken;
};
unsigned vq_bytes(unsigned n);
int vq_init(struct vq *q, void *ring, unsigned bytes, unsigned n);
int vq_submit(struct vq *q, unsigned lo, unsigned hi, unsigned length,
              int device_writes);
/* Atomically reserve/publish a whole chain. Failure leaves queue unchanged.
 * Capacity includes all segments to accommodate legacy TX used lengths.
 * Consumers must validate device-specific writable lengths separately. */
int vq_submit_chain(struct vq *q,const struct vq_buffer *buffers,unsigned count);
/* 1 completed, 0 no completion, -1 corrupt device ring (queue quarantined). */
int vq_complete(struct vq *q, unsigned *id, unsigned *length);
#endif
