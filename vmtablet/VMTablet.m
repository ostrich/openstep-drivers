/* OPENSTEP 4.2 VMware backdoor absolute pointer prototype. */
#import <driverkit/IOEventSource.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/IODisplay.h>
#import <machkit/NXLock.h>
#import <objc/objc-runtime.h>
#import <kernserv/kern_server_types.h>

#ifdef VMTABLET_DEBUG
#define VTLog IOLog
#else
#define VTLog while (0) IOLog
#endif

#define VM_MAGIC 0x564d5868U
#define VM_PORT 0x5658U
#define VM_DATA 39
#define VM_STATUS 40
#define VM_COMMAND 41
#define VM_ENABLE 0x45414552U
#define VM_ABSOLUTE 0x53424152U
#define VM_DISABLE 0xf5U
#define VM_VERSION 0x3442554aU

typedef struct { unsigned a,b,c,d; } VMReply;
static VMReply vmcall(unsigned command, unsigned argument)
{
    VMReply r;
    r.a = VM_MAGIC; r.b = argument; r.c = command; r.d = VM_PORT;
    __asm__ volatile("inl %%dx,%%eax"
        : "=a" (r.a), "=b" (r.b), "=c" (r.c), "=d" (r.d)
        : "0" (r.a), "1" (r.b), "2" (r.c), "3" (r.d) : "memory");
    return r;
}

@interface VMTablet : IOEventSource
{
    volatile BOOL stopping;
    volatile BOOL running;
    unsigned packets;
    id detachedOwner;
    unsigned detachedGeneration;
    BOOL sawClosedEvents;
}
- poll;
- (IOReturn)relinquishOwnership:client;
- reconnect;
@end

static void tabletThread(void *arg)
{
    [(VMTablet *)arg poll];
    IOExitThread();
}

@implementation VMTablet
+ (IODeviceStyle)deviceStyle { return IO_PseudoDevice; }
+ (BOOL)probe:description
{
    VMReply r = vmcall(10, ~VM_MAGIC);
    VMTablet *device;
    if (r.b != VM_MAGIC || r.a == ~0U) {
        IOLog("VMTablet: VMware backdoor not detected\n");
        return NO;
    }
    vmcall(VM_COMMAND, VM_ENABLE);
    r = vmcall(VM_STATUS, 0);
    if ((r.a >> 16) || !(r.a & 0xffff)) return NO;
    r = vmcall(VM_DATA, 1);
    if (r.a != VM_VERSION) {
        vmcall(VM_COMMAND, VM_DISABLE);
        return NO;
    }
    device = [[self alloc] init];
    if (!device) { vmcall(VM_COMMAND, VM_DISABLE); return NO; }
    [device setName:"VMTablet0"];
    [device setDeviceKind:"Pointing Device"];
    [device setLocation:"VMware backdoor"];
    if (![device registerDevice]) { [device free]; return NO; }
    [IOEventSource registerEventSource:device];
    vmcall(VM_COMMAND, VM_ABSOLUTE);
    device->running = YES;
    if (!IOForkThread(tabletThread, device)) {
        device->running = NO;
        [device free];
        return NO;
    }
    IOLog("VMTablet: absolute mode enabled, polling every 8 ms\n");
    return YES;
}
/* EventDriver removes every source from its list on evClose. The default
 * sources are reprobed on evOpen, but dynamically loaded sources are not.
 * Keep the persistent EventDriver singleton as a reconnect candidate only;
 * never deliver packets to it until registerEventSource restores ownership. */
