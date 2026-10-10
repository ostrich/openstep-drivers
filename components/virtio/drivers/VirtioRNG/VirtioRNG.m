/* Experimental OPENSTEP 4.2 virtio-rng driver. Copyright 2026. MIT license.
 * Legacy PCI, one direct descriptor per read; no credited-entropy integration. */
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
#include <string.h>
#include "../../src/split-queue.h"
#include "../../src/legacy-pci.h"
#include "../../src/legacy-transport.h"
#include "../../src/native-dma.h"
/* Acknowledge the level-triggered device in interrupt context before deferring.
 * No allocation, Objective-C calls, sleeping or queue consumption here. */
struct RNGInterruptState { unsigned short port; volatile unsigned pending; };
static void rngInterrupt(void *identity,void *state,unsigned argument)
{
    struct RNGInterruptState *irq=(struct RNGInterruptState *)argument;
    unsigned pending=rd8(irq->port+VT_ISR);
    if(pending) {
        irq->pending |= pending;
        IOSendInterrupt(identity,state,IO_DEVICE_INTERRUPT_MSG);
    } else IOEnableInterrupt(identity);
}
static unsigned takePending(struct RNGInterruptState *irq)
{
    unsigned value;
    __asm__ volatile("xchgl %%eax,%1" : "=a"(value),"=m"(irq->pending) : "0"(0),"m"(irq->pending) : "memory");
    return value;
}
@interface VirtioRNG : IODirectDevice
{
    unsigned short port;
    unsigned irq,originalCommand;
    BOOL configured,online,finished;
    volatile BOOL closing,workerRunning;
#ifdef VIRTIO_RNG_TESTING
    const char *testFailure;
    BOOL testFaultsEnabled;
#endif
    id requestLock,stateLock;
    struct DMARegion ring,buffer;
    struct vq queue;
    struct RNGInterruptState irqState;
    unsigned completedLength,requests,completions,interrupts,strays,errors,resets;
    IOReturn completionError;
}
- (BOOL)resetDevice;
- (BOOL)setupQueue;
- serviceThread;
@end
static void rngThread(void *argument)
{
    [(VirtioRNG *)argument serviceThread];
    IOExitThread();
}
@implementation VirtioRNG
+ (BOOL)probe:description
{
    IOPCIConfigSpace pci;
    IORange ports;
    unsigned interrupt;
    id dev;
    if([self getPCIConfigSpace:&pci withDeviceDescription:description]!=IO_R_SUCCESS || pci.VendorID!=0x1af4 || pci.DeviceID!=0x1005)return NO;
    if(!(pci.BaseAddress[0]&1) || (pci.BaseAddress[0]&~3U)>0xffe0)return NO;
    interrupt=pci.InterruptLine;
    if(interrupt<3 || interrupt>15)return NO;
    ports.start=pci.BaseAddress[0]&~3U;ports.size=32;
    if([description setPortRangeList:&ports num:1]!=IO_R_SUCCESS || [description setInterruptList:&interrupt num:1]!=IO_R_SUCCESS)return NO;
    dev=[self alloc];return [dev initFromDeviceDescription:description]!=nil;
}
- initFromDeviceDescription:description
{
    IOPCIConfigSpace pci;
    unsigned bytes,n;
    if(![super initFromDeviceDescription:description])return [super free];
#ifdef VIRTIO_RNG_TESTING
    testFailure=[[description configTable] valueForStringKey:"VirtioRNG Test Failure"];
    testFaultsEnabled=YES;
#endif
    requestLock=[NXLock new];stateLock=[NXLock new];
    if(!requestLock || !stateLock)goto fail;
    if([self getPCIConfigSpace:&pci]!=IO_R_SUCCESS)goto fail;
    port=pci.BaseAddress[0]&~3U;irq=pci.InterruptLine;originalCommand=pci.Command;
    irqState.port=port;
    /* DWORD config writes must not accidentally clear write-one-to-clear status. */
    if([self setPCIConfigData:originalCommand|5 atRegister:4]!=IO_R_SUCCESS)goto fail;
    configured=YES;
    if(![self resetDevice])goto fail;
    wr16(port+VT_QUEUE_SELECT,0);n=rd16(port+VT_QUEUE_SIZE);bytes=vq_bytes(n);
    if(!bytes || !dma_alloc(&ring,bytes))goto fail;
#ifdef VIRTIO_RNG_TESTING
    if(testFailure && !strcmp(testFailure,"Ring"))goto fail;
#endif
    if(!dma_alloc(&buffer,4096))goto fail;
#ifdef VIRTIO_RNG_TESTING
    if(testFailure && !strcmp(testFailure,"Buffer"))goto fail;
#endif
    if([self attachInterruptPort]!=IO_R_SUCCESS)goto fail;
    workerRunning=YES;
    if(!IOForkThread(rngThread,self)) { workerRunning=NO;goto fail; }
    if([self enableAllInterrupts]!=IO_R_SUCCESS)goto fail;
#ifdef VIRTIO_RNG_TESTING
    if(testFailure && !strcmp(testFailure,"Thread"))goto fail;
#endif
    if(![self setupQueue])goto fail;
    [self setName:"VirtioRNG0"];[self registerDevice];
    IOLog("VirtioRNG: ready, queue %u, IRQ %u\n",n,irq);
    return self;
fail:
    IOLog("VirtioRNG: initialization failed\n");return [self free];
}
- (BOOL)resetDevice
{
    online=NO;
    if(vt_legacy_reset(port,IODelay)) { takePending(&irqState);resets++;return YES; }
    IOLog("VirtioRNG: device reset timed out; DMA memory retained\n");return NO;
}
- (BOOL)setupQueue
{
    unsigned n;
    if(!vt_legacy_begin(port,0))return NO;
    wr16(port+VT_QUEUE_SELECT,0);
    n=rd16(port+VT_QUEUE_SIZE);
    if(vq_init(&queue,ring.address,ring.size,n))return NO;
    if(!vt_legacy_queue(port,0,ring.physical,n))return NO;
    online=vt_legacy_ready(port);return online;
}
/* Own the worker so constructor failure cannot race IODirectDevice's
 * asynchronous free. Never use the inherited startIOThread entry point. */
