/* OPENSTEP 4.2 virtio-blk development driver. MIT license.
 * IOSCSIController integrates the existing disk/partition/root layer.
 * Transport is virtio-blk legacy PCI, not virtio-scsi. Not release validated. */
#import <driverkit/IOSCSIController.h>
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
#include "../src/legacy-pci.h"
#include "../src/legacy-transport.h"
#include "../src/native-dma.h"
#include "../src/block-scsi.h"
#include "../src/block-mode.h"
#ifdef VIRTIO_BLK_MEMTRACE
#include "../src/block-flight-trace.h"
#define BF(event,a,b,c,d,e,f) vbFlight(event,a,b,c,d,e,f)
#else
#define BF(event,a,b,c,d,e,f)
#endif
/* Diagnostic-only logging is bounded: syslog writes themselves cause disk I/O.
 * Never print payload bytes or call IOLog from the hardware IRQ handler. */
#ifdef VIRTIO_BLK_VERBOSE
static volatile unsigned blkTraceErrors;
#ifndef VIRTIO_BLK_ERRORS_ONLY
static volatile unsigned blkTraceDetail;
#endif
static int blkTracePermit(volatile unsigned *counter,unsigned limit)
{
    unsigned previous=1;
    if(*counter>limit)return 0;
    __asm__ volatile("lock; xaddl %0,%1" : "=r"(previous),"=m"(*counter) : "0"(previous),"m"(*counter) : "memory","cc");
    if(previous==limit)IOLog("VirtioBlkTrace: log budget exhausted (%u records)\n",limit);
    return previous<limit;
}
#ifdef VIRTIO_BLK_ERRORS_ONLY
#define BT(args)
#else
#define BT(args) do { if(blkTracePermit(&blkTraceDetail,256))IOLog args; } while(0)
#endif
#define BE(args) do { if(blkTracePermit(&blkTraceErrors,512))IOLog args; } while(0)
#else
#define BT(args)
#define BE(args)
#endif
/* Acknowledge the level-triggered device in interrupt context before deferring.
 * No allocation, Objective-C calls, sleeping or queue consumption here. */
