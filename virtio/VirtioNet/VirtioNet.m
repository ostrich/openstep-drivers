/* Native OPENSTEP virtio Ethernet. Copyright 2026. MIT license. */
#import <driverkit/IOEthernet.h>
#import <driverkit/IONetbufQueue.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <machkit/NXLock.h>
#import <kernserv/kern_server_types.h>
#include <string.h>
#include "../src/split-queue.h"
#include "../src/legacy-transport.h"
#include "../src/native-dma.h"

#define NET_SLOTS 32
#define NET_STRIDE 1600
#define NET_HEADER 10
#define NET_FRAME_OFFSET 16
#define NET_FRAME_MAX 1514
#define NET_RX_CAPACITY 1536
#define NET_MAC (1U<<5)
#define NET_STATUS (1U<<16)

struct NetIRQState { unsigned short port; volatile unsigned pending; };
static void netIRQ(void *identity,void *state,unsigned argument)
{
    struct NetIRQState *irq=(struct NetIRQState *)argument;
    unsigned pending=rd8(irq->port+VT_ISR);
    if(pending) { irq->pending|=pending;IOSendInterrupt(identity,state,IO_DEVICE_INTERRUPT_MSG); }
    else IOEnableInterrupt(identity);
}
static unsigned netPending(struct NetIRQState *irq)
{
    unsigned value;
    __asm__ volatile("xchgl %%eax,%1" : "=a"(value),"=m"(irq->pending) : "0"(0),"m"(irq->pending) : "memory");
    return value;
}

@interface VirtioNet : IOEthernet
{
    unsigned short port;
    unsigned irq,originalCommand,features;
    BOOL configured,online,closing,promiscuous,linkUp;
    id stateLock;
    IONetwork *network;
    IONetbufQueue *backlog;
    enet_addr_t mac;
    struct NetIRQState irqState;
    struct DMARegion rings[2],buffers[2];
    struct vq queues[2];
    unsigned slotForHead[2][VQ_MAX];
    unsigned char txBusy[NET_SLOTS];
    ns_time_t txStarted[NET_SLOTS];
    unsigned received,submitted,completed,dropped,errors,resets,interrupts;
#ifdef VIRTIO_NET_TESTING
    const char *testFailure;
    BOOL testFaultsEnabled;
#endif
}
- (BOOL)stopHardware;
- (BOOL)startHardware;
- (int)postSlot:(unsigned)slot queue:(unsigned)queue length:(unsigned)length;
- (void)submitPacket:(netbuf_t)packet slot:(unsigned)slot;
- (void)drainBacklog;
#ifdef VIRTIO_NET_TESTING
- (BOOL)testFault:(const char *)stage;
#endif
@end

