/* See LICENSE. Read-only module status. */
#import <driverkit/IODeviceMaster.h>
#include <stdio.h>
#include <string.h>
#include <libc.h>
int main(int argc, char **argv)
{
    id master;
    unsigned object, count, values[4];
    IOString name, kind;
    if (argc != 2 || strcmp(argv[1], "--status")) {
        fprintf(stderr, "Usage: kernel-mapping-fixctl --status\n"); return 2;
    }
    master = [IODeviceMaster new];
    if (!master)
        return 1;
    for (object = 0; object < 256; object++) {
        if ([master lookUpByObjectNumber:object
                              deviceKind:&kind
                              deviceName:&name] != IO_R_SUCCESS)
            continue;
        count = 4;
        if ([master getIntValues:values
                    forParameter:"KernelMappingFixStatus"
                    objectNumber:object
                           count:&count] != IO_R_SUCCESS ||
            count != 4)
            continue;
        printf("result=%u image=%u cr0_before=%08x cr0_after=%08x\n",
               values[0], values[1], values[2], values[3]);
        [master free];
        return 0;
    }
    [master free];
    fprintf(stderr, "KernelMappingFix is not loaded; boot after enabling it.\n");
    return 1;
}
