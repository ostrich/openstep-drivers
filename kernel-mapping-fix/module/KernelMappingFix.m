/* One-shot OPENSTEP Intel kernel patch. See LICENSE. */
#import <driverkit/IODevice.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IOConfigTable.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <kernserv/kern_server_types.h>
#include <mach/machine.h>
#include <string.h>
#include "sha256.h"
#include "patch-inputs.h"

extern void pmap_remove(void *, unsigned, unsigned);
extern void *kernel_pmap;
extern struct machine_info machine_info;
static unsigned applyResult, savedCR0, restoredCR0;
static BOOL claimed;

/* These helpers neither allocate nor call the VM subsystem. */
static unsigned irq_save(void)
{
    unsigned f;
    asm volatile("pushfl; popl %0; cli" : "=r"(f) : : "memory", "cc");
    return f;
}
static void irq_restore(unsigned f)
{
    asm volatile("pushl %0; popfl" : : "r"(f) : "memory", "cc");
}
static unsigned read_cr0(void)
{
    unsigned v;
    asm volatile("movl %%cr0,%0" : "=r"(v));
    return v;
}
static void write_cr0(unsigned v)
{
    asm volatile("movl %0,%%cr0" : : "r"(v) : "memory");
}
static void flush(void)
{
    unsigned v;
    asm volatile("movl %%cr3,%0; movl %0,%%cr3" : "=&r"(v) : : "memory");
}
static void put_bytes(unsigned address, const unsigned char *bytes, unsigned n)
{
    volatile unsigned char *p = (volatile unsigned char *)address;
    unsigned i;
    for (i = 0; i < n; i++) p[i] = bytes ? bytes[i] : 0;
}
/* 0 unsupported/mixed, 1 exact original, 2 exact fixed image. */
static unsigned image_state(void)
{
    struct sha_context ctx;
    char hash[65];
    unsigned i, original = 1, fixed = 1;
    if ((unsigned)&pmap_remove != 0x18fa44U ||
        (unsigned)&kernel_pmap != 0x1f63f0U ||
        machine_info.avail_cpus != 1 || machine_info.max_cpus != 1) return 0;
    sha_init(&ctx);
    if (sha_update(&ctx, (const unsigned char *)PMAP_START, PMAP_LENGTH)) return 0;
    sha_finish(&ctx, hash);
    original = !strcmp(hash, original_pmap_hash);
    fixed = !strcmp(hash, patched_pmap_hash);
    for (i = 0; i < sizeof(sites) / sizeof(sites[0]); i++) {
        if (memcmp((const void *)sites[i].address, sites[i].original, 5)) original = 0;
        if (memcmp((const void *)sites[i].address, sites[i].patched, 5)) fixed = 0;
    }
    for (i = 0; i < sizeof(payload); i++) {
        unsigned char v = ((const volatile unsigned char *)PAYLOAD_ADDRESS)[i];
        if (v) original = 0;
        if (v != payload[i]) fixed = 0;
    }
    return original ? 1 : fixed ? 2 : 0;
}
static unsigned apply_fix(void)
{
    unsigned flags, state, cr0, i, result;
    flags = irq_save();
    state = image_state();
    if (state != 1) { irq_restore(flags); return state == 2 ? 2 : 0; }
    cr0 = read_cr0();
    savedCR0 = cr0;
    write_cr0(cr0 & ~0x10000U);
    /* Publish complete standalone code before any branch can target it. */
    put_bytes(PAYLOAD_ADDRESS, payload, sizeof(payload));
    for (i = 0; i < sizeof(sites) / sizeof(sites[0]); i++)
        put_bytes(sites[i].address, sites[i].patched, 5);
    write_cr0(cr0);
    flush();
    result = image_state() == 2 ? 1 : 0;
    if (!result) {
        /* All preconditions matched before publication. Restore the exact
         * original bytes if the post-write verification unexpectedly fails. */
        write_cr0(cr0 & ~0x10000U);
        for (i = 0; i < sizeof(sites) / sizeof(sites[0]); i++)
            put_bytes(sites[i].address, sites[i].original, 5);
        put_bytes(PAYLOAD_ADDRESS, 0, sizeof(payload));
        write_cr0(cr0);
        flush();
    }
    restoredCR0 = read_cr0();
    irq_restore(flags);
    return result;
}

@interface KernelMappingFix : IODevice {
    BOOL ownsClaim;
}
@end
@implementation KernelMappingFix
+ (IODeviceStyle)deviceStyle { return IO_PseudoDevice; }
+ (BOOL)probe:description
{
    KernelMappingFix *device;
    const char *option;
    BOOL enable;
    unsigned flags, state;
    option = [[description configTable] valueForStringKey:"Apply Mapping Fix"];
    enable = option && !strcmp(option, "Yes");
    if (option && strcmp(option, "Yes") && strcmp(option, "No")) {
        [[description configTable] freeString:option];
        IOLog("KernelMappingFix: invalid configuration; unchanged\n"); return NO;
    }
    if (option) [[description configTable] freeString:option];
    flags = irq_save();
    if (claimed) { irq_restore(flags); return NO; }
    state = image_state();
    irq_restore(flags);
    if (!state) { IOLog("KernelMappingFix: unsupported kernel or conflicting code; unchanged\n"); return NO; }
    device = [[self alloc] init];
    if (!device) return NO;
    [device setName:"KernelMappingFix0"];
    [device setDeviceKind:"Kernel Mapping Fix"];
    flags = irq_save();
    if (claimed) { irq_restore(flags); [device free]; return NO; }
    claimed = YES; device->ownsClaim = YES; irq_restore(flags);
    if (![device registerDevice]) { [device free]; return NO; }
    applyResult = enable ? apply_fix() : 3;
    if (!applyResult) {
        IOLog("KernelMappingFix: application refused or verification failed\n");
        [device free]; return NO;
    }
    IOLog("KernelMappingFix: %s\n", applyResult == 1 ? "applied" :
          applyResult == 2 ? "already applied" : "read only");
    return YES;
}
- (IOReturn)getIntValues:(unsigned *)values forParameter:(IOParameterName)name count:(unsigned *)count
{
    unsigned flags;
    if (strcmp(name, "KernelMappingFixStatus"))
        return [super getIntValues:values forParameter:name count:count];
    if (*count < 4) return IO_R_INVALID_ARG;
    flags = irq_save();
    values[0] = applyResult; values[1] = image_state();
    values[2] = savedCR0; values[3] = restoredCR0;
    irq_restore(flags); *count = 4; return IO_R_SUCCESS;
}
- free
{
    unsigned flags = irq_save();
    if (ownsClaim) { claimed = NO; ownsClaim = NO; }
    irq_restore(flags);
    /* Standalone stubs have no references to this module. Never undo live. */
    return [super free];
}
@end
kern_server_t KernelMappingFix_instance;
@interface KernelMappingFixKernelServerInstance : Object
@end
@implementation KernelMappingFixKernelServerInstance
+ (kern_server_t *)kernelServerInstance { return &KernelMappingFix_instance; }
@end
@interface KernelMappingFixVersion : IODevice
@end
@implementation KernelMappingFixVersion
+ (int)driverKitVersionForKernelMappingFix { return IO_DRIVERKIT_VERSION; }
@end
