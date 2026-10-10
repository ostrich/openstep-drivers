/* Native user-space probe for the standard OPENSTEP display blit interface. */
#import <driverkit/IODeviceMaster.h>
#import <driverkit/displayDefs.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
int main(int argc,char **argv)
{
    id master=[IODeviceMaster new];
    unsigned object,count,values[258],args[6];
    IOString name,kind;
    IOReturn result;
    if (!master) return 1;
    for(object=0;object<256;object++) {
        if ([master lookUpByObjectNumber:object deviceKind:&kind deviceName:&name] != IO_R_SUCCESS) continue;
        printf("device %u: %s (%s)\n",object,name,kind);
        if (strcmp(name,"Display0")) continue;
        if(argc==2 && !strcmp(argv[1],"--cursor-image")) {
            unsigned i;count=258;
            result=[master getIntValues:values forParameter:"VMWareCursorImage" objectNumber:object count:&count];
            printf("cursor image result %d count %u\n",result,count);
            if(!result) {for(i=0;i<count;i++) printf("%08x%s",values[i],i+1==count ? "\n" : " ");}
            [master free];return result ? 1 : 0;
        }
        count=3;
        result=[master getIntValues:values forParameter:"VMWareCursorPosition" objectNumber:object count:&count];
        if(!result) printf("cursor position %u,%u visible %u\n",values[0],values[1],values[2]);
        count=5;
        result=[master getIntValues:values forParameter:IO_GET_DISPLAY_INFO objectNumber:object count:&count];
        printf("display info result %d count %u: %u %u %u %u 0x%x\n",result,count,values[0],values[1],values[2],values[3],values[4]);
        count=6;
        result=[master getIntValues:values forParameter:"VMWareDisplayInfo" objectNumber:object count:&count];
        printf("driver info result %d: %ux%u stride %u flags 0x%x caps 0x%x active %u\n",result,values[0],values[1],values[2],values[3],values[4],values[5]);
        count=2;
        result=[master getIntValues:values forParameter:"VMWareBlitCount" objectNumber:object count:&count];
        printf("stats result %d: blits %u updates %u\n",result,values[0],values[1]);
        count=1;
        result=[master getIntValues:values forParameter:"VMWareFillCount" objectNumber:object count:&count];
        if(!result) printf("fill count %u\n",values[0]);
        count=6;
        result=[master getIntValues:values forParameter:"VMWareCursorStats" objectNumber:object count:&count];
        if(!result) printf("cursor stats: hardware %u frame %u definitions %u moves %u eligible 0x%x\n",values[0],values[1],values[2],values[3],values[4]);
        if(!result && count>=6) printf("cursor refresh RPCs %u\n",values[5]);
        count=5;
        result=[master getIntValues:values forParameter:"VMWareRefreshStats" objectNumber:object count:&count];
        if(!result) printf("refresh stats: polls %u requested rows %u updated rows %u full updates %u interval %u ms\n",values[0],values[1],values[2],values[3],values[4]);
        if(argc>1) {
            if(argc==3 && !strcmp(argv[1],"--fill-enabled")) {
                args[0]=strtoul(argv[2],0,0);
                result=[master setIntValues:args forParameter:"VMWareFillEnabled" objectNumber:object count:1];
                printf("fill enabled result %d\n",result);[master free];return result ? 1 : 0;
            }
            if(argc==7 && !strcmp(argv[1],"--fill")) {
                unsigned i;
                for(i=0;i<5;i++) args[i]=strtoul(argv[i+2],0,0);
                result=[master setIntValues:args forParameter:"VMWareFillRectangle" objectNumber:object count:5];
                printf("fill result %d\n",result);
                [master free];return result ? 1 : 0;
            }
            if(argc==4 && !strcmp(argv[1],"--refresh")) {
                if(strcmp(argv[3],"full") && strcmp(argv[3],"damage")) return 2;
                args[0]=strtoul(argv[2],0,10);args[1]=!strcmp(argv[3],"damage");
                result=[master setIntValues:args forParameter:"VMWareRefreshConfig" objectNumber:object count:2];
                printf("refresh config result %d\n",result);
                [master free];return result ? 1 : 0;
            }
            if(argc!=7) return 2;
            {unsigned i;for(i=0;i<6;i++) args[i]=strtoul(argv[i+1],0,10);}
            result=[master setIntValues:args forParameter:IO_DISPLAY_DO_BLIT objectNumber:object count:6];
            printf("blit result %d\n",result);
        }
    }
    [master free];return 0;
}
