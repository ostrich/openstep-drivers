/* Exercise production safety rules with delayed device completion. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../vmwareFB_reloc.tproj/VMWareFBPolicy.h"
struct Device { unsigned fifo[16], pixels[8], polls, delay, publish, executed, never; };
static void syncDevice(void *p)
{
    struct Device *d=p;
    unsigned expected[7]={3,0,0,1,0,5,1};
    unsigned i,index=56;
    /* Publication must expose the whole wrapped command, not its prefix. */
    assert(d->fifo[2]==36);
    for(i=0;i<7;i++) {assert(d->fifo[index/4]==expected[i]);index+=4;if(index==64)index=16;}
    d->publish++;
}
static unsigned busyDevice(void *p)
{
    struct Device *d=p;
    if(d->never || d->polls++<d->delay) return 1;
    if(!d->executed) {
        memmove(d->pixels+1,d->pixels,5*sizeof(unsigned));
        d->executed++;
        d->fifo[3]=d->fifo[2];
    }
    return 0;
}
static void delayDevice(void *p) { (void)p; }
static void setup(struct Device *d)
{
    unsigned i;
    memset(d,0,sizeof(*d));d->fifo[0]=16;d->fifo[1]=64;d->fifo[2]=56;d->fifo[3]=52;
    for(i=0;i<8;i++) d->pixels[i]=i;
}
int main(void)
{
    struct Device d;
    unsigned copy[7]={3,0,0,1,0,5,1};
    unsigned expected[8]={0,0,1,2,3,4,6,7};
    assert(vmwareFramebufferFits(16*1024*1024,0,6400,1600,1200,32));
    assert(!vmwareFramebufferFits(8*1024*1024,0,7680,1920,1200,32));
    assert(vmwareFramebufferFits(9216000,0,7680,1920,1200,32));
    assert(!vmwareFramebufferFits(9216000,1,7680,1920,1200,32));
    assert(!vmwareFramebufferFits(~0U,0,~0U,~0U,1,32));
    assert(!vmwareFramebufferFits(~0U,0,0,1,1,32));
    assert(!vmwareFramebufferFits(~0U,~0U,4,1,1,32));
    assert(!vmwareFramebufferFits(~0U,0,4,1,1,24));
    setup(&d);d.delay=1200;
    assert(vmwareFifoSubmit(d.fifo,sizeof(d.fifo),copy,7,&d,syncDevice,busyDevice,delayDevice)==VM_FIFO_COMPLETE);
    assert(d.publish==1 && d.executed==1 && !memcmp(expected,d.pixels,sizeof(expected)));
    setup(&d);d.never=1;
    assert(vmwareFifoSubmit(d.fifo,sizeof(d.fifo),copy,7,&d,syncDevice,busyDevice,delayDevice)==VM_FIFO_UNCERTAIN);
    assert(d.publish==1 && !d.executed);
    setup(&d);d.fifo[3]=60; /* No room: must not publish. */
    assert(vmwareFifoSubmit(d.fifo,sizeof(d.fifo),copy,7,&d,syncDevice,busyDevice,delayDevice)==VM_FIFO_REJECTED);
    assert(!d.publish && d.fifo[2]==56);
    setup(&d);d.fifo[1]=65;
    assert(vmwareFifoSubmit(d.fifo,sizeof(d.fifo),copy,7,&d,syncDevice,busyDevice,delayDevice)==VM_FIFO_REJECTED);
    assert(!d.publish);
    puts("PASS: framebuffer bounds, atomic wrapped FIFO, delayed overlapping copy, uncertain completion, rejection without publication");
    return 0;
}