struct BlkInterruptState { unsigned short port; volatile unsigned pending; };
static void blkInterrupt(void *identity,void *state,unsigned argument)
{
    struct BlkInterruptState *irq=(struct BlkInterruptState *)argument;
    unsigned pending=rd8(irq->port+VT_ISR);
    if(pending) {
        irq->pending |= pending;
        IOSendInterrupt(identity,state,IO_DEVICE_INTERRUPT_MSG);
    } else IOEnableInterrupt(identity);
}
static unsigned takePending(struct BlkInterruptState *irq)
{
    unsigned value;
    __asm__ volatile("xchgl %%eax,%1" : "=a"(value),"=m"(irq->pending) : "0"(0),"m"(irq->pending) : "memory");
    return value;
}
@interface VirtioBlk : IOSCSIController
{
    unsigned short port;
    unsigned irq,originalCommand;
    BOOL configured,online,finished,stopped,writeFaulted;
    volatile BOOL closing,workerRunning;
#ifdef VIRTIO_BLK_TESTING
    const char *testFailure;
    BOOL testFaultsEnabled;
    unsigned testNextFault;
#endif
    id requestLock,stateLock,completionLock;
    struct DMARegion ring,buffer,extraBuffer;
    struct vq queue;
    struct BlkInterruptState irqState;
    unsigned capacity,features,cylinders,heads,sectors,vmPageBytes;
    unsigned char sense[18];
    ns_time_t commandDeadline;
    unsigned completedLength,requests,completions,interrupts,strays,errors,resets;
    unsigned queuedType;
    IOReturn completionError;
}
- (BOOL)resetDevice;
- (BOOL)setupQueue;
- (BOOL)copyPayload:(void *)address task:(vm_task_t)task bytes:(unsigned)bytes toClient:(BOOL)toClient;
- serviceThread;
@end
static void blkThread(void *argument)
{
    [(VirtioBlk *)argument serviceThread];
    IOExitThread();
}
@implementation VirtioBlk
+ (BOOL)probe:description
{
    IOPCIConfigSpace pci;
    IORange ports;
    unsigned interrupt;
    id dev;
    if([self getPCIConfigSpace:&pci withDeviceDescription:description]!=IO_R_SUCCESS || pci.VendorID!=0x1af4 || pci.DeviceID!=0x1001)return NO;
    if(!(pci.BaseAddress[0]&1) || (pci.BaseAddress[0]&~3U)>0xffc0)return NO;
    interrupt=pci.InterruptLine;
    if(interrupt<3 || interrupt>15)return NO;
    ports.start=pci.BaseAddress[0]&~3U;ports.size=64;
    if([description setPortRangeList:&ports num:1]!=IO_R_SUCCESS || [description setInterruptList:&interrupt num:1]!=IO_R_SUCCESS)return NO;
    dev=[self alloc];return [dev initFromDeviceDescription:description]!=nil;
}
- initFromDeviceDescription:description
{
    IOPCIConfigSpace pci;
    unsigned bytes,n;
    BT(("VirtioBlkTrace: init detail_limit=256 error_limit=512\n"));
    requestLock=[NXLock new];stateLock=[NXLock new];
    completionLock=[[NXConditionLock alloc] initWith:0];
    if(!requestLock || !stateLock || !completionLock)return [self free];
    if(![super initFromDeviceDescription:description])return [self free];
    /* Documented kernel interface: avoid Mach user-API EXTERNAL stubs,
     * which are not available to the original early boot-driver linker. */
    vmPageBytes=PAGE_SIZE;
    if(vmPageBytes<4096 || vmPageBytes>65536 || (vmPageBytes&(vmPageBytes-1))) {
        IOLog("VirtioBlk: invalid VM page size %u\n",vmPageBytes);return [self free];
    }
#ifdef VIRTIO_BLK_TESTING
    testFailure=[[description configTable] valueForStringKey:"VirtioBlk Test Failure"];
    testFaultsEnabled=YES;
#endif

    if([self getPCIConfigSpace:&pci]!=IO_R_SUCCESS)goto fail;
    port=pci.BaseAddress[0]&~3U;irq=pci.InterruptLine;originalCommand=pci.Command;
    irqState.port=port;
    /* DWORD config writes must not accidentally clear write-one-to-clear status. */
    if([self setPCIConfigData:originalCommand|5 atRegister:4]!=IO_R_SUCCESS)goto fail;
    configured=YES;
    if(![self resetDevice])goto fail;
    wr16(port+VT_QUEUE_SELECT,0);n=rd16(port+VT_QUEUE_SIZE);bytes=vq_bytes(n);
    if(!bytes || !dma_alloc(&ring,bytes))goto fail;
#ifdef VIRTIO_BLK_TESTING
    if(testFailure && !strcmp(testFailure,"Ring"))goto fail;
#endif
    if(!dma_alloc(&buffer,36864))goto fail;
#ifdef VIRTIO_BLK_TESTING
    /* Exercise unwind with the original arena allocated but no extra arena. */
    if(testFailure && !strcmp(testFailure,"ExtraBuffer"))goto fail;
#endif
    if(!dma_alloc(&extraBuffer,32768))goto fail;
#ifdef VIRTIO_BLK_TESTING
    if(testFailure && !strcmp(testFailure,"Buffer"))goto fail;
#endif

    workerRunning=YES;
    if(!IOForkThread(blkThread,self)) { workerRunning=NO;goto fail; }
    if([self enableAllInterrupts]!=IO_R_SUCCESS)goto fail;
#ifdef VIRTIO_BLK_TESTING
    if(testFailure && !strcmp(testFailure,"Thread"))goto fail;
#endif
    if(![self setupQueue])goto fail;
    if(![self registerDevice])goto fail;
    IOLog("VirtioBlk: ready, controller %s, queue %u, IRQ %u\n",[self name],n,irq);
    return self;
fail:
    IOLog("VirtioBlk: initialization failed\n");return [self free];
}
- (BOOL)resetDevice
{
    BF(5,requests,completions,errors,resets,online,writeFaulted);
    BT(("VirtioBlkTrace: reset requests=%u outstanding=%u faulted=%u\n",requests,queue.outstanding,writeFaulted));
    online=NO;
    if(vt_legacy_reset(port,IODelay)) { takePending(&irqState);resets++;return YES; }
    IOLog("VirtioBlk: device reset timed out; DMA memory retained\n");return NO;
}
/* IOSCSIController calls startIOThread during super initialization. Attach
 * its port but defer our owned worker until BAR/locks/DMA are initialized. */
