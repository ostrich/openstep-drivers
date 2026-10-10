#ifndef OS42_VIRTIO_LEGACY_TRANSPORT_H
#define OS42_VIRTIO_LEGACY_TRANSPORT_H
#include "legacy-pci.h"
#include "legacy-io.h"
/* Reusable legacy transport operations. Caller owns PCI resources and DMA;
 * device-specific code chooses features/queues and serializes register access.
 * Reset is synchronous; delay callback is needed only if acknowledgment lags. */
static int vt_legacy_reset(unsigned short port,void (*delay)(unsigned))
{
    unsigned i;
    wr8(port+VT_STATUS,0);
    for(i=0;i<1000;i++) {
        if(!rd8(port+VT_STATUS))return 1;
        delay(10);
    }
    return 0;
}
static int vt_legacy_begin(unsigned short port,unsigned features)
{
    unsigned offered=rd32(port+VT_HOST_FEATURES);
    if(features&~offered)return 0;
    wr8(port+VT_STATUS,VT_ACK);wr8(port+VT_STATUS,VT_ACK|VT_DRIVER);
    wr32(port+VT_GUEST_FEATURES,features);return 1;
}
static int vt_legacy_queue(unsigned short port,unsigned short index,
                           unsigned physical,unsigned entries)
{
    if(!physical || (physical&4095))return 0;
    wr16(port+VT_QUEUE_SELECT,index);
    if(rd16(port+VT_QUEUE_SIZE)!=entries)return 0;
    wr32(port+VT_QUEUE_PFN,physical>>12);
    return rd32(port+VT_QUEUE_PFN)==(physical>>12);
}
static int vt_legacy_ready(unsigned short port)
{
    wr8(port+VT_STATUS,VT_ACK|VT_DRIVER|VT_READY);
    return rd8(port+VT_STATUS)==(VT_ACK|VT_DRIVER|VT_READY);
}
#endif
