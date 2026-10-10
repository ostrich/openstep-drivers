/* MIT license. Legacy virtio-serial driver, one or two independent ports.
 * Queue indices: control 2/3, port-1 data 4/5, port-2 data 6/7. */
#import <driverkit/IODirectDevice.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/kernelDriver.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <machkit/NXLock.h>
#import <kernserv/kern_server_types.h>
#import <kernserv/prototypes.h>
#import <mach/vm_param.h>
#include <string.h>
#include "../src/split-queue.h"
#include "../src/legacy-transport.h"
struct DMARegion { void *allocation;unsigned allocated;void *address;unsigned physical,size; };
#include "../src/console-buffer.h"
#include "../src/console-link.h"
#ifdef VIRTIO_CONSOLE_DIAGNOSTICS
#define VCLOG(args) IOLog args
#define VCSTAGE(text) failureStage=text
#else
#define VCLOG(args)
#define VCSTAGE(text)
#endif
struct VCInterrupt { unsigned short port;volatile unsigned pending; };
static void vcInterrupt(void *identity,void *state,unsigned argument)
{
    struct VCInterrupt *irq=(struct VCInterrupt *)argument;unsigned pending=rd8(irq->port+VT_ISR);
    if(pending) { irq->pending|=pending;IOSendInterrupt(identity,state,IO_DEVICE_INTERRUPT_MSG); }
    else IOEnableInterrupt(identity);
}
static unsigned vcTake(struct VCInterrupt *irq)
{
    unsigned value;__asm__ volatile("xchgl %%eax,%1":"=a"(value),"=m"(irq->pending):"0"(0),"m"(irq->pending):"memory");return value;
}
/* One owned 64 KiB pool avoids exhausting the scarce low-memory allocator.
 * Control payloads occupy unused first-page ring padding: metadata ends below
 * offset 1024, and the used list starts at 4096. Data arenas follow four rings.
 * Each ring and each data slot is independently physically validated. */
static int vcPoolAlloc(struct DMARegion *pool,struct DMARegion *rings,
                       struct DMARegion *buffers,unsigned *rx,unsigned *tx)
{
    unsigned i,j,first,last,off;
    if(PAGE_SIZE!=8192)return 0;
    pool->allocated=65536;pool->allocation=IOMallocLow(pool->allocated);
    if(!pool->allocation) { VCLOG(("VirtioConsoleProbe: DMA pool unavailable\n"));return 0; }
    pool->address=pool->allocation;pool->size=65536;
    if((unsigned)pool->address&(PAGE_SIZE-1))goto fail;
    memset(pool->address,0,pool->size);
    for(i=0;i<4;i++) {
        rings[i].address=(unsigned char *)pool->address+i*8192;rings[i].size=8192;
        if(IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)rings[i].address,&first)!=IO_R_SUCCESS || (first&4095))goto fail;
        for(off=0;off<8192;off+=4096)if(IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)rings[i].address+off,&last)!=IO_R_SUCCESS || last!=first+off)goto fail;
        if(IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)rings[i].address+8191,&last)!=IO_R_SUCCESS || last!=first+8191)goto fail;
        rings[i].physical=first;
        VCLOG(("VirtioConsoleProbe: pool ring %u physical=%x\n",i+2,first));
    }
    buffers[0].address=(unsigned char *)rings[0].address+1024;buffers[0].physical=rings[0].physical+1024;buffers[0].size=2048;
    buffers[1].address=(unsigned char *)rings[1].address+1024;buffers[1].physical=rings[1].physical+1024;buffers[1].size=256;
    for(i=2;i<4;i++) {
        unsigned *addresses=i==2?rx:tx;
        buffers[i].address=(unsigned char *)pool->address+32768+(i-2)*16384;buffers[i].size=16384;
        for(j=0;j<32;j++) {
            if(IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)buffers[i].address+j*512,&first)!=IO_R_SUCCESS ||
               IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)buffers[i].address+j*512+511,&last)!=IO_R_SUCCESS ||
               first>~0U-511 || last!=first+511 || (first&4095)!=(((unsigned)buffers[i].address+j*512)&4095))goto fail;
            addresses[j]=first;
        }
        buffers[i].physical=addresses[0];
    }
    return 1;