- (IOReturn)relinquishOwnership:client
{
    IOReturn result = [super relinquishOwnership:client];
    if (result == IO_R_SUCCESS &&
        [client isKindOf:objc_getClass("EventDriver")]) {
        [[self ownerLock] lock];
        detachedOwner = client;
        detachedGeneration++;
        sawClosedEvents = NO;
        [[self ownerLock] unlock];
        {
#ifdef VMTABLET_DEBUG
                IOLog("VMTablet: event owner detached\n");
#endif
            }
    }
    return result;
}
- reconnect
{
    id client;
    unsigned generation;
    BOOL closed;
    IOReturn state;
    [[self ownerLock] lock];
    client = detachedOwner;
    generation = detachedGeneration;
    closed = sawClosedEvents;
    [[self ownerLock] unlock];
    /* Detachment starts while eventsOpen is still true. Observe the closed
     * state before accepting a subsequent open; otherwise registration can
     * race the list-draining loop in detachEventSources. */
    if (!client || stopping) return self;
    state = [client relinquishOwnershipRequest:self];
    if (state == IO_R_SUCCESS) {
        [[self ownerLock] lock];
        if (generation == detachedGeneration) sawClosedEvents = YES;
        [[self ownerLock] unlock];
    } else if (closed && state == IO_R_BUSY) {
        if ([IOEventSource registerEventSource:self]) {
            [[self ownerLock] lock];
            if (generation == detachedGeneration) detachedOwner = nil;
            [[self ownerLock] unlock];
            {
#ifdef VMTABLET_DEBUG
                IOLog("VMTablet: event owner reattached\n");
#endif
            }
        }
    }
    return self;
}
- poll
{
    while (!stopping) {
        unsigned n;
        VMReply status;
        [self reconnect];
        status = vmcall(VM_STATUS, 0);
        if (status.a >> 16) {
            IOLog("VMTablet: queue error, disabling\n");
            break;
        }
        /* Bound each batch so malformed input cannot monopolize IOTask. */
        n = (status.a & 0xffff) / 4;
        if (n > 256) n = 256;
        while (n--) {
            VMReply r = vmcall(VM_DATA, 4);
            id client;
            Bounds *bounds;
            Bounds displayBounds;
            Point p;
            int buttons = 0;
            if (r.a & 0x10000) continue;
            if (r.a & 0x20) buttons |= EV_LB;
            if (r.a & 0x10) buttons |= EV_RB;
            [[self ownerLock] lock];
            client = [self owner];
            if (packets < 12)
                {
#ifdef VMTABLET_DEBUG
                IOLog("VMTablet: owner %x workspace API %d packet %u,%u\n",
                    (unsigned)client, client ? [client respondsTo:@selector(workspaceBounds)] : 0, r.b, r.c);
#endif
            }
            if (client && [client respondsTo:@selector(workspaceBounds)]) {
                bounds = [(id<IOWorkspaceBounds>)client workspaceBounds];
                if (packets < 12 && bounds)
                    {
#ifdef VMTABLET_DEBUG
                IOLog("VMTablet: bounds %d,%d-%d,%d at %x\n",
                        bounds->minx, bounds->miny, bounds->maxx, bounds->maxy, (unsigned)bounds);
#endif
            }
                /* OPENSTEP 4.2 can report an empty workspace. Query the
                 * active framebuffer instead; this fallback is single-screen. */
                if (!bounds || bounds->maxx <= bounds->minx ||
                    bounds->maxy <= bounds->miny) {
                    id display = nil;
                    if (IOGetObjectForDeviceName("Display0", &display) == IO_R_SUCCESS) {
                        IODisplayInfo *info = [(IODisplay *)display displayInfo];
                        if (info && info->width > 0 && info->width < 32768 &&
                            info->height > 0 && info->height < 32768) {
                            displayBounds.minx = displayBounds.miny = 0;
                            displayBounds.maxx = info->width;
                            displayBounds.maxy = info->height;
                            bounds = &displayBounds;
                        }
                    }
                }
                if (bounds && bounds->maxx > bounds->minx &&
                    bounds->maxy > bounds->miny) {
                    p.x = bounds->minx + ((r.b & 0xffff) *
                        (bounds->maxx - bounds->minx - 1) + 32767) / 65535;
                    p.y = bounds->miny + ((r.c & 0xffff) *
                        (bounds->maxy - bounds->miny - 1) + 32767) / 65535;
                    [(id<IOEventSourceClient>)client absolutePointerEvent:buttons
                        at:&p inProximity:YES];
                    if (packets < 12)
                        {
#ifdef VMTABLET_DEBUG
                IOLog("VMTablet: raw %u,%u -> %d,%d buttons %d bounds %d,%d-%d,%d\n",
                            r.b, r.c, p.x, p.y, buttons, bounds->minx,
                            bounds->miny, bounds->maxx, bounds->maxy);
#endif
            }
                }
            }
            [[self ownerLock] unlock];
            packets++;
        }
        IOSleep(8);
    }
    vmcall(VM_COMMAND, VM_DISABLE);
    running = NO;
    return self;
}
- free
{
    stopping = YES;
    while (running) IOSleep(10);
    vmcall(VM_COMMAND, VM_DISABLE);
    return [super free];
}
@end

kern_server_t VMTablet_instance;
@interface VMTabletKernelServerInstance : Object
@end
@implementation VMTabletKernelServerInstance
+ (kern_server_t *)kernelServerInstance { return &VMTablet_instance; }
@end
@interface VMTabletVersion : IODevice
@end
@implementation VMTabletVersion
+ (int)driverKitVersionForVMTablet { return IO_DRIVERKIT_VERSION; }
@end
