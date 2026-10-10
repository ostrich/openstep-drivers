/* OPENSTEP 4.2 TCP-default tuner. MIT license.
 * Symbol-based linking only: no fixed addresses or kernel-file modification. */
#import <driverkit/IODevice.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IOConfigTable.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <kernserv/kern_server_types.h>
#include <string.h>
extern int tcp_sendspace;
extern int tcp_recvspace;
extern int splhigh(void);
extern int splx(int);
static BOOL claimed;
@interface TCPBuffers : IODevice
{
    int savedSend,savedReceive;
    BOOL applied,ownsClaim;
}
@end
@implementation TCPBuffers
+ (IODeviceStyle)deviceStyle { return IO_PseudoDevice; }
+ (BOOL)probe:description
{
    TCPBuffers *device;
    int level,previousSend,previousReceive;
    const char *apply=[[description configTable] valueForStringKey:"Apply TCP Defaults"];
    BOOL valid=!apply || !strcmp(apply,"Yes") || !strcmp(apply,"No");
    BOOL enable=apply && !strcmp(apply,"Yes");
    if(apply)[[description configTable] freeString:apply];
    if(!valid) { IOLog("TCPBuffers: invalid Apply TCP Defaults; unchanged\n");return NO; }
    level=splhigh();
    if(claimed) { splx(level);return NO; }
    previousSend=tcp_sendspace;previousReceive=tcp_recvspace;
    if(previousSend<1 || previousSend>32768 || previousReceive<1 || previousReceive>32768) {
        splx(level);IOLog("TCPBuffers: unsupported existing defaults; unchanged\n");return NO;
    }
    claimed=YES;splx(level);
    device=[[self alloc] init];
    if(!device) { level=splhigh();claimed=NO;splx(level);return NO; }
    device->ownsClaim=YES;
    device->savedSend=previousSend;device->savedReceive=previousReceive;
    [device setName:"TCPBuffers0"];[device setDeviceKind:"TCP Defaults"];
    if(![device registerDevice]) { [device free];return NO; }
    if(enable) {
        /* Short one-vCPU interrupt exclusion; Intel splnet is a no-op. No allocation,
         * registration, logging or blocking operation while raised. */
        level=splhigh();
        if(tcp_sendspace!=previousSend || tcp_recvspace!=previousReceive) {
            splx(level);[device free];IOLog("TCPBuffers: defaults changed during initialization; unchanged\n");return NO;
        }
        tcp_sendspace=32768;tcp_recvspace=32768;device->applied=YES;
        splx(level);
    }
    IOLog("TCPBuffers: defaults send %d receive %d%s\n",tcp_sendspace,tcp_recvspace,enable?" (applied)":" (read only)");
    return YES;
}
- (IOReturn)getIntValues:(unsigned *)values forParameter:(IOParameterName)name count:(unsigned *)count
{
    int level;
    if(strcmp(name,"TCPBufferDefaults"))return [super getIntValues:values forParameter:name count:count];
    if(*count<5)return IO_R_INVALID_ARG;
    level=splhigh();
    values[0]=tcp_sendspace;values[1]=tcp_recvspace;values[2]=savedSend;values[3]=savedReceive;values[4]=applied;splx(level);*count=5;return IO_R_SUCCESS;
}
- free
{
    int level=splhigh();
    /* Preserve another tuner's changes rather than blindly overwriting them. */
    if(applied && tcp_sendspace==32768 && tcp_recvspace==32768) {
        tcp_sendspace=savedSend;tcp_recvspace=savedReceive;
    }
    if(ownsClaim)claimed=NO;
    applied=NO;ownsClaim=NO;splx(level);
    return [super free];
}
@end
kern_server_t TCPBuffers_instance;
@interface TCPBuffersKernelServerInstance : Object
@end
@implementation TCPBuffersKernelServerInstance
+ (kern_server_t *)kernelServerInstance { return &TCPBuffers_instance; }
@end
@interface TCPBuffersVersion : IODevice
@end
@implementation TCPBuffersVersion
+ (int)driverKitVersionForTCPBuffers { return IO_DRIVERKIT_VERSION; }
@end
