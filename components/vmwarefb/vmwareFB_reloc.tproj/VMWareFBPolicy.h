/* Shared, host-testable safety rules; compatible with OPENSTEP's C compiler. */
#ifndef VMWAREFB_POLICY_H
#define VMWAREFB_POLICY_H

#define VM_FIFO_REJECTED 0
#define VM_FIFO_COMPLETE 1
#define VM_FIFO_UNCERTAIN 2

static __inline__ int vmwareFramebufferFits(unsigned size,unsigned offset,unsigned stride,
                                unsigned width,unsigned height,unsigned bpp)
{
    unsigned bytes;
    if(!width || !height || (bpp!=8 && bpp!=16 && bpp!=32) || offset>size) return 0;
    bytes=bpp/8;
    if(width>~0U/bytes || stride<width*bytes || !stride) return 0;
    return height<=(size-offset)/stride;
}

/* Caller holds the device lock. REJECTED guarantees nothing was published.
 * UNCERTAIN must fail closed: the caller may not retry or touch framebuffer
 * memory while completion is unknown. */
static __inline__ int vmwareFifoSubmit(volatile unsigned *fifo,unsigned length,
                           const unsigned *words,unsigned count,
                           void *device,void (*sync)(void *),
                           unsigned (*busy)(void *),void (*delay)(void *))
{
    unsigned min,max,next,stop,room,i,spins;
    if(!fifo || !words || !count || count>1024 || length<16) return VM_FIFO_REJECTED;
    min=fifo[0];max=fifo[1];next=fifo[2];stop=fifo[3];
    if(min<16 || max>length || min>=max || next<min || next>=max ||
       stop<min || stop>=max || ((min|max|next|stop)&3)) return VM_FIFO_REJECTED;
    room=stop>next ? stop-next-4 : max-next+stop-min-4;
    if(room<count*4) return VM_FIFO_REJECTED;
    for(i=0;i<count;i++) {
        fifo[next/4]=words[i];next+=4;if(next==max) next=min;
    }
    __asm__ volatile("" : : : "memory");
    fifo[2]=next;
    sync(device);
    /* One second maximum. The supported QEMU SYNC processes the ring
     * synchronously; tolerate delayed completion without replaying a copy. */
    for(spins=0;spins<10000;spins++) {
        if(!busy(device)) return VM_FIFO_COMPLETE;
        delay(device);
    }
    return VM_FIFO_UNCERTAIN;
}
#endif