@implementation VirtioNet
+ (BOOL)probe:description
{
    IOPCIConfigSpace pci;
    IORange ports;
    unsigned interrupt;
    id device;
    IOReturn status;
    memset(&pci,0,sizeof(pci));
    status=[self getPCIConfigSpace:&pci withDeviceDescription:description];
#ifdef VIRTIO_NET_TESTING
    IOLog("VirtioNetTest: PCI status %d ID %x:%x BAR %x IRQ %u\n",status,pci.VendorID,pci.DeviceID,(unsigned)pci.BaseAddress[0],pci.InterruptLine);
#endif
    if(status!=IO_R_SUCCESS || pci.VendorID!=0x1af4 || pci.DeviceID!=0x1000)return NO;
    if(!(pci.BaseAddress[0]&1) || (pci.BaseAddress[0]&~3U)>0xffe0)return NO;
    interrupt=pci.InterruptLine;if(interrupt<3 || interrupt>15)return NO;
    ports.start=pci.BaseAddress[0]&~3U;ports.size=32;
    status=[description setPortRangeList:&ports num:1];
#ifdef VIRTIO_NET_TESTING
    IOLog("VirtioNetTest: port resource status %d\n",status);
#endif
    if(status!=IO_R_SUCCESS)return NO;
    status=[description setInterruptList:&interrupt num:1];
#ifdef VIRTIO_NET_TESTING
    IOLog("VirtioNetTest: IRQ resource status %d\n",status);
#endif
    if(status!=IO_R_SUCCESS)return NO;
    device=[self alloc];return [device initFromDeviceDescription:description]!=nil;
}
- initFromDeviceDescription:description
{
    IOPCIConfigSpace pci;
    unsigned i,n;
    /* IOEthernet creates its command-serving worker. Its synchronous command-4
     * teardown must precede reclaiming any driver state or DMA allocations. */
    if(![super initFromDeviceDescription:description])return nil;
#ifdef VIRTIO_NET_TESTING
    testFailure=[[description configTable] valueForStringKey:"VirtioNet Test Failure"];
    testFaultsEnabled=YES;
    if([self testFault:"Thread"])goto fail;
#endif
    stateLock=[NXLock new];backlog=[[IONetbufQueue alloc] initWithMaxCount:64];
    if(!stateLock || !backlog)goto fail;
    if([self getPCIConfigSpace:&pci]!=IO_R_SUCCESS)goto fail;
    port=pci.BaseAddress[0]&~3U;irq=pci.InterruptLine;irqState.port=port;
    originalCommand=pci.Command;
    if([self setPCIConfigData:originalCommand|5 atRegister:4]!=IO_R_SUCCESS)goto fail;
    configured=YES;
    if(!vt_legacy_reset(port,IODelay))goto fail;
    features=rd32(port+VT_HOST_FEATURES)&(NET_MAC|NET_STATUS);
    if(!(features&NET_MAC))goto fail;
    for(i=0;i<6;i++)((unsigned char *)&mac)[i]=rd8(port+20+i);
    if(((unsigned char *)&mac)[0]&1)goto fail;
    for(i=0;i<2;i++) {
        wr16(port+VT_QUEUE_SELECT,i);n=rd16(port+VT_QUEUE_SIZE);
        if(n<2*NET_SLOTS || !dma_alloc(&rings[i],vq_bytes(n)))goto fail;
#ifdef VIRTIO_NET_TESTING
        if([self testFault:i?"Ring1":"Ring0"])goto fail;
#endif
        if(!dma_alloc(&buffers[i],NET_SLOTS*NET_STRIDE))goto fail;
#ifdef VIRTIO_NET_TESTING
        if([self testFault:i?"Buffer1":"Buffer0"])goto fail;
#endif
    }
    network=[super attachToNetworkWithAddress:mac];
    if(!network)goto fail;
    /* An unconfigured secondary interface can remain down after attachment.
     * IOEthernet's finishInitialization command enables hardware separately. */
    IOLog("VirtioNet: attached, IRQ %u\n",irq);
    return self;
fail:
    IOLog("VirtioNet: initialization failed\n");return [self free];
}
- (BOOL)getHandler:(IOInterruptHandler *)handler level:(unsigned *)level
          argument:(unsigned *)argument forInterrupt:(unsigned)local
{
    if(local)return NO;
    *handler=netIRQ;*level=3;*argument=(unsigned)&irqState;return YES;
}
- (BOOL)stopHardware
{
    BOOL safe;
    online=NO;[self setRunning:NO];[self clearTimeout];[self disableAllInterrupts];
    if(!configured)return YES;
    safe=vt_legacy_reset(port,IODelay);
    /* A suspended registered source holds the whole shared IRQ masked in this
     * kernel. Once device reset guarantees no DMA/owned interrupt, keep its
     * empty-ISR callback armed so peers can run. Closing removes the source. */
    if(safe && !closing)[self enableAllInterrupts];
    return safe;
}
- (int)postSlot:(unsigned)slot queue:(unsigned)queue length:(unsigned)length
{
    struct vq_buffer chain[2];
    unsigned address=buffers[queue].physical+slot*NET_STRIDE;
    int head;
    chain[0].lo=address;chain[0].hi=0;chain[0].length=NET_HEADER;chain[0].device_writes=queue==0;
    chain[1].lo=address+NET_FRAME_OFFSET;chain[1].hi=0;chain[1].length=length;chain[1].device_writes=queue==0;
    head=vq_submit_chain(&queues[queue],chain,2);
    if(head>=0)slotForHead[queue][head]=slot;
    return head;
}
#ifdef VIRTIO_NET_TESTING
- (BOOL)testFault:(const char *)stage
{ return testFaultsEnabled && testFailure && !strcmp(testFailure,stage); }
#endif
- (BOOL)startHardware
{
    unsigned q,i,n;
    if(!vt_legacy_begin(port,features))return NO;
    for(q=0;q<2;q++) {
        wr16(port+VT_QUEUE_SELECT,q);n=rd16(port+VT_QUEUE_SIZE);
        if(vq_init(&queues[q],rings[q].address,rings[q].size,n) || !vt_legacy_queue(port,q,rings[q].physical,n))return NO;
        for(i=0;i<VQ_MAX;i++)slotForHead[q][i]=NET_SLOTS;
        memset(buffers[q].address,0,buffers[q].size);
    }
    memset(txBusy,0,sizeof(txBusy));netPending(&irqState);
    for(i=0;i<NET_SLOTS;i++)if([self postSlot:i queue:0 length:NET_RX_CAPACITY]<0)return NO;
    linkUp=!(features&NET_STATUS) || (rd16(port+26)&1);
    if(!vt_legacy_ready(port))return NO;
    online=YES;[self setRunning:YES];
    if([self enableAllInterrupts]!=IO_R_SUCCESS)return NO;
    wr16(port+VT_QUEUE_NOTIFY,0);[self setRelativeTimeout:1000];return YES;
}
- (BOOL)resetAndEnable:(BOOL)enable
{
    BOOL ok;
    netbuf_t packet;
    unsigned i;
    [stateLock lock];
    for(i=0;i<NET_SLOTS;i++)if(txBusy[i]) { dropped++;if(network)[network incrementOutputErrors]; }
    while(backlog && (packet=[backlog dequeue])) { nb_free(packet);dropped++;if(network)[network incrementOutputErrors]; }
    ok=[self stopHardware];
    if(ok && enable && !closing)ok=[self startHardware];
    if(!ok) { errors++;[self stopHardware];IOLog("VirtioNet: device setup/reset failed\n"); }
    resets++;[stateLock unlock];return ok;
}
- (void)submitPacket:(netbuf_t)packet slot:(unsigned)slot
{
    unsigned length=nb_size(packet);
    unsigned char *memory=(unsigned char *)buffers[1].address+slot*NET_STRIDE;
    memset(memory,0,NET_FRAME_OFFSET);
    memcpy(memory+NET_FRAME_OFFSET,nb_map(packet),length);
    nb_free(packet);
    if([self postSlot:slot queue:1 length:length]<0) {
        errors++;dropped++;[network incrementOutputErrors];return;
    }
    txBusy[slot]=1;IOGetTimestamp(&txStarted[slot]);submitted++;
    wr16(port+VT_QUEUE_NOTIFY,1);
}
- (void)drainBacklog
{
    unsigned slot;
    netbuf_t packet;
    for(slot=0;slot<NET_SLOTS && online && linkUp;slot++)
        if(!txBusy[slot] && (packet=[backlog dequeue]))[self submitPacket:packet slot:slot];
}
- (void)transmit:(netbuf_t)packet
{
    unsigned slot,length=nb_size(packet);
    if(length<14 || length>NET_FRAME_MAX) {
        nb_free(packet);[stateLock lock];dropped++;[network incrementOutputErrors];[stateLock unlock];return;
    }
    [self performLoopback:packet];
    [stateLock lock];
    if(!online || closing || !linkUp) { nb_free(packet);dropped++;[network incrementOutputErrors]; }
    else {
        for(slot=0;slot<NET_SLOTS && txBusy[slot];slot++);
        if(slot<NET_SLOTS)[self submitPacket:packet slot:slot];
        else if([backlog count]<[backlog maxCount])[backlog enqueue:packet];
        else { nb_free(packet);dropped++;[network incrementOutputErrors]; }
    }
    [stateLock unlock];
}
- (void)interruptOccurred
{
    netbuf_t packets[NET_SLOTS];
    unsigned packetCount=0,rxWork=0,id,length,slot,pending,i;
    int result;
    BOOL broken=NO;
    [stateLock lock];pending=netPending(&irqState);interrupts++;
    if(online && pending) {
        if(pending&2)linkUp=!(features&NET_STATUS) || (rd16(port+26)&1);
        while((result=vq_complete(&queues[1],&id,&length))==1) {
            slot=slotForHead[1][id];
            if(slot>=NET_SLOTS || !txBusy[slot]) { broken=YES;break; }
            txBusy[slot]=0;slotForHead[1][id]=NET_SLOTS;completed++;
            [network incrementOutputPackets];
        }
        if(result<0)broken=YES;
#ifdef VIRTIO_NET_TESTING
        if([self testFault:"Completion"] &&
           ((volatile unsigned short *)(queues[0].ring+queues[0].used_offset))[1]!=queues[0].consumed) {
            volatile struct vq_used *entries=(volatile struct vq_used *)(queues[0].ring+queues[0].used_offset+4);
            entries[queues[0].consumed&(queues[0].n-1)].id=queues[0].n;
        }
#endif
        while(!broken && rxWork<NET_SLOTS && (result=vq_complete(&queues[0],&id,&length))==1) {
            unsigned char *memory;
            rxWork++;
            slot=slotForHead[0][id];
            if(slot>=NET_SLOTS) { broken=YES;break; }
            slotForHead[0][id]=NET_SLOTS;
            memory=(unsigned char *)buffers[0].address+slot*NET_STRIDE;
#ifdef VIRTIO_NET_TESTING
            if([self testFault:"Short"])length=NET_HEADER-1;
            if([self testFault:"Oversize"])length=NET_HEADER+NET_FRAME_MAX+1;
#endif
            /* No checksum/GSO or merged receive features negotiated. */
            if(length<NET_HEADER+14 || length>NET_HEADER+NET_FRAME_MAX || (memory[0]&1) || memory[1]) {
                dropped++;[network incrementInputErrors];
            } else {
                netbuf_t packet;
#ifdef VIRTIO_NET_TESTING
                packet=[self testFault:"RxAlloc"]?0:nb_alloc(length-NET_HEADER);
#else
                packet=nb_alloc(length-NET_HEADER);
#endif
                if(packet) {
                    memcpy(nb_map(packet),memory+NET_FRAME_OFFSET,length-NET_HEADER);
                    packets[packetCount++]=packet;received++;
                } else { dropped++;[network incrementInputErrors]; }
            }
            memset(memory,0,NET_FRAME_OFFSET);
            if([self postSlot:slot queue:0 length:NET_RX_CAPACITY]<0)broken=YES;
        }
        if(result<0)broken=YES;
        if(broken) { errors++;[self stopHardware];IOLog("VirtioNet: invalid queue completion; device stopped\n"); }
        else { wr16(port+VT_QUEUE_NOTIFY,0);[self drainBacklog]; }
    }
    [stateLock unlock];
    /* Network input may synchronously generate output; never hold stateLock. */
    for(i=0;i<packetCount;i++) {
        unsigned char *frame=nb_map(packets[i]);
        if(!promiscuous && ((!(frame[0]&1) && memcmp(frame,&mac,6)) ||
            [super isUnwantedMulticastPacket:(ether_header_t *)frame]))nb_free(packets[i]);
        else if(network)[network handleInputPacket:packets[i] extra:0];
        else nb_free(packets[i]);
    }
    if(!closing)[self enableAllInterrupts];
}
- (void)timeoutOccurred
{
    ns_time_t now;
    unsigned slot;
    BOOL stalled=NO;
    [stateLock lock];IOGetTimestamp(&now);
    if(online) {
        linkUp=!(features&NET_STATUS) || (rd16(port+26)&1);
        for(slot=0;slot<NET_SLOTS;slot++)if(txBusy[slot] && now-txStarted[slot]>=2000000000ULL)stalled=YES;
        if(!stalled)[self setRelativeTimeout:1000];
    }
    [stateLock unlock];
    if(stalled) { IOLog("VirtioNet: transmit stalled; resetting device\n");[self resetAndEnable:YES]; }
}
- (BOOL)enablePromiscuousMode { promiscuous=YES;return YES; }
- (void)disablePromiscuousMode { promiscuous=NO; }
- (BOOL)enableMulticastMode { return YES; }
- (void)disableMulticastMode { }
- (void)addMulticastAddress:(enet_addr_t *)address { }
- (void)removeMulticastAddress:(enet_addr_t *)address { }
/* Preserve the existing adapter's debugger registration: this driver does not
 * implement the polled kernel-debugger sendPacket/receivePacket interface. */
