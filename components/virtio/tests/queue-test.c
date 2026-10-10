#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <stddef.h>
#include "../src/split-queue.h"
static unsigned char ring[8192] __attribute__((aligned(4096)));
static struct vq q;
static void complete(unsigned short sequence,unsigned id,unsigned length)
{
    struct vq_used *u=(struct vq_used *)(ring+q.used_offset+4);
    u[(unsigned short)(sequence-1)&(q.n-1)].id=id;
    u[(unsigned short)(sequence-1)&(q.n-1)].length=length;
    ((unsigned short *)(ring+q.used_offset))[1]=sequence;
}
int main(void)
{
    unsigned i,id,length;
    struct vq_buffer chain[2]={{0x30000,0,10,0},{0x30010,0,1514,0}};
    struct vq_desc *descriptors=(struct vq_desc *)ring;
    assert(sizeof(unsigned)==4 && sizeof(unsigned short)==2);
    assert(sizeof(struct vq_desc)==16 && offsetof(struct vq_desc,length)==8);
    assert(sizeof(struct vq_used)==8);
    assert(vq_bytes(0)==0 && vq_bytes(3)==0 && vq_bytes(512)==0);
    assert(vq_init(&q,ring,4096,8)==-1);
    assert(vq_init(&q,ring+1,8191,8)==-1);
    assert(vq_init(&q,ring,sizeof(ring),8)==0);
    for(i=0;i<8;i++) assert(vq_submit(&q,0x10000+i*64,0,64,1)==(int)i);
    assert(vq_submit(&q,0x10000,0,64,1)==-1);
    for(i=0;i<8;i++) {
        complete(i+1,7-i,64);assert(vq_complete(&q,&id,&length)==1);
        assert(id==7-i && length==64);
    }
    assert(vq_complete(&q,&id,&length)==0);
    /* More than one full 16-bit index cycle, with recycling. */
    for(i=0;i<70000;i++) {
        int d=vq_submit(&q,0x20000,0,64,1);assert(d>=0);
        complete(q.available,(unsigned)d,32);
        assert(vq_complete(&q,&id,&length)==1 && length==32);
    }
    assert(vq_submit(&q,0,0,0,1)==-1);
    assert(vq_submit(&q,0x20000,0,64,1)==0);
    complete(q.available,0,65);assert(vq_complete(&q,&id,&length)==-1);
    assert(q.broken && q.outstanding==1);
    assert(vq_submit(&q,0x20000,0,64,1)==-1);
    assert(vq_init(&q,ring,sizeof(ring),8)==0);
    assert(vq_submit(&q,0x20000,0,64,1)==0);
    complete(1,255,1);assert(vq_complete(&q,&id,&length)==-1);
    assert(vq_init(&q,ring,sizeof(ring),8)==0);
    complete(1,0,1);assert(vq_complete(&q,&id,&length)==-1);
    assert(vq_init(&q,ring,sizeof(ring),8)==0);
    for(i=0;i<4;i++)assert(vq_submit_chain(&q,chain,2)==(int)(2*i));
    assert(q.outstanding==4 && q.available==4);
    assert(descriptors[0].flags==1 && descriptors[0].next==1);
    assert(descriptors[1].flags==0 && descriptors[1].length==1514);
    assert(vq_submit_chain(&q,chain,2)==-1 && q.outstanding==4);
    for(i=0;i<4;i++) {
        complete(i+1,6-2*i,1524);assert(vq_complete(&q,&id,&length)==1);
        assert(id==6-2*i && !q.busy[id] && !q.busy[id+1]);
    }
    for(i=0;i<70000;i++) {
        assert(vq_submit_chain(&q,chain,2)==0);
        complete(q.available,0,0);
        assert(vq_complete(&q,&id,&length)==1 && length==0);
    }
    /* Reservation failure must not consume the one remaining descriptor. */
    for(i=0;i<7;i++)assert(vq_submit(&q,0x40000,0,64,1)==(int)i);
    assert(vq_submit_chain(&q,chain,2)==-1 && !q.busy[7]);
    assert(vq_submit(&q,0x40000,0,64,1)==7);
    assert(vq_init(&q,ring,sizeof(ring),8)==0);
    chain[0].device_writes=1;
    assert(vq_submit_chain(&q,chain,2)==-1 && q.available==0);
    chain[0].device_writes=0;chain[1].length=~0U;
    assert(vq_submit_chain(&q,chain,2)==-1 && q.available==0);
    chain[1].length=1514;
    assert(vq_submit_chain(&q,chain,2)==0);
    /* A used ID identifying a chain tail is invalid, even though busy. */
    complete(1,1,0);assert(vq_complete(&q,&id,&length)==-1);
    assert(q.broken && q.busy[0] && q.busy[1] && q.outstanding==1);
    puts("PASS layouts, exhaustion, out-of-order completion, 16-bit wrap, malformed completion quarantine");
    return 0;
}