- serviceThread
{
    int message;
    while(!closing) {
        if([self waitForInterrupt:&message]!=IO_R_SUCCESS) {
            if(!closing) {
                [stateLock lock];completionError=IO_R_IPC_FAILURE;finished=YES;errors++;
                [self resetDevice];[stateLock unlock];
                IOLog("VirtioRNG: interrupt worker receive failed\n");
            }
            break;
        }
        if(closing)break;
        if(message==IO_DEVICE_INTERRUPT_MSG)[self interruptOccurred];
    }
    workerRunning=NO;return self;
}
- (BOOL)getHandler:(IOInterruptHandler *)handler level:(unsigned *)level
          argument:(unsigned *)argument forInterrupt:(unsigned)local
{
    if(local)return NO;
    *handler=rngInterrupt;*level=3;*argument=(unsigned)&irqState;return YES;
}
- (void)interruptOccurred
{
    unsigned pending,id,length;
    int result;
    [stateLock lock];pending=takePending(&irqState);
    if(pending&1) {
        interrupts++;
#ifdef VIRTIO_RNG_TESTING
        if(testFaultsEnabled && testFailure && !strcmp(testFailure,"Completion")) {
            volatile struct vq_used *used=(volatile struct vq_used *)(queue.ring+queue.used_offset+4);
            used[queue.consumed&(queue.n-1)].id=queue.n;
        }
#endif
        result=vq_complete(&queue,&id,&length);
        if(result==1) { completedLength=length;completionError=IO_R_SUCCESS;completions++;finished=YES; }
        else if(result<0) { completionError=IO_R_IO;errors++;finished=YES;[self resetDevice]; }
    } else strays++;
    [stateLock unlock];
    if(!closing)[self enableAllInterrupts];
}
- (IOReturn)getCharValues:(unsigned char *)data forParameter:(IOParameterName)name count:(unsigned *)count
{
    unsigned length,i;
    ns_time_t now,deadline;
    BOOL gotCompletion=NO;
    IOReturn result;
    if(strcmp(name,"VirtioRNGRead"))return [super getCharValues:data forParameter:name count:count];
    length=*count;*count=0;if(!length || length>256)return IO_R_INVALID_ARG;
    [requestLock lock];[stateLock lock];
    if(closing || !online) { [stateLock unlock];[requestLock unlock];return IO_R_NOT_READY; }
    finished=NO;completedLength=0;completionError=IO_R_NOT_READY;
    if(vq_submit(&queue,buffer.physical,0,length,1)<0) { [stateLock unlock];[requestLock unlock];return IO_R_BUSY; }
    IOGetTimestamp(&now);deadline=now+2000000000ULL;
    requests++;wr16(port+VT_QUEUE_NOTIFY,0);[stateLock unlock];
    for(i=0;i<2000;i++) {
        [stateLock lock];if(finished) { gotCompletion=YES;break; } [stateLock unlock];
        IOGetTimestamp(&now);if(now>=deadline)break;IOSleep(1);
    }
    if(!gotCompletion) {
        [stateLock lock];errors++;result=IO_R_TIMEOUT;
        /* Retain allocations if reset fails; never reclaim in-flight memory. */
        [self resetDevice];
        IOLog("VirtioRNG: read timed out; device stopped\n");
    } else {
        result=completionError;
        if(result==IO_R_SUCCESS) { *count=completedLength;memcpy(data,buffer.address,completedLength); }
    }
    [stateLock unlock];[requestLock unlock];return result;
}
- (IOReturn)getIntValues:(unsigned *)values forParameter:(IOParameterName)name count:(unsigned *)count
{
    if(strcmp(name,"VirtioRNGStats"))return [super getIntValues:values forParameter:name count:count];
    if(*count<12)return IO_R_INVALID_ARG;
    [stateLock lock];values[0]=requests;values[1]=completions;values[2]=interrupts;values[3]=strays;values[4]=errors;values[5]=resets;values[6]=online;values[7]=ring.physical;values[8]=ring.size;values[9]=buffer.physical;values[10]=irq;values[11]=queue.n;[stateLock unlock];*count=12;return IO_R_SUCCESS;
}
- (IOReturn)setIntValues:(unsigned *)values forParameter:(IOParameterName)name count:(unsigned)count
{
    BOOL ok;
#ifdef VIRTIO_RNG_TESTING
    if(!strcmp(name,"VirtioRNGTestFaults")) {
        if(count!=1 || values[0]!=0)return IO_R_INVALID_ARG;
        [requestLock lock];[stateLock lock];testFaultsEnabled=NO;[stateLock unlock];[requestLock unlock];return IO_R_SUCCESS;
    }
#endif
    if(strcmp(name,"VirtioRNGReset"))return [super setIntValues:values forParameter:name count:count];
    if(count!=1 || values[0]!=1)return IO_R_INVALID_ARG;
    [requestLock lock];[stateLock lock];ok=!closing && workerRunning && [self resetDevice] && [self setupQueue];[stateLock unlock];[requestLock unlock];return ok?IO_R_SUCCESS:IO_R_IO;
}
- free
{
    struct DMARegion savedRing=ring,savedBuffer=buffer;
    id savedRequest=requestLock,savedState=stateLock,result;
    BOOL safe=YES;
    closing=YES;
#ifdef VIRTIO_RNG_TESTING
    IOLog("VirtioRNGTest: unwind ring %u buffer %u configured %u\n",ring.allocation!=0,buffer.allocation!=0,configured);
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
            if(now>=deadline)IOPanic("VirtioRNG: worker cannot stop safely");
            IOSleep(1);
        }
    }
    result=[super free]; /* Inherited worker slot is empty; owned worker exited. */
    if(safe) {
        if(savedRing.allocation)IOFreeLow(savedRing.allocation,savedRing.allocated);
        if(savedBuffer.allocation)IOFreeLow(savedBuffer.allocation,savedBuffer.allocated);
    }
    [savedRequest free];[savedState free];
#ifdef VIRTIO_RNG_TESTING
    IOLog("VirtioRNGTest: unwind complete, safe %u\n",safe);
#endif
    return result;
}
@end
kern_server_t VirtioRNG_instance;
@interface VirtioRNGKernelServerInstance : Object
@end
@implementation VirtioRNGKernelServerInstance
+ (kern_server_t *)kernelServerInstance { return &VirtioRNG_instance; }
@end
@interface VirtioRNGVersion : IODevice
@end
@implementation VirtioRNGVersion
+ (int)driverKitVersionForVirtioRNG { return IO_DRIVERKIT_VERSION; }
@end
