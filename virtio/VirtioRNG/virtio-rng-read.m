#import <driverkit/IODeviceMaster.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc,char **argv)
{
    id master=[IODeviceMaster new];
    unsigned obj,count,values[12],left,total=0;
    IOString name,kind;
    unsigned char bytes[256];
    IOReturn result=IO_R_NO_DEVICE;
    if(!master)return 1;
    for(obj=0;obj<256;obj++) {
        if([master lookUpByObjectNumber:obj deviceKind:&kind deviceName:&name]!=IO_R_SUCCESS || strcmp(name,"VirtioRNG0"))continue;
        if(argc==2 && !strcmp(argv[1],"--stats")) {
            count=12;result=[master getIntValues:values forParameter:"VirtioRNGStats" objectNumber:obj count:&count];
            if(!result && count==12)printf("requests=%u completions=%u interrupts=%u stray=%u errors=%u resets=%u online=%u ring=%x/%u buffer=%x irq=%u queue=%u\n",values[0],values[1],values[2],values[3],values[4],values[5],values[6],values[7],values[8],values[9],values[10],values[11]);
        } else if(argc==2 && !strcmp(argv[1],"--reset")) {
            values[0]=1;result=[master setIntValues:values forParameter:"VirtioRNGReset" objectNumber:obj count:1];
        } else if(argc==2) {
            char *end;left=strtoul(argv[1],&end,10);
            if(*end || !left || left>1048576) { fprintf(stderr,"Byte count must be 1..1048576\n");[master free];return 2; }
            while(left) {
                count=left>256?256:left;
                result=[master getCharValues:bytes forParameter:"VirtioRNGRead" objectNumber:obj count:&count];
                if(result || !count || count>left || count>256) { if(!result)result=IO_R_IO;break; }
                if(fwrite(bytes,1,count,stdout)!=count) { result=IO_R_IO;break; }
                left-=count;total+=count;
            }
            if(!result && fflush(stdout))result=IO_R_IO;
        } else { fprintf(stderr,"Usage: virtio-rng-read BYTE_COUNT | --stats | --reset\n");[master free];return 2; }
        [master free];if(result)fprintf(stderr,"VirtioRNG request failed: %d (bytes %u)\n",result,total);return result?1:0;
    }
    [master free];fprintf(stderr,"VirtioRNG0 not found\n");return 1;
}