- (IOReturn)startIOThread { return [self attachInterruptPort]; }
- (BOOL)setupQueue
{
    unsigned n,lo,hi,lo2,hi2,i,offered=rd32(port+VT_HOST_FEATURES);
    if(!(offered&VB_F_FLUSH))return NO; /* durability must be expressible */
    features=offered&(VB_F_RO|VB_F_FLUSH|VB_F_GEOMETRY|VB_F_BLK_SIZE);
    if(!vt_legacy_begin(port,features))return NO;
    for(i=0;i<100;i++) {
        lo=rd32(port+20);hi=rd32(port+24);
        lo2=rd32(port+20);hi2=rd32(port+24);
        if(lo==lo2 && hi==hi2)break;
    }
    /* READ CAPACITY(10) and guest block APIs are 32-bit; reject rather than
     * silently truncate an unsupported capacity. */
    if(i==100 || hi || !lo || (capacity && capacity!=lo))return NO;
    if((features&VB_F_BLK_SIZE) && rd32(port+40)!=512) {
        IOLog("VirtioBlk: backend logical block size must be 512 bytes\n");return NO;
    }
    capacity=lo;
    if(features&VB_F_GEOMETRY) {
        cylinders=rd16(port+36);heads=rd8(port+38);sectors=rd8(port+39);
    } else { heads=4;sectors=64;cylinders=capacity/(heads*sectors); }
    if(!cylinders || !heads || !sectors)return NO;
    wr16(port+VT_QUEUE_SELECT,0);n=rd16(port+VT_QUEUE_SIZE);
    if(vq_init(&queue,ring.address,ring.size,n))return NO;
    if(!vt_legacy_queue(port,0,ring.physical,n))return NO;
    online=vt_legacy_ready(port);
    BT(("VirtioBlkTrace: setup online=%u sectors=%u features=%x ring=%x buffer=%x\n",online,capacity,features,ring.physical,buffer.physical));
    return online;
}
/* Own the worker so constructor failure cannot race IODirectDevice's
 * asynchronous free. Never use the inherited startIOThread entry point. */
- serviceThread
{
    msg_header_t message;
    msg_return_t result;
    ns_time_t now;
    while(!closing) {
        memset(&message,0,sizeof(message));message.msg_size=sizeof(message);
        message.msg_local_port=[self interruptPort];
        /* Same exported IPC primitive as IODirectDevice's waitForInterrupt,
         * with a bounded idle tick for command deadlines. Completion itself
         * wakes the submitter immediately, not on a sleep/timer boundary. */
        result=msg_receive(&message,RCV_TIMEOUT|RCV_LARGE,100);
        if(closing)break;
        if(result==RCV_SUCCESS) {
            if(message.msg_id==IO_DEVICE_INTERRUPT_MSG)[self interruptOccurred];
        } else if(result!=RCV_TIMED_OUT && result!=RCV_INTERRUPTED) {
            [stateLock lock];completionError=IO_R_IPC_FAILURE;finished=YES;errors++;
            if(queue.outstanding && queuedType!=VB_T_IN)writeFaulted=YES;
            [self resetDevice];
            [completionLock lock];[completionLock unlockWith:1];
            [stateLock unlock];
            IOLog("VirtioBlk: interrupt worker receive failed\n");break;
        }
        [stateLock lock];IOGetTimestamp(&now);
        if(queue.outstanding && !finished && now>=commandDeadline) {
            if(queuedType!=VB_T_IN)writeFaulted=YES;
            errors++;completionError=IO_R_TIMEOUT;finished=YES;[self resetDevice];
            [completionLock lock];[completionLock unlockWith:1];
            IOLog("VirtioBlk: request timed out; uncertain writes are not replayed\n");
        }
        [stateLock unlock];
    }
    workerRunning=NO;return self;
}
- (BOOL)getHandler:(IOInterruptHandler *)handler level:(unsigned *)level
          argument:(unsigned *)argument forInterrupt:(unsigned)local
{
    if(local)return NO;
    *handler=blkInterrupt;*level=3;*argument=(unsigned)&irqState;return YES;
}
- (void)interruptOccurred
{
    unsigned pending,id,length;
    int result;
    [stateLock lock];pending=takePending(&irqState);
    if(pending&1) {
        interrupts++;
#ifdef VIRTIO_BLK_TESTING
        if(testNextFault==1 || (testFaultsEnabled && testFailure && !strcmp(testFailure,"Completion"))) {
            volatile struct vq_used *used=(volatile struct vq_used *)(queue.ring+queue.used_offset+4);
            used[queue.consumed&(queue.n-1)].id=queue.n;
            testNextFault=0;
        }
#endif
        result=vq_complete(&queue,&id,&length);
        BF(3,requests,result,result==1?id:~0U,result==1?length:0,pending,queue.consumed);
        BT(("VirtioBlkTrace: completion request=%u queue_result=%d pending=%u\n",requests,result,pending));
        if(result==1) { completedLength=length;completionError=IO_R_SUCCESS;completions++;finished=YES; }
        else if(result<0) {
            if(queuedType!=VB_T_IN)writeFaulted=YES;
            completionError=IO_R_IO;errors++;finished=YES;[self resetDevice];
        }
    } else strays++;
    if(finished) { [completionLock lock];[completionLock unlockWith:1]; }
    [stateLock unlock];
    if(!closing)[self enableAllInterrupts];
}
/* Client pages are wired by the SCSI disk layer. Translate/map each page;
 * never treat another task's virtual address as an IOTask pointer. */
