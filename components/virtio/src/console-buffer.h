/* MIT license. Bounded byte FIFO; caller supplies storage and serialization.
 * Writes are all-or-nothing. No allocation, DMA, blocking or packet semantics. */
#ifndef OS42_CONSOLE_BUFFER_H
#define OS42_CONSOLE_BUFFER_H
#include <string.h>
struct vc_fifo { unsigned char *data;unsigned capacity,head,count; };
static int vc_fifo_init(struct vc_fifo *q,void *data,unsigned capacity)
{
    if(!q || !data || !capacity)return 0;
    q->data=data;q->capacity=capacity;q->head=0;q->count=0;return 1;
}
static void vc_fifo_clear(struct vc_fifo *q) { q->head=0;q->count=0; }
static unsigned vc_fifo_space(const struct vc_fifo *q) { return q->capacity-q->count; }
/* Reserve capacity for posted RX descriptors before accepting additional data.
 * These reservations are owned by the driver until completion/reset. */
static int vc_fifo_can_reserve(const struct vc_fifo *q,unsigned reserved,unsigned bytes)
{
    unsigned available=vc_fifo_space(q);
    return reserved<=available && bytes<=available-reserved;
}
/* 1 accepted (including zero bytes), 0 full, -1 invalid input. */
static int vc_fifo_put(struct vc_fifo *q,const void *data,unsigned bytes)
{
    unsigned tail,n;
    if(!q || !q->data || !q->capacity || q->count>q->capacity || (bytes && !data))return -1;
    if(bytes>vc_fifo_space(q))return 0;
    if(!bytes)return 1;
    /* Avoid head+count overflowing unsigned arithmetic for large buffers. */
    tail=q->count>=q->capacity-q->head?q->count-(q->capacity-q->head):q->head+q->count;
    n=q->capacity-tail;if(n>bytes)n=bytes;
    memcpy(q->data+tail,data,n);
    if(bytes>n)memcpy(q->data,(const unsigned char *)data+n,bytes-n);
    q->count+=bytes;return 1;
}
/* Returns bytes removed. Zero means empty or a zero-size request. */
static unsigned vc_fifo_get(struct vc_fifo *q,void *data,unsigned bytes)
{
    unsigned n;
    if(!q || !q->data || !data || !q->capacity || q->count>q->capacity)return 0;
    if(bytes>q->count)bytes=q->count;
    if(!bytes)return 0;
    n=q->capacity-q->head;if(n>bytes)n=bytes;
    memcpy(data,q->data+q->head,n);
    if(bytes>n)memcpy((unsigned char *)data+n,q->data,bytes-n);
    q->head=bytes>=q->capacity-q->head?bytes-(q->capacity-q->head):q->head+bytes;
    q->count-=bytes;return bytes;
}
#endif
