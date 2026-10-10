#ifndef OS42_VIRTIO_NATIVE_DMA_H
#define OS42_VIRTIO_NATIVE_DMA_H
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/kernelDriver.h>
#include <string.h>
/* Low memory allocation is not assumed contiguous: verify every page boundary.
 * Preserve original allocation for the matching IOFreeLow call. */
struct DMARegion { void *allocation;unsigned allocated;void *address;unsigned physical,size; };
static int dma_alloc(struct DMARegion *r,unsigned size)
{
    unsigned off,phys,first;
    if(!r || r->allocation || !size || size>65536-4095)return 0;
    r->allocated=size+4095;r->allocation=IOMallocLow(r->allocated);
    if(!r->allocation)return 0;
    r->address=(void *)(((unsigned)r->allocation+4095)&~4095U);
    if(IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)r->address,&first)!=IO_R_SUCCESS || (first&4095))goto fail;
    for(off=0;off<size;off+=4096) {
        if(IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)r->address+off,&phys)!=IO_R_SUCCESS || phys!=first+off)goto fail;
    }
    if(IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)r->address+size-1,&phys)!=IO_R_SUCCESS || phys!=first+size-1)goto fail;
    r->physical=first;r->size=size;memset(r->address,0,size);return 1;
fail:
    IOFreeLow(r->allocation,r->allocated);memset(r,0,sizeof(*r));return 0;
}
#endif