- (void)registerAsDebuggerDevice { }
- (IOReturn)getIntValues:(unsigned *)values forParameter:(IOParameterName)name count:(unsigned *)count
{
    if(strcmp(name,"VirtioNetStats"))return [super getIntValues:values forParameter:name count:count];
    if(*count<12)return IO_R_INVALID_ARG;
    [stateLock lock];values[0]=received;values[1]=submitted;values[2]=completed;
    values[3]=dropped;values[4]=errors;values[5]=resets;values[6]=interrupts;
    values[7]=online;values[8]=linkUp;values[9]=queues[0].outstanding;
    values[10]=queues[1].outstanding;values[11]=[backlog count];
    [stateLock unlock];*count=12;return IO_R_SUCCESS;
}
- (IOReturn)setIntValues:(unsigned *)values forParameter:(IOParameterName)name count:(unsigned)count
{
#ifdef VIRTIO_NET_TESTING
    if(!strcmp(name,"VirtioNetTestFaults")) {
        if(count!=1 || values[0]!=0)return IO_R_INVALID_ARG;
        [stateLock lock];testFaultsEnabled=NO;[stateLock unlock];return IO_R_SUCCESS;
    }
#endif
    if(strcmp(name,"VirtioNetReset"))return [super setIntValues:values forParameter:name count:count];
    if(count!=1 || values[0]!=1)return IO_R_INVALID_ARG;
    return [self resetAndEnable:YES]?IO_R_SUCCESS:IO_R_IO;
}
- free
{
    struct DMARegion savedRings[2],savedBuffers[2];
    id savedLock=stateLock,savedBacklog=backlog,result;
    BOOL safe;
    unsigned i;
    closing=YES;[stateLock lock];safe=[self stopHardware];[stateLock unlock];
#ifdef VIRTIO_NET_TESTING
    IOLog("VirtioNetTest: unwind %s, DMA reset safe %u\n",testFailure?testFailure:"none",safe);
    if(testFailure) { [[[self deviceDescription] configTable] freeString:testFailure];testFailure=0; }
#endif
    for(i=0;i<2;i++) { savedRings[i]=rings[i];savedBuffers[i]=buffers[i]; }
    if(configured && safe)[self setPCIConfigData:originalCommand atRegister:4];
    /* IOEthernet command-4 is synchronous and the worker performs no accesses
     * to this object after acknowledging its final command (kernel verified). */
    result=[super free];
    if(safe)for(i=0;i<2;i++) {
        if(savedRings[i].allocation)IOFreeLow(savedRings[i].allocation,savedRings[i].allocated);
        if(savedBuffers[i].allocation)IOFreeLow(savedBuffers[i].allocation,savedBuffers[i].allocated);
    }
    [savedBacklog free];[savedLock free];
#ifdef VIRTIO_NET_TESTING
    IOLog("VirtioNetTest: unwind complete\n");
#endif
    return result;
}
@end
kern_server_t VirtioNet_instance;
@interface VirtioNetKernelServerInstance : Object
@end
@implementation VirtioNetKernelServerInstance
+ (kern_server_t *)kernelServerInstance { return &VirtioNet_instance; }
@end
@interface VirtioNetVersion : IODevice
@end
@implementation VirtioNetVersion
+ (int)driverKitVersionForVirtioNet { return IO_DRIVERKIT_VERSION; }
@end
