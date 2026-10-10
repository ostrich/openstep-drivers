#ifndef OS42_VIRTIO_NATIVE_DMA_H
#define OS42_VIRTIO_NATIVE_DMA_H
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/kernelDriver.h>
#import <driverkit/generalFuncs.h>
#import <mach/vm_param.h>
#include <string.h>
/* PCI DMA is not restricted to ISA/conventional memory. A page-sized wired
 * allocation can be aligned within its owner without requiring contiguous
 * physical pages beyond that native page. Verify physical layout in all cases.
 * Larger arenas retain the conventional-memory allocator and its 64-KiB cap.
 * Its results are already page/64-KiB aligned; padding would waste pool blocks. */
struct DMARegion { void *allocation;unsigned allocated;void *address;unsigned physical,size;int low; };
static void dma_free(struct DMARegion *r)
{
    if(!r || !r->allocation)return;
    if(r->low)IOFreeLow(r->allocation,r->allocated);
    else IOFree(r->allocation,r->allocated);
    memset(r,0,sizeof(*r));
}
static int dma_alloc(struct DMARegion *r,unsigned size)
{
    unsigned off,phys,first,page=PAGE_SIZE;
    if(!r || r->allocation || !size || size>65536 || !page || (page&(page-1)))return 0;
    r->low=size>page;
    r->allocated=r->low?size:size+page-1;
    r->allocation=r->low?IOMallocLow(r->allocated):IOMalloc(r->allocated);
    if(!r->allocation) { memset(r,0,sizeof(*r));return 0; }
    r->address=r->low?r->allocation:(void *)(((unsigned)r->allocation+page-1)&~(page-1));
    if((unsigned)r->address&4095)goto fail;
    if(IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)r->address,&first)!=IO_R_SUCCESS || (first&4095))goto fail;
    for(off=0;off<size;off+=4096) {
        if(IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)r->address+off,&phys)!=IO_R_SUCCESS || phys!=first+off)goto fail;
    }
    if(IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)r->address+size-1,&phys)!=IO_R_SUCCESS || phys!=first+size-1)goto fail;
    r->physical=first;r->size=size;memset(r->address,0,size);return 1;
fail:
    dma_free(r);return 0;
}
#endif
