#include "split-queue.h"
/* Locked instruction is a full x86 barrier plus a compiler memory barrier.
 * Avoid newer compiler builtins: this must compile with native Developer Tools. */
static void fence(void)
{
    volatile unsigned word=0;
    __asm__ volatile("lock; addl $0,%0" : "=m"(word) : "m"(word) : "memory", "cc");
}
static unsigned used_offset(unsigned n) { return (16*n+4+2*n+2+4095)&~4095U; }
unsigned vq_bytes(unsigned n)
{
    if (!n || n>VQ_MAX || (n&(n-1))) return 0;
    return (used_offset(n)+4+8*n+2+4095)&~4095U;
}
int vq_init(struct vq *q, void *ring, unsigned bytes, unsigned n)
{
    unsigned i,required=vq_bytes(n);
    if (!q || !ring || !required || bytes<required || ((unsigned long)ring&15)) return -1;
    q->ring=ring;q->n=n;q->bytes=required;q->used_offset=used_offset(n);
    q->available=q->consumed=0;q->outstanding=q->broken=0;
    for(i=0;i<required;i++) q->ring[i]=0;
    for(i=0;i<VQ_MAX;i++) {
        q->busy[i]=0;q->capacity[i]=0;q->chain_count[i]=0;
        q->chain_next[i]=VQ_MAX;
    }
    return 0;
}
int vq_submit(struct vq *q,unsigned lo,unsigned hi,unsigned length,int writes)
{
    struct vq_buffer buffer;
    buffer.lo=lo;buffer.hi=hi;buffer.length=length;buffer.device_writes=writes;
    return vq_submit_chain(q,&buffer,1);
}
int vq_submit_chain(struct vq *q,const struct vq_buffer *buffers,unsigned count)
{
    unsigned ids[VQ_MAX],i,j,total=0;
    volatile struct vq_desc *desc;
    volatile unsigned short *avail;
    if(!q || q->broken || !buffers || !count || count>q->n)return -1;
    for(i=0;i<count;i++) {
        if(!buffers[i].length || buffers[i].length>~0U-total)return -1;
        /* Device-readable descriptors cannot follow writable descriptors. */
        if(i && buffers[i-1].device_writes && !buffers[i].device_writes)return -1;
        total+=buffers[i].length;
    }
    for(i=0,j=0;i<q->n && j<count;i++)if(!q->busy[i])ids[j++]=i;
    if(j!=count)return -1;
    desc=(volatile struct vq_desc *)q->ring;
    avail=(volatile unsigned short *)(q->ring+16*q->n);
    for(i=0;i<count;i++) {
        unsigned id=ids[i],next=i+1<count?ids[i+1]:VQ_MAX;
        q->busy[id]=1;q->chain_count[id]=0;q->chain_next[id]=next;
        desc[id].addr_lo=buffers[i].lo;desc[id].addr_hi=buffers[i].hi;
        desc[id].length=buffers[i].length;
        desc[id].flags=(buffers[i].device_writes?2:0)|(i+1<count?1:0);
        desc[id].next=i+1<count?next:0;
    }
    q->capacity[ids[0]]=total;q->chain_count[ids[0]]=count;q->outstanding++;
    avail[2+(q->available&(q->n-1))]=(unsigned short)ids[0];
    fence();q->available++;avail[1]=q->available;fence();
    return (int)ids[0];
}
int vq_complete(struct vq *q,unsigned *id,unsigned *length)
{
    volatile unsigned short *used;
    volatile struct vq_used *entry;
    unsigned pending,index,count,i,current;
    if(!q || q->broken || !id || !length) return -1;
    used=(volatile unsigned short *)(q->ring+q->used_offset);
    pending=(unsigned short)(used[1]-q->consumed);
    if(!pending) return 0;
    fence();
    if(pending>q->outstanding) { q->broken=1;return -1; }
    entry=(volatile struct vq_used *)(q->ring+q->used_offset+4);
    index=entry[q->consumed&(q->n-1)].id;
    count=entry[q->consumed&(q->n-1)].length;
    if(index>=q->n || !q->busy[index] || !q->chain_count[index] || count>q->capacity[index]) {
        q->broken=1;return -1;
    }
    current=index;
    for(i=0;i<q->chain_count[index];i++) {
        unsigned next=q->chain_next[current];
        q->busy[current]=0;current=next;
    }
    q->chain_count[index]=0;
    *id=index;*length=count;q->outstanding--;q->consumed++;
    return 1;
}
