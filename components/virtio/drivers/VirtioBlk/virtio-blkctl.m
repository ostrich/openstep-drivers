#import <driverkit/IODeviceMaster.h>
#include <stdio.h>
#include <string.h>
#include <libc.h>
int main(int argc,char **argv)
{
    id master;
    unsigned object,count,values[18];
    IOString name,kind;
    IOReturn result;
    int valid=argc==2 && (!strcmp(argv[1],"--stats") || !strcmp(argv[1],"--reset"));
#ifdef VIRTIO_BLK_TESTING
    int fault=argc==2 && (!strcmp(argv[1],"--test-completion") || !strcmp(argv[1],"--test-timeout") || !strcmp(argv[1],"--test-preflush"));
    valid=valid || fault;
#endif
    if(!valid) {
        fprintf(stderr,"Usage: virtio-blkctl --stats | --reset\n");return 2;
    }
    if(strcmp(argv[1],"--stats") && geteuid()!=0) {
        fprintf(stderr,"Reset requires root; unmount secondary disk filesystems first\n");return 1;
    }
    master=[IODeviceMaster new];if(!master)return 1;
    for(object=0;object<256;object++) {
        if([master lookUpByObjectNumber:object deviceKind:&kind deviceName:&name]!=IO_R_SUCCESS)continue;
        count=18;
        if([master getIntValues:values forParameter:"VirtioBlkStats" objectNumber:object count:&count]!=IO_R_SUCCESS || count!=18)continue;
#ifdef VIRTIO_BLK_TESTING
        if(fault) {
            values[0]=!strcmp(argv[1],"--test-completion")?1:(!strcmp(argv[1],"--test-timeout")?2:3);
            result=[master setIntValues:values forParameter:"VirtioBlkTestNextFault" objectNumber:object count:1];
            [master free];return result?1:0;
        }
#endif
        if(!strcmp(argv[1],"--reset")) {
            values[0]=1;
            result=[master setIntValues:values forParameter:"VirtioBlkReset" objectNumber:object count:1];
            [master free];return result?1:0;
        }
        printf("controller=%s requests=%u completions=%u interrupts=%u stray=%u errors=%u resets=%u online=%u irq=%u queue=%u available=%u consumed=%u sectors=%u features=%x vm_page=%u outstanding=%u\n",
            name,values[0],values[1],values[2],values[3],values[4],values[5],values[6],values[10],values[11],values[12],values[13],values[14],values[15],values[16],values[17]);
        [master free];return 0;
    }
    [master free];fprintf(stderr,"VirtioBlk not found\n");return 1;
}