fail:
    VCLOG(("VirtioConsoleProbe: DMA pool alignment/translation failed\n"));
    IOFreeLow(pool->allocation,pool->allocated);memset(pool,0,sizeof(*pool));return 0;
}
static int vcExtraAlloc(struct DMARegion *pool,struct DMARegion *rings,
                         struct DMARegion *buffers,unsigned *rx,unsigned *tx)
{
    unsigned i,j,off,first,last;
    pool->allocated=49152;pool->allocation=IOMallocLow(pool->allocated);
    if(!pool->allocation)return 0;
    pool->address=pool->allocation;pool->size=pool->allocated;
    if((unsigned)pool->address&(PAGE_SIZE-1))goto fail;
    memset(pool->address,0,pool->size);
    for(i=0;i<2;i++) {
        rings[i].address=(unsigned char *)pool->address+i*8192;rings[i].size=8192;
        if(IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)rings[i].address,&first)!=IO_R_SUCCESS || (first&4095))goto fail;
        for(off=0;off<8192;off+=4096)if(IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)rings[i].address+off,&last)!=IO_R_SUCCESS || last!=first+off)goto fail;
        if(IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)rings[i].address+8191,&last)!=IO_R_SUCCESS || last!=first+8191)goto fail;
        rings[i].physical=first;
        buffers[i].address=(unsigned char *)pool->address+16384+i*16384;buffers[i].size=16384;
        for(j=0;j<32;j++) {
            unsigned *addresses=i==0?rx:tx;
            if(IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)buffers[i].address+j*512,&first)!=IO_R_SUCCESS ||
               IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_address_t)buffers[i].address+j*512+511,&last)!=IO_R_SUCCESS ||
               first>~0U-511 || last!=first+511)goto fail;
            addresses[j]=first;
        }
        buffers[i].physical=(i==0?rx:tx)[0];
    }
    return 1;
