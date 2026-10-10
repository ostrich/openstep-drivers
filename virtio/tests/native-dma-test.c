#define _GNU_SOURCE
#include <assert.h>
#include <stdio.h>
#include <stdint.h>
#include <sys/mman.h>
#include "../src/native-dma.h"
unsigned mock_page_size=8192;
static void *mapping,*owner;
static unsigned mapped,requested,wired_calls,low_calls,wired_frees,low_frees;
static int fail_allocation,broken_mapping,unaligned_low;
static void *allocate(int size,int low)
{
    uintptr_t address;
    requested=size;
    if(low)low_calls++;else wired_calls++;
    if(fail_allocation)return 0;
    mapped=size+131072;
    mapping=mmap(0,mapped,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT,-1,0);
    assert(mapping!=MAP_FAILED && (uintptr_t)mapping+mapped<UINT32_MAX);
    address=(uintptr_t)mapping;
    if(low)address=(address+65535)&~(uintptr_t)65535;
    else address+=112;
    if(low && unaligned_low)address++;
    owner=(void *)address;memset(owner,0xa5,size);
    return owner;
}
void *IOMalloc(int size) { return allocate(size,0); }
void *IOMallocLow(int size) { return allocate(size,1); }
static void release(void *address,int size,int low)
{
    assert(address==owner && size==(int)requested);
    if(low)low_frees++;else wired_frees++;
    assert(munmap(mapping,mapped)==0);mapping=owner=0;
}
void IOFree(void *address,int size) { release(address,size,0); }
void IOFreeLow(void *address,int size) { release(address,size,1); }
void *IOVmTaskSelf(void) { return (void *)1; }
int IOPhysicalFromVirtual(void *task,vm_address_t address,unsigned *physical)
{
    assert(task==(void *)1);
    *physical=0x2000000+address-(uintptr_t)mapping;
    if(broken_mapping && address>=(uintptr_t)owner+8192)*physical+=4096;
    return IO_R_SUCCESS;
}
static void reset(void)
{
    assert(!mapping);requested=wired_calls=low_calls=wired_frees=low_frees=0;
    fail_allocation=broken_mapping=unaligned_low=0;
}
int main(void)
{
    unsigned sizes[]={256,4096,8192,12288,32768,36864,65536},i,j;
    struct DMARegion region;
    for(i=0;i<sizeof(sizes)/sizeof(sizes[0]);i++) {
        reset();memset(&region,0,sizeof(region));
        assert(dma_alloc(&region,sizes[i]));
        assert(region.size==sizes[i] && !(region.physical&4095));
        assert(region.low==(sizes[i]>8192));
        assert(wired_calls==(sizes[i]<=8192) && low_calls==(sizes[i]>8192));
        assert(requested==(sizes[i]>8192?sizes[i]:sizes[i]+8191));
        for(j=0;j<sizes[i];j++)assert(((unsigned char *)region.address)[j]==0);
        assert(!dma_alloc(&region,sizes[i])); /* no lost owner */
        dma_free(&region);assert(!region.allocation);
        assert(wired_frees==wired_calls && low_frees==low_calls);
    }
    for(i=0;i<2;i++) {
        reset();memset(&region,0,sizeof(region));broken_mapping=1;
        assert(!dma_alloc(&region,i?32768:8192));
        assert(!region.allocation && wired_frees+low_frees==1);
    }
    reset();memset(&region,0,sizeof(region));unaligned_low=1;
    assert(!dma_alloc(&region,32768));assert(low_frees==1 && !region.allocation);
    reset();fail_allocation=1;
    assert(!dma_alloc(&region,8192));assert(!region.allocation && !wired_frees && !low_frees);
    reset();assert(!dma_alloc(&region,0));assert(!dma_alloc(&region,65537));
    assert(!wired_calls && !low_calls);
    puts("PASS DMA allocator selection, high PCI addresses, page alignment, bounds, owner release and mapping rejection");
    return 0;
}
