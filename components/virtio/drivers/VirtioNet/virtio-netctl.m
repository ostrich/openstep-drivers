#import <driverkit/IODeviceMaster.h>
#include <stdio.h>
#include <string.h>
int main(int argc,char **argv)
{
    id master;
    unsigned object,count,values[12];
    IOString name,kind;
    IOReturn result;
    int valid=argc==2 && (!strcmp(argv[1],"--stats") || !strcmp(argv[1],"--reset"));
#ifdef VIRTIO_NET_TESTING
    if(argc==2 && !strcmp(argv[1],"--clear-test-fault"))valid=1;
#endif
    if(!valid) {
        fprintf(stderr,"Usage: virtio-netctl --stats | --reset\n");return 2;
    }
    master=[IODeviceMaster new];if(!master)return 1;
    for(object=0;object<256;object++) {
        if([master lookUpByObjectNumber:object deviceKind:&kind deviceName:&name]!=IO_R_SUCCESS)continue;
        count=12;
        if([master getIntValues:values forParameter:"VirtioNetStats" objectNumber:object count:&count]!=IO_R_SUCCESS || count!=12)continue;
        if(strcmp(argv[1],"--stats")) {
            char *parameter="VirtioNetReset";
            values[0]=1;
#ifdef VIRTIO_NET_TESTING
            if(!strcmp(argv[1],"--clear-test-fault")) { parameter="VirtioNetTestFaults";values[0]=0; }
#endif
            result=[master setIntValues:values forParameter:parameter objectNumber:object count:1];
            [master free];return result?1:0;
        }
        printf("device=%s rx=%u submitted=%u completed=%u dropped=%u errors=%u resets=%u interrupts=%u online=%u link=%u rx_pending=%u tx_pending=%u backlog=%u\n",
            name,values[0],values[1],values[2],values[3],values[4],values[5],values[6],values[7],values[8],values[9],values[10],values[11]);
        [master free];return 0;
    }
    [master free];fprintf(stderr,"VirtioNet not found\n");return 1;
}
