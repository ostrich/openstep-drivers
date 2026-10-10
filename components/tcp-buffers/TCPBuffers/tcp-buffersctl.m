/* MIT license. Status, and configuration changes for the next cold boot. */
#import <driverkit/IODeviceMaster.h>
#include <stdio.h>
#include <string.h>
#include <libc.h>
int main(int argc,char **argv)
{
    id master;unsigned object,count,values[5];IOString name,kind;
    if(argc!=2 || (strcmp(argv[1],"--status") && strcmp(argv[1],"--enable") && strcmp(argv[1],"--disable"))) {
        fprintf(stderr,"Usage: tcp-buffersctl --status | --enable | --disable\n");return 2;
    }
    if(strcmp(argv[1],"--status")) {
        execl("/usr/local/sbin/tcp-buffers-configure","tcp-buffers-configure",argv[1]+2,(char *)0);
        perror("configure");return 1;
    }
    master=[IODeviceMaster new];if(!master)return 1;
    for(object=0;object<256;object++) {
        if([master lookUpByObjectNumber:object deviceKind:&kind deviceName:&name]!=IO_R_SUCCESS)continue;
        count=5;
        if([master getIntValues:values forParameter:"TCPBufferDefaults" objectNumber:object count:&count]!=IO_R_SUCCESS || count!=5)continue;
        printf("send=%u receive=%u previous_send=%u previous_receive=%u applied=%u\n",values[0],values[1],values[2],values[3],values[4]);[master free];return 0;
    }
    [master free];fprintf(stderr,"TCPBuffers is not loaded; boot after enabling it.\n");return 1;
}