fail:
    IOFreeLow(pool->allocation,pool->allocated);memset(pool,0,sizeof(*pool));return 0;
}
static unsigned vc_port_id(const unsigned char *p)
{ return (unsigned)p[0]|((unsigned)p[1]<<8)|((unsigned)p[2]<<16)|((unsigned)p[3]<<24); }
static int vcParameter(const char *name,const char *prefix,unsigned *generation)
{
    unsigned value=0,i,n=strlen(prefix);if(strncmp(name,prefix,n))return 0;
    for(i=0;i<8;i++) {
        unsigned ch=(unsigned char)name[n+i],digit;
        if(ch>='0' && ch<='9')digit=ch-'0';else if(ch>='a' && ch<='f')digit=ch-'a'+10;else return -1;
        value=(value<<4)|digit;
    }
    if(name[n+8] || !value)return -1;*generation=value;return 1;
}
struct VCChannel {
    struct vc_link link;
    struct vc_fifo receive;unsigned char receiveBytes[32768];
    unsigned reserved,received,transmitted;
    unsigned rxGeneration[128],rxPhysical[32],txPhysical[32];
    ns_time_t txDeadline[128];
};
@interface VirtioConsole : IODirectDevice
{
    unsigned short port;unsigned irq,originalCommand;
    BOOL configured,online;volatile BOOL closing,workerRunning;
    id stateLock;struct VCInterrupt irqState;unsigned numPorts;
    struct VCChannel channels[2];
    struct DMARegion dmaPool,extraPool,rings[6],buffers[6];struct vq queues[6];
    unsigned errors,resets,interrupts;
    #ifdef VIRTIO_CONSOLE_TESTING
    const char *testFailure;unsigned testNextFault;
#endif
    ns_time_t discoveryDeadline,discoveryRetry;
}
- (BOOL)resetDevice;
- (BOOL)setupQueues;
- (BOOL)control:(unsigned)event value:(unsigned)value portID:(unsigned)portID;
- (BOOL)postReceive:(unsigned)channel;
- (BOOL)fenceReceive:(unsigned)channel;
- serviceThread;
- pump;
@end
static void vcThread(void *argument) { [(VirtioConsole *)argument serviceThread];IOExitThread(); }
@implementation VirtioConsole
+ (BOOL)probe:description
{
    IOPCIConfigSpace pci;IORange ports;unsigned interrupt;id device;IOReturn pciResult,resourceResult;
    memset(&pci,0,sizeof(pci));pciResult=[self getPCIConfigSpace:&pci withDeviceDescription:description];
    VCLOG(("VirtioConsoleProbe: pci=%d vendor=%x device=%x BAR0=%x IRQ=%u\n",pciResult,pci.VendorID,pci.DeviceID,(unsigned)pci.BaseAddress[0],(unsigned)pci.InterruptLine));
    if(pciResult!=IO_R_SUCCESS || pci.VendorID!=0x1af4 || pci.DeviceID!=0x1003)return NO;
    if(!(pci.BaseAddress[0]&1) || (pci.BaseAddress[0]&~3U)>0xffe0)return NO;
    interrupt=pci.InterruptLine;if(interrupt<3 || interrupt>15)return NO;
    ports.start=pci.BaseAddress[0]&~3U;ports.size=32;
    resourceResult=[description setPortRangeList:&ports num:1];
    if(resourceResult==IO_R_SUCCESS)resourceResult=[description setInterruptList:&interrupt num:1];
    VCLOG(("VirtioConsoleProbe: resources=%d port=%x IRQ=%u\n",resourceResult,(unsigned)ports.start,interrupt));
    if(resourceResult!=IO_R_SUCCESS)return NO;
    device=[self alloc];return [device initFromDeviceDescription:description]!=nil;
}
- initFromDeviceDescription:description
{
    IOPCIConfigSpace pci;unsigned i,n,stage=0;BOOL ready;const char *portSetting;
    if(![super initFromDeviceDescription:description]) { VCLOG(("VirtioConsoleProbe: superclass initialization refused\n"));return [super free]; }
    #ifdef VIRTIO_CONSOLE_TESTING
    testFailure=[[description configTable] valueForStringKey:"VirtioConsole Test Failure"];
#endif
    stage=1;(void)stage;stateLock=[NXLock new];if(!stateLock)goto fail;
    numPorts=1;portSetting=[[description configTable] valueForStringKey:"VirtioConsole Ports"];
    if(portSetting) {
        if(!strcmp(portSetting,"2"))numPorts=2;
        else if(strcmp(portSetting,"1")) { [[[self deviceDescription] configTable] freeString:portSetting];goto fail; }
        [[[self deviceDescription] configTable] freeString:portSetting];
    }
    for(i=0;i<numPorts;i++) {
        vc_link_init(&channels[i].link);
        vc_fifo_init(&channels[i].receive,channels[i].receiveBytes,sizeof(channels[i].receiveBytes));
    }
    stage=2;if([self getPCIConfigSpace:&pci]!=IO_R_SUCCESS)goto fail;
    port=pci.BaseAddress[0]&~3U;irq=pci.InterruptLine;originalCommand=pci.Command;irqState.port=port;
    if([self setPCIConfigData:originalCommand|5 atRegister:4]!=IO_R_SUCCESS)goto fail;
    stage=3;configured=YES;if(![self resetDevice])goto fail;
    for(i=0;i<2+2*numPorts;i++) {
        stage=4+i;wr16(port+VT_QUEUE_SELECT,i+2);n=rd16(port+VT_QUEUE_SIZE);
        VCLOG(("VirtioConsoleProbe: allocating queue %u entries=%u\n",i+2,n));
        if(n!=(i<2?32:128) || vq_bytes(n)!=8192)goto fail;
    }
    stage=7;if(!vcPoolAlloc(&dmaPool,rings,buffers,channels[0].rxPhysical,channels[0].txPhysical))goto fail;
    #ifdef VIRTIO_CONSOLE_TESTING
    if(testFailure && !strcmp(testFailure,"Pool"))goto fail;
#endif
    if(numPorts==2 && !vcExtraAlloc(&extraPool,rings+4,buffers+4,channels[1].rxPhysical,channels[1].txPhysical))goto fail;
    stage=8;if([self attachInterruptPort]!=IO_R_SUCCESS)goto fail;
    stage=9;workerRunning=YES;if(!IOForkThread(vcThread,self)) { workerRunning=NO;goto fail; }
    #ifdef VIRTIO_CONSOLE_TESTING
    if(testFailure && !strcmp(testFailure,"Worker"))goto fail;
#endif
    stage=10;if([self enableAllInterrupts]!=IO_R_SUCCESS)goto fail;
    stage=11;[stateLock lock];ready=[self setupQueues];[stateLock unlock];if(!ready)goto fail;
    [self setName:"VirtioConsole0"];[self registerDevice];
    IOLog("VirtioConsole: %u port(s) ready, IRQ %u\n",numPorts,irq);return self;
fail:
    VCLOG(("VirtioConsoleProbe: init failed at stage %u\n",stage));
    [self free];return nil;
}
- (BOOL)resetDevice
{
    unsigned i;online=NO;
    if(!vt_legacy_reset(port,IODelay))return NO;
    vcTake(&irqState);
    for(i=0;i<numPorts;i++) {
        vc_link_reset(&channels[i].link);vc_fifo_clear(&channels[i].receive);
        channels[i].reserved=0;
    }
    discoveryDeadline=discoveryRetry=0;resets++;return YES;
}
- (BOOL)control:(unsigned)event value:(unsigned)value portID:(unsigned)portID
{
    unsigned id;int submitted;struct vq *q=&queues[1];
    for(id=0;id<32 && q->busy[id];id++);if(id==32)return NO;
    vc_control_encode((unsigned char *)buffers[1].address+id*8,event,value,portID);
    submitted=vq_submit(q,buffers[1].physical+id*8,0,8,0);if(submitted!=(int)id)return NO;
    wr16(port+VT_QUEUE_NOTIFY,3);return YES;
}
- (BOOL)setupQueues
{
    unsigned i,j,n;ns_time_t now;
    if(!vt_legacy_begin(port,2))return NO;
    for(i=0;i<2+2*numPorts;i++) {
        n=i<2?32:128;
        if(vq_init(&queues[i],rings[i].address,rings[i].size,n) || !vt_legacy_queue(port,i+2,rings[i].physical,n))return NO;
    }
    for(i=0;i<numPorts;i++) { memset(channels[i].txDeadline,0,sizeof(channels[i].txDeadline));memset(channels[i].rxGeneration,0,sizeof(channels[i].rxGeneration)); }
    for(j=0;j<32;j++)if(vq_submit(&queues[0],buffers[0].physical+j*64,0,64,1)!=(int)j)return NO;
    if(!vt_legacy_ready(port))return NO;
    IOGetTimestamp(&now);discoveryDeadline=now+10000000000ULL;discoveryRetry=now+100000000ULL;
    online=YES;return [self control:0 value:1 portID:0];
}
- (BOOL)postReceive:(unsigned)channel
{
    struct VCChannel *ch=&channels[channel];unsigned id,qrx=2+2*channel;
    int result;BOOL posted=NO;
    if(!ch->link.present || !ch->link.host_open)return YES;
    while(vc_fifo_can_reserve(&ch->receive,ch->reserved,512)) {
        for(id=0;id<32 && queues[qrx].busy[id];id++);if(id==32)break;
        result=vq_submit(&queues[qrx],ch->rxPhysical[id],0,512,1);if(result!=(int)id)return NO;
        ch->rxGeneration[id]=ch->link.generation;ch->reserved+=512;posted=YES;
    }
    if(posted)wr16(port+VT_QUEUE_NOTIFY,qrx+2);return YES;
}
- (BOOL)fenceReceive:(unsigned)channel
{
    struct VCChannel *ch=&channels[channel];unsigned qrx=2+2*channel,id,length,steps;int result;
    /* Keep all device-owned descriptors allocated. Discard completions already
     * visible at the session boundary, then bind still-posted receive credits
     * to the new generation. Clients synchronize after observing host-open. */
    vc_fifo_clear(&ch->receive);
    for(steps=0;steps<32;steps++) {
        result=vq_complete(&queues[qrx],&id,&length);
        if(result<0)return NO;if(!result)break;
        if(id>=32 || !length || length>512 || ch->reserved<512)return NO;
        ch->reserved-=512;
    }
    for(id=0;id<32;id++)if(queues[qrx].busy[id])ch->rxGeneration[id]=ch->link.generation;
    return YES;
}
- pump
{
    unsigned id,length,steps,actions,channel,qrx,qtx,portID;struct VCChannel *ch;int result;ns_time_t now;
#ifdef VIRTIO_CONSOLE_DIAGNOSTICS
    const char *failureStage="entry";id=length=0;result=0;
#endif
    ch=&channels[0];[stateLock lock];if(!online || closing)goto done;
    if(vcTake(&irqState))interrupts++;
    VCSTAGE("control-tx");
    for(steps=0;steps<32;steps++) {
        result=vq_complete(&queues[1],&id,&length);if(result<0)goto fault;if(!result)break;
        if(id>=32 || length>8)goto fault;
    }
    VCSTAGE("control-rx");
    for(steps=0;steps<32;steps++) {
        VCSTAGE("control-rx");result=vq_complete(&queues[0],&id,&length);if(result<0)goto fault;if(!result)break;
        if(id>=32 || length<8 || length>64)goto fault;
        portID=vc_port_id((unsigned char *)buffers[0].address+id*64);
        if(portID<1 || portID>numPorts)goto fault;
        channel=portID-1;ch=&channels[channel];
        result=numPorts==1?vc_link_control(&ch->link,(unsigned char *)buffers[0].address+id*64,length):vc_link_control_port(&ch->link,portID,(unsigned char *)buffers[0].address+id*64,length);
        if(result<0) {
            VCLOG(("VirtioConsoleFault: control id=%u event=%u value=%u bytes=%u policy=%d present=%u open=%u\n",(unsigned)((unsigned char *)buffers[0].address)[id*64],(unsigned)((unsigned char *)buffers[0].address)[id*64+4],(unsigned)((unsigned char *)buffers[0].address)[id*64+6],length,result,ch->link.present,ch->link.host_open));
            VCSTAGE("control-policy");goto fault;
        }
        actions=(unsigned)result;
        if(actions&VC_LINK_CLEAR) {
            if(numPorts==1)vc_fifo_clear(&ch->receive);
            else if(![self fenceReceive:channel])goto fault;
        }
        VCSTAGE("control-ready");if(actions&VC_LINK_READY)if(![self control:3 value:1 portID:portID])goto fault;
        VCSTAGE("control-open");if(actions&VC_LINK_OPEN)if(![self control:6 value:1 portID:portID])goto fault;
        /* A close/removal fences all old DMA before new queues or sessions.
         * A queued transmit may already have reached the host: never replay. */
        if(numPorts==1 && (actions&VC_LINK_CLEAR) && !(actions&VC_LINK_READY) && !ch->link.host_open) {
            VCSTAGE("close-reset");if(![self resetDevice] || ![self setupQueues])goto fault;goto done;
        }
        VCSTAGE("control-repost");result=vq_submit(&queues[0],buffers[0].physical+id*64,0,64,1);if(result!=(int)id)goto fault;
        wr16(port+VT_QUEUE_NOTIFY,2);
    }
    IOGetTimestamp(&now);
    for(channel=0;channel<numPorts;channel++) {
        ch=&channels[channel];qrx=2+2*channel;qtx=qrx+1;
    VCSTAGE("data-rx");
    for(steps=0;steps<32;steps++) {
        #ifdef VIRTIO_CONSOLE_TESTING
        if(testNextFault==1 && ((volatile unsigned short *)(queues[qrx].ring+queues[qrx].used_offset))[1]!=queues[qrx].consumed) {
            volatile struct vq_used *entry=(volatile struct vq_used *)(queues[qrx].ring+queues[qrx].used_offset+4);
            entry[queues[qrx].consumed&(queues[qrx].n-1)].id=queues[qrx].n;testNextFault=0;
        }
#endif
        result=vq_complete(&queues[qrx],&id,&length);if(result<0)goto fault;if(!result)break;
        if(id>=32 || !length || length>512 || ch->reserved<512)goto fault;ch->reserved-=512;
        if(ch->link.host_open && ch->rxGeneration[id]==ch->link.generation) {
            if(vc_fifo_put(&ch->receive,(unsigned char *)buffers[qrx].address+id*512,length)!=1)goto fault;
            ch->received+=length;
        }
    }
    VCSTAGE("data-tx");
    for(steps=0;steps<32;steps++) {
        #ifdef VIRTIO_CONSOLE_TESTING
        if(testNextFault==2 && ((volatile unsigned short *)(queues[qtx].ring+queues[qtx].used_offset))[1]!=queues[qtx].consumed) {
            volatile struct vq_used *entry=(volatile struct vq_used *)(queues[qtx].ring+queues[qtx].used_offset+4);
            entry[queues[qtx].consumed&(queues[qtx].n-1)].id=queues[qtx].n;testNextFault=0;
        }
#endif
        result=vq_complete(&queues[qtx],&id,&length);if(result<0)goto fault;if(!result)break;
        if(id>=32 || length>512)goto fault;ch->txDeadline[id]=0;
    }
    VCSTAGE("tx-deadline");IOGetTimestamp(&now);
    for(id=0;id<32;id++)if(ch->txDeadline[id] && now>=ch->txDeadline[id])goto fault;
        if(![self postReceive:channel])goto fault;
    }
    /* QEMU drops control events when its receive queue has no credits. A
     * connection burst can occupy all 32 buffers before DEVICE_READY's ADD
     * reply. Drain/repost first, then repeat discovery with a finite bound. */
    if(!channels[0].link.present || (numPorts==2 && !channels[1].link.present)) {
        VCSTAGE("port-discovery");if(now>=discoveryDeadline)goto fault;
        if(now>=discoveryRetry) {
            if(![self control:0 value:1 portID:0])goto fault;
            discoveryRetry=now+100000000ULL;
        }
    }
    goto done;
fault:
    VCLOG(("VirtioConsoleFault: stage=%s result=%d id=%u length=%u present=%u open=%u generation=%u ctrl_rx_used=%u ctrl_rx_consumed=%u ctrl_tx_pending=%u rx_pending=%u tx_pending=%u\n",failureStage,result,id,length,ch->link.present,ch->link.host_open,ch->link.generation,(unsigned)((volatile unsigned short *)(queues[0].ring+queues[0].used_offset))[1],(unsigned)queues[0].consumed,queues[1].outstanding,queues[2].outstanding,queues[3].outstanding));
    errors++;[self resetDevice];IOLog("VirtioConsole: channel stopped after transport failure\n");
done:
    [stateLock unlock];return self;
}
- serviceThread
{
    msg_header_t message;msg_return_t result;
    while(!closing) {
        memset(&message,0,sizeof(message));message.msg_size=sizeof(message);message.msg_local_port=[self interruptPort];
        result=msg_receive(&message,RCV_TIMEOUT|RCV_LARGE,10);if(closing)break;
        if(result!=RCV_SUCCESS && result!=RCV_TIMED_OUT && result!=RCV_INTERRUPTED) {
            [stateLock lock];errors++;[self resetDevice];[stateLock unlock];break;
        }
        [self pump];if(!closing && result==RCV_SUCCESS && message.msg_id==IO_DEVICE_INTERRUPT_MSG)[self enableAllInterrupts];
    }
    workerRunning=NO;return self;
}
- (BOOL)getHandler:(IOInterruptHandler *)handler level:(unsigned *)level argument:(unsigned *)argument forInterrupt:(unsigned)local
{
    if(local)return NO;*handler=vcInterrupt;*level=3;*argument=(unsigned)&irqState;return YES;
}
- (IOReturn)getCharValues:(unsigned char *)data forParameter:(IOParameterName)name count:(unsigned *)count
{
    unsigned generation,n=*count,channel=0;struct VCChannel *ch;int match=vcParameter(name,"VirtioConsoleRead.",&generation);IOReturn result;
    if(!match) { channel=1;match=vcParameter(name,"VirtioConsoleRead2.",&generation); }
    if(match && channel>=numPorts)return IO_R_NO_DEVICE;ch=&channels[channel];
    if(!match)return [super getCharValues:data forParameter:name count:count];
    *count=0;if(match<0 || !n || n>512)return IO_R_INVALID_ARG;
    [stateLock lock];result=online && ch->link.host_open && generation==ch->link.generation?IO_R_SUCCESS:IO_R_NOT_READY;
    if(result==IO_R_SUCCESS) { *count=vc_fifo_get(&ch->receive,data,n);if(![self postReceive:channel]) { errors++;[self resetDevice];result=IO_R_IO; } }
    [stateLock unlock];return result;
}
- (IOReturn)setCharValues:(unsigned char *)data forParameter:(IOParameterName)name count:(unsigned)count
{
    unsigned generation,id,channel=0,qtx;struct VCChannel *ch;int match=vcParameter(name,"VirtioConsoleWrite.",&generation),submitted;ns_time_t now;IOReturn result=IO_R_SUCCESS;
    if(!match) { channel=1;match=vcParameter(name,"VirtioConsoleWrite2.",&generation); }
    if(match && channel>=numPorts)return IO_R_NO_DEVICE;ch=&channels[channel];qtx=3+2*channel;
    if(!match)return [super setCharValues:data forParameter:name count:count];
    if(match<0 || !count || count>512)return IO_R_INVALID_ARG;
    [stateLock lock];
    if(!online || !ch->link.host_open || generation!=ch->link.generation)result=IO_R_NOT_READY;
    else {
        for(id=0;id<32 && queues[qtx].busy[id];id++);
        if(id==32)result=IO_R_BUSY;
        else {
            memcpy((unsigned char *)buffers[qtx].address+id*512,data,count);
            submitted=vq_submit(&queues[qtx],ch->txPhysical[id],0,count,0);
            if(submitted!=(int)id) { errors++;[self resetDevice];result=IO_R_IO; }
            else { IOGetTimestamp(&now);ch->txDeadline[id]=now+30000000000ULL;ch->transmitted+=count;wr16(port+VT_QUEUE_NOTIFY,qtx+2); }
        }
    }
    [stateLock unlock];return result;
}
- (IOReturn)getIntValues:(unsigned *)values forParameter:(IOParameterName)name count:(unsigned *)count
{
    unsigned channel,qtx;struct VCChannel *ch;
    if(!strcmp(name,"VirtioConsoleStats"))channel=0;
    else if(!strcmp(name,"VirtioConsoleStats2"))channel=1;
    else return [super getIntValues:values forParameter:name count:count];
    if(channel>=numPorts)return IO_R_NO_DEVICE;ch=&channels[channel];qtx=3+2*channel;
    if(*count<12)return IO_R_INVALID_ARG;
    [stateLock lock];values[0]=online;values[1]=ch->link.present;values[2]=ch->link.host_open;values[3]=ch->link.generation;values[4]=ch->receive.count;values[5]=ch->reserved;values[6]=queues[qtx].outstanding;values[7]=ch->received;values[8]=ch->transmitted;values[9]=errors;values[10]=resets;values[11]=interrupts;[stateLock unlock];*count=12;return IO_R_SUCCESS;
}
- (IOReturn)setIntValues:(unsigned *)values forParameter:(IOParameterName)name count:(unsigned)count
{
    BOOL ok;
#ifdef VIRTIO_CONSOLE_TESTING
    if(!strcmp(name,"VirtioConsoleTestFault")) {
        if(count!=1 || values[0]<1 || values[0]>2)return IO_R_INVALID_ARG;
        [stateLock lock];testNextFault=values[0];[stateLock unlock];return IO_R_SUCCESS;
    }
#endif
    if(strcmp(name,"VirtioConsoleReset"))return [super setIntValues:values forParameter:name count:count];
    if(count!=1 || values[0]!=1)return IO_R_INVALID_ARG;
    [stateLock lock];ok=!closing && workerRunning && [self resetDevice] && [self setupQueues];[stateLock unlock];return ok?IO_R_SUCCESS:IO_R_IO;
}
- free
{
    struct DMARegion savedPool=dmaPool,savedExtra=extraPool;id savedLock=stateLock,result;BOOL safe=YES;unsigned i;
    #ifdef VIRTIO_CONSOLE_TESTING
    IOLog("VirtioConsoleTest: unwind pool=%u configured=%u worker=%u\n",dmaPool.allocation!=0,configured,workerRunning);
    if(testFailure) { [[[self deviceDescription] configTable] freeString:testFailure];testFailure=0; }
#endif
    closing=YES;
    [self disableAllInterrupts];[stateLock lock];if(configured) { safe=[self resetDevice];if(safe)[self setPCIConfigData:originalCommand atRegister:4]; }
    [stateLock unlock];
    for(i=0;workerRunning && i<2000;i++)IOSleep(1);
    if(workerRunning)IOPanic("VirtioConsole: worker cannot stop safely");
    result=[super free];
    if(safe && savedPool.allocation)IOFreeLow(savedPool.allocation,savedPool.allocated);
    if(safe && savedExtra.allocation)IOFreeLow(savedExtra.allocation,savedExtra.allocated);
    [savedLock free];
#ifdef VIRTIO_CONSOLE_TESTING
    IOLog("VirtioConsoleTest: unwind complete safe=%u pool_freed=%u\n",safe,safe && savedPool.allocation!=0);
#endif
    return result;
}
@end
kern_server_t VirtioConsole_instance;
@interface VirtioConsoleKernelServerInstance : Object
@end
@implementation VirtioConsoleKernelServerInstance
+ (kern_server_t *)kernelServerInstance { return &VirtioConsole_instance; }
@end
@interface VirtioConsoleVersion : IODevice
@end
@implementation VirtioConsoleVersion
+ (int)driverKitVersionForVirtioConsole { return IO_DRIVERKIT_VERSION; }
@end