- (BOOL)copyClient:(void *)clientBuffer task:(vm_task_t)task
             local:(void *)local length:(unsigned)bytes toClient:(BOOL)toClient
{
    unsigned address=(unsigned)clientBuffer,physical,offset,n;
    vm_address_t mapped;IOReturn copyError;
    if(bytes && address>~0U-(bytes-1)) { BE(("VirtioBlkTrace: copy overflow va=%x bytes=%u task=%x direction=%u\n",address,bytes,(unsigned)task,toClient));return NO; }
    while(bytes) {
        offset=address&4095;n=4096-offset;if(n>bytes)n=bytes;
        copyError=IOPhysicalFromVirtual(task,address,&physical);
        BF(4,address,copyError==IO_R_SUCCESS?physical:0,n,(unsigned)task,toClient,copyError);
        if(copyError!=IO_R_SUCCESS) { BE(("VirtioBlkTrace: copy translation error=%d va=%x remaining=%u task=%x direction=%u\n",copyError,address,bytes,(unsigned)task,toClient));return NO; }
        if((physical&4095)!=offset) { BE(("VirtioBlkTrace: copy offset mismatch va=%x physical=%x\n",address,physical));return NO; }
        /* Existing IOTask buffers already have the correct mapping. Avoid
         * allocating/unmapping an alias of kernel-owned wired memory. */
        if(task==IOVmTaskSelf()) {
            if(toClient)memcpy((void *)address,local,n);
            else memcpy(local,(void *)address,n);
            address+=n;local=(char *)local+n;bytes-=n;continue;
        }
        /* Mach VM allocation/alias granularity is not the x86 hardware page
         * size: OPENSTEP reports 8192. Walk 4096-byte translations, but map a
         * complete native VM page and preserve the physical byte offset. */
        mapped=0;
        copyError=IOMapPhysicalIntoIOTask(physical&~(vmPageBytes-1),vmPageBytes,&mapped);
        if(copyError!=IO_R_SUCCESS) { BE(("VirtioBlkTrace: copy map error=%d physical=%x page=%u\n",copyError,physical,vmPageBytes));return NO; }
        if(toClient)memcpy((void *)(mapped+(physical&(vmPageBytes-1))),local,n);
        else memcpy(local,(void *)(mapped+(physical&(vmPageBytes-1))),n);
        copyError=IOUnmapPhysicalFromIOTask(mapped,vmPageBytes);
        if(copyError!=IO_R_SUCCESS) { BE(("VirtioBlkTrace: copy unmap error=%d alias=%x page=%u\n",copyError,(unsigned)mapped,vmPageBytes));return NO; }
        address+=n;local=(char *)local+n;bytes-=n;
    }
    return YES;
}
- (BOOL)copyPayload:(void *)address task:(vm_task_t)task bytes:(unsigned)bytes toClient:(BOOL)toClient
{
    unsigned first=bytes>32768?32768:bytes;
    if(bytes>65536)return NO;
    if(![self copyClient:address task:task local:(char *)buffer.address+16 length:first toClient:toClient])return NO;
    if(bytes>32768 && ![self copyClient:(char *)address+32768 task:task local:extraBuffer.address length:bytes-32768 toClient:toClient])return NO;
    return YES;
}
/* Serialized by requestLock. Headers/status live outside the bounce data. */
- (sc_status_t)blockRequest:(unsigned)type sector:(unsigned)sector
                     bytes:(unsigned)bytes timeout:(unsigned)seconds
{
    struct vb_header *header=buffer.address;
    struct vq_buffer chain[4];unsigned count=0,i,length=0;
    volatile unsigned char *status=(unsigned char *)buffer.address+32784;
    ns_time_t now;sc_status_t result;
    [stateLock lock];
    if(closing || !online) { [stateLock unlock];return SR_IOST_HW; }
    IOGetTimestamp(&now);
    if(now>=commandDeadline) {
        if(type!=VB_T_IN) {
            /* A prior chunk/write may have completed before this flush or
             * next chunk could start. Fence upper-layer retries as well as
             * requests that time out while already outstanding. */
            writeFaulted=YES;errors++;[self resetDevice];
            IOLog("VirtioBlk: write deadline expired; administrative reset required\n");
        }
        [stateLock unlock];return SR_IOST_IOTO;
    }
    [completionLock lock];[completionLock unlockWith:0];
    header->type=type;header->reserved=0;header->sector_lo=sector;header->sector_hi=0;
    *status=255;finished=NO;completedLength=0;completionError=IO_R_NOT_READY;queuedType=type;
    chain[count].lo=buffer.physical;chain[count].hi=0;
    chain[count].length=16;chain[count++].device_writes=0;
    if(bytes) {
        chain[count].lo=buffer.physical+16;chain[count].hi=0;
        chain[count].length=bytes>32768?32768:bytes;chain[count++].device_writes=type==VB_T_IN;
        if(bytes>32768) {
            chain[count].lo=extraBuffer.physical;chain[count].hi=0;
            chain[count].length=bytes-32768;chain[count++].device_writes=type==VB_T_IN;
        }
    }
    chain[count].lo=buffer.physical+32784;chain[count].hi=0;
    chain[count].length=1;chain[count++].device_writes=1;
    if(vq_submit_chain(&queue,chain,count)<0) { [stateLock unlock];return SR_IOST_HW; }
    requests++;
    BF(2,requests,type,sector,bytes,queue.available,queue.consumed);
    BT(("VirtioBlkTrace: submit request=%u type=%u sector=%u bytes=%u avail=%u used=%u\n",requests,type,sector,bytes,queue.available,queue.consumed));
    BT(("VirtioBlkTrace: deadline request=%u now=%x:%08x deadline=%x:%08x\n",requests,(unsigned)(now>>32),(unsigned)now,(unsigned)(commandDeadline>>32),(unsigned)commandDeadline));
#ifdef VIRTIO_BLK_TESTING
    if(testNextFault==2) {
        /* Deliberately leave a submitted request without a notification.
         * The real worker deadline must wake the blocked caller and reset. */
        testNextFault=0;commandDeadline=now+1000000000ULL;
    } else
#endif
    wr16(port+VT_QUEUE_NOTIFY,0);
    [stateLock unlock];
    [completionLock lockWhen:1];[completionLock unlock];
    [stateLock lock];
    if(completionError==IO_R_TIMEOUT)result=SR_IOST_IOTO;
    else if(completionError!=IO_R_SUCCESS)result=SR_IOST_HW;
    else {
        length=completedLength;
        BT(("VirtioBlkTrace: result request=%u type=%u used_length=%u status=%u\n",requests,type,length,(unsigned)*status));
        i=vb_completion_result(type,bytes,length,*status);
        if((int)i<0) {
            if(type!=VB_T_IN)writeFaulted=YES;
            errors++;[self resetDevice];result=SR_IOST_HW;
        }
        else if(i) {
            result=SR_IOST_GOOD;
#ifdef VIRTIO_BLK_TESTING
            if(type==VB_T_OUT && testNextFault==3) {
                testNextFault=0;IOGetTimestamp(&now);commandDeadline=now;
            }
#endif
        }
        else {
            errors++;
            if(type!=VB_T_IN) {
                /* SCSIDisk retries SR_IOST_HW. A failed write/flush may
                 * already have changed media: fence subsequent commands,
                 * including automatic bus reset, until explicit recovery. */
                writeFaulted=YES;[self resetDevice];
                IOLog("VirtioBlk: write/flush failed; administrative reset required\n");
            }
            result=SR_IOST_HW;
        }
    }
    [stateLock unlock];return result;
}
- (int)numberOfTargets { return 1; }
- (unsigned)maxTransfer { return 65536; }
- (sc_status_t)resetSCSIBus
{
    BOOL ok;
    [requestLock lock];[stateLock lock];
    ok=!closing && !writeFaulted && workerRunning && [self resetDevice] && [self setupQueue];
    [stateLock unlock];[requestLock unlock];return ok?SR_IOST_GOOD:SR_IOST_HW;
}
- (sc_status_t)setSenseFor:(IOSCSIRequest *)r key:(unsigned)key asc:(unsigned)asc
{
    memset(sense,0,sizeof(sense));sense[0]=0x70;sense[2]=key;sense[7]=10;sense[12]=asc;
    memset(&r->senseData,0,sizeof(r->senseData));
    memcpy(&r->senseData,sense,sizeof(sense)<sizeof(r->senseData)?sizeof(sense):sizeof(r->senseData));
    r->scsiStatus=STAT_CHECK;return SR_IOST_CHKSV;
}
- (sc_status_t)executeRequest:(IOSCSIRequest *)r buffer:(void *)data client:(vm_task_t)client
{
    unsigned char *cdb=(unsigned char *)&r->cdb,response[96];
    struct vb_rw_command command;unsigned size=0,limit,asc,op=cdb[0],offset,n,seconds;
    ns_time_t started,ended;
    sc_status_t result=SR_IOST_GOOD;
    r->bytesTransferred=0;r->scsiStatus=STAT_GOOD;r->totalTime=0;r->latentTime=0;
    [requestLock lock];
    BF(1,op,r->target,r->lun,r->maxTransfer,(unsigned)data,(unsigned)client);
    BT(("VirtioBlkTrace: begin request=%x op=%x cdb_length=%u target=%u lun=%u extent=%d read=%u task=%x\n",(unsigned)r,op,r->cdbLength,r->target,r->lun,r->maxTransfer,r->read,(unsigned)client));
    IOGetTimestamp(&started);
    seconds=r->timeoutLength>0?r->timeoutLength:30;if(seconds>120)seconds=120;
    commandDeadline=started+(ns_time_t)seconds*1000000000ULL;
    if(r->target || r->lun) { result=SR_IOST_SELTO;goto finish; }
    if(r->maxTransfer<0) { result=SR_IOST_BCOUNT;goto finish; }
    if(!online || closing) { result=SR_IOST_HW;goto finish; }
    memset(response,0,sizeof(response));
    switch(op) {
    case 0x08:case 0x0a:case 0x28:case 0x2a:
        asc=vb_decode_rw(cdb,r->cdbLength?r->cdbLength:(op==8 || op==10?6:10),
                         r->maxTransfer,capacity,0,&command);
        if(asc) { result=[self setSenseFor:r key:5 asc:asc];break; }
        if((command.type==VB_T_IN)!=!!r->read) { result=[self setSenseFor:r key:5 asc:0x24];break; }
        if(command.type==VB_T_OUT && (features&VB_F_RO)) { result=[self setSenseFor:r key:7 asc:0x27];break; }
        if(stopped) { result=[self setSenseFor:r key:2 asc:4];break; }
        if(!command.bytes)break;
        if((unsigned)data>~0U-(command.bytes-1)) { result=SR_IOST_MEMF;break; }
        /* The kernel can pass boot-block/raw requests larger than maxTransfer.
         * Keep the DMA allocation bounded and service the validated CDB in
         * order. Account only completed, durable chunks; never retry writes. */
        for(offset=0;offset<command.bytes;offset+=n) {
            n=command.bytes-offset;if(n>65536)n=65536;
            if(command.type==VB_T_OUT && ![self copyPayload:(char *)data+offset task:client bytes:n toClient:NO]) { result=SR_IOST_MEMF;break; }
            result=[self blockRequest:command.type sector:command.sector+offset/512 bytes:n timeout:seconds];
            if(result!=SR_IOST_GOOD)break;
            if(command.type==VB_T_OUT)result=[self blockRequest:VB_T_FLUSH sector:0 bytes:0 timeout:seconds];
            else if(![self copyPayload:(char *)data+offset task:client bytes:n toClient:YES])result=SR_IOST_MEMF;
            if(result!=SR_IOST_GOOD)break;
            r->bytesTransferred+=n;
        }
        if(command.type==VB_T_OUT && result!=SR_IOST_GOOD && r->bytesTransferred) {
            [stateLock lock];
            if(online) {
                writeFaulted=YES;errors++;[self resetDevice];
                IOLog("VirtioBlk: partial write failed; administrative reset required\n");
            }
            [stateLock unlock];
        }
        break;
    case 0x00: /* TEST UNIT READY, fixed nonremovable media */
        if(stopped)result=[self setSenseFor:r key:2 asc:4];
        break;
    case 0x12: /* standard INQUIRY; no fabricated optional features */
        if(cdb[1] || cdb[2]) { result=[self setSenseFor:r key:5 asc:0x24];break; }
        response[2]=2;response[3]=2;response[4]=31;
        memcpy(response+8,"VIRTIO  ",8);memcpy(response+16,"Block Disk      ",16);memcpy(response+32,"0001",4);
        size=36;if(size>cdb[4])size=cdb[4];break;
    case 0x25: /* READ CAPACITY(10), 512-byte logical blocks */
        if(cdb[1] || cdb[2] || cdb[3] || cdb[4] || cdb[5] || cdb[8]) { result=[self setSenseFor:r key:5 asc:0x24];break; }
        limit=capacity-1;response[0]=limit>>24;response[1]=limit>>16;response[2]=limit>>8;response[3]=limit;
        response[6]=2;size=8;break;
    case 0x03: /* REQUEST SENSE; saved sense returned then cleared */
        memcpy(response,sense,sizeof(sense));size=sizeof(sense);if(size>cdb[4])size=cdb[4];
        memset(sense,0,sizeof(sense));sense[0]=0x70;sense[7]=10;break;
    case 0x1a: /* MODE SENSE(6): logical geometry and durable writes */
        asc=vb_mode_sense(cdb,capacity,cylinders,heads,sectors,
                          !!(features&VB_F_RO),response,&size);
        if(asc) { result=[self setSenseFor:r key:5 asc:asc];size=0; }
        else if(size>cdb[4])size=cdb[4];
        break;
    case 0x1b: /* START STOP: stop flushes before changing readiness */
        if(cdb[1] || cdb[2] || cdb[3] || (cdb[4]&~1U) || cdb[5]) {
            result=[self setSenseFor:r key:5 asc:0x24];break;
        }
        if(cdb[4]&1)stopped=NO;
        else {
            result=[self blockRequest:VB_T_FLUSH sector:0 bytes:0 timeout:r->timeoutLength];
            if(result==SR_IOST_GOOD)stopped=YES;
        }
        break;
    case 0x35: /* SYNCHRONIZE CACHE; no IMMED or range variants yet */
        if(cdb[1] || cdb[2] || cdb[3] || cdb[4] || cdb[5] || cdb[6] || cdb[7] || cdb[8] || cdb[9]) { result=[self setSenseFor:r key:5 asc:0x24];break; }
        result=[self blockRequest:VB_T_FLUSH sector:0 bytes:0 timeout:r->timeoutLength];break;
    default:result=[self setSenseFor:r key:5 asc:0x20];break;
    }
    if(result==SR_IOST_GOOD && size) {
        if(!r->read)result=[self setSenseFor:r key:5 asc:0x24];
        else {
            if(size>(unsigned)r->maxTransfer)size=r->maxTransfer;
            if([self copyClient:data task:client local:response length:size toClient:YES])r->bytesTransferred=size;
            else result=SR_IOST_MEMF;
        }
    }
finish:
    BT(("VirtioBlkTrace: end request=%x op=%x driver_status=%d scsi_status=%u transferred=%u\n",(unsigned)r,op,result,r->scsiStatus,r->bytesTransferred));
    if(result!=SR_IOST_GOOD)BE(("VirtioBlkTrace: rejected request=%x op=%x target=%u lun=%u cdb_length=%u driver_status=%d scsi_status=%u transferred=%u online=%u faulted=%u\n",(unsigned)r,op,r->target,r->lun,r->cdbLength,result,r->scsiStatus,r->bytesTransferred,online,writeFaulted));
    if(result==SR_IOST_CHKSV)BE(("VirtioBlkTrace: sense key=%u asc=%u\n",(unsigned)sense[2],(unsigned)sense[12]));
    IOGetTimestamp(&ended);r->totalTime=ended-started;
    r->driverStatus=result;[requestLock unlock];return result;
}
- (IOReturn)getIntValues:(unsigned *)values forParameter:(IOParameterName)name count:(unsigned *)count
{
    if(strcmp(name,"VirtioBlkStats"))return [super getIntValues:values forParameter:name count:count];
    if(*count<18)return IO_R_INVALID_ARG;
    [stateLock lock];values[0]=requests;values[1]=completions;values[2]=interrupts;values[3]=strays;values[4]=errors;values[5]=resets;values[6]=online;values[7]=ring.physical;values[8]=ring.size;values[9]=buffer.physical;values[10]=irq;values[11]=queue.n;values[12]=queue.available;values[13]=queue.consumed;values[14]=capacity;values[15]=features;values[16]=vmPageBytes;values[17]=queue.outstanding;[stateLock unlock];*count=18;return IO_R_SUCCESS;
}
- (IOReturn)setIntValues:(unsigned *)values forParameter:(IOParameterName)name count:(unsigned)count
{
    BOOL ok;
#ifdef VIRTIO_BLK_TESTING
    if(!strcmp(name,"VirtioBlkTestNextFault")) {
        if(count!=1 || values[0]>3)return IO_R_INVALID_ARG;
        [requestLock lock];[stateLock lock];
        if(!online || !workerRunning || closing) {
            [stateLock unlock];[requestLock unlock];return IO_R_NOT_READY;
        }
        testNextFault=values[0];
        [stateLock unlock];[requestLock unlock];return IO_R_SUCCESS;
    }
    if(!strcmp(name,"VirtioBlkTestFaults")) {
        if(count!=1 || values[0]!=0)return IO_R_INVALID_ARG;
        [requestLock lock];[stateLock lock];testFaultsEnabled=NO;[stateLock unlock];[requestLock unlock];return IO_R_SUCCESS;
    }
#endif
    if(strcmp(name,"VirtioBlkReset"))return [super setIntValues:values forParameter:name count:count];
    if(count!=1 || values[0]!=1)return IO_R_INVALID_ARG;
    [requestLock lock];[stateLock lock];
    ok=!closing && workerRunning && [self resetDevice] && [self setupQueue];
    if(ok)writeFaulted=NO;
    [stateLock unlock];[requestLock unlock];return ok?IO_R_SUCCESS:IO_R_IO;
}
- free
{
    struct DMARegion savedRing=ring,savedBuffer=buffer,savedExtra=extraBuffer;
    id savedRequest=requestLock,savedState=stateLock,savedCompletion=completionLock,result;
    BOOL safe=YES;
    closing=YES;
    [stateLock lock];completionError=IO_R_NOT_READY;finished=YES;
    [completionLock lock];[completionLock unlockWith:1];[stateLock unlock];
    /* Any active submitter must finish before DMA or wait objects are freed. */
    [requestLock lock];
#ifdef VIRTIO_BLK_TESTING
    IOLog("VirtioBlkTest: unwind ring %u buffer %u configured %u\n",ring.allocation!=0,buffer.allocation!=0,configured);
    if(testFailure) {
        [[[self deviceDescription] configTable] freeString:testFailure];testFailure=0;
    }
#endif
    [self disableAllInterrupts];
    if(configured) {
        safe=[self resetDevice];
        if(safe)[self setPCIConfigData:originalCommand atRegister:4];
    }
    if(workerRunning) {
        msg_header_t message;
        ns_time_t now,deadline;
        memset(&message,0,sizeof(message));message.msg_simple=1;
        message.msg_size=sizeof(message);message.msg_type=MSG_TYPE_NORMAL;
        message.msg_remote_port=IOConvertPort([self interruptPort],IO_KernelIOTask,IO_Kernel);
        message.msg_id=IO_COMMAND_MSG;
        (void)msg_send_from_kernel(&message,SEND_TIMEOUT,1000);
        IOGetTimestamp(&now);deadline=now+2000000000ULL;
        while(workerRunning) {
            IOGetTimestamp(&now);
            if(now>=deadline)IOPanic("VirtioBlk: worker cannot stop safely");
            IOSleep(1);
        }
    }
    result=[super free]; /* Inherited worker slot is empty; owned worker exited. */
    if(safe) {
        if(savedRing.allocation)IOFreeLow(savedRing.allocation,savedRing.allocated);
        if(savedBuffer.allocation)IOFreeLow(savedBuffer.allocation,savedBuffer.allocated);
        if(savedExtra.allocation)IOFreeLow(savedExtra.allocation,savedExtra.allocated);
    }
    [savedRequest unlock];[savedRequest free];[savedState free];[savedCompletion free];
#ifdef VIRTIO_BLK_TESTING
    IOLog("VirtioBlkTest: unwind complete, safe %u\n",safe);
#endif
    return result;
}
@end
kern_server_t VirtioBlk_instance;
@interface VirtioBlkKernelServerInstance : Object
@end
@implementation VirtioBlkKernelServerInstance
+ (kern_server_t *)kernelServerInstance { return &VirtioBlk_instance; }
@end
@interface VirtioBlkVersion : IODevice
@end
@implementation VirtioBlkVersion
+ (int)driverKitVersionForVirtioBlk { return IO_DRIVERKIT_VERSION; }
@end
