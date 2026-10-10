/* SCSI disk presentation for the virtio-blk IOSCSIController adapter.
 * Geometry is a logical hint, never a claim of physical rotating hardware. */
#ifndef OS42_VIRTIO_BLOCK_MODE_H
#define OS42_VIRTIO_BLOCK_MODE_H
#include <string.h>
/* Return SCSI ASC, or zero with full response size (caller limits transfer).
 * Caller provides at least 80 bytes. Parameters cannot be changed or saved.
 * Successful writes are flushed, so WCE is truthfully zero. */
static unsigned vb_mode_sense(const unsigned char *cdb,unsigned capacity,
                              unsigned cylinders,unsigned heads,unsigned sectors,
                              int readonly,unsigned char *reply,unsigned *size)
{
    unsigned page=cdb[2]&63,pc=cdb[2]>>6,n=4,start;
    if((cdb[1]&~8U) || cdb[3] || cdb[5])return 0x24;
    if(page!=0 && page!=3 && page!=4 && page!=8 && page!=63)return 0x24;
    if(pc==3)return 0x39; /* saving parameters not supported */
    memset(reply,0,80);reply[2]=readonly?0x80:0;
    if(!(cdb[1]&8)) {
        reply[3]=8;n=12;
        if(capacity<=0xffffff) {
            reply[5]=capacity>>16;reply[6]=capacity>>8;reply[7]=capacity;
        }
        reply[10]=2; /* 512-byte block length */
    }
    if(page==3 || page==63) {
        start=n;reply[n]=3;reply[n+1]=22;n+=24;
        if(pc!=1) {
            reply[start+2]=heads>>8;reply[start+3]=heads;
            reply[start+10]=sectors>>8;reply[start+11]=sectors;
            reply[start+12]=2;reply[start+15]=1;reply[start+20]=0x40;
        }
    }
    if(page==4 || page==63) {
        start=n;reply[n]=4;reply[n+1]=22;n+=24;
        if(pc!=1) {
            reply[start+2]=cylinders>>16;reply[start+3]=cylinders>>8;reply[start+4]=cylinders;
            reply[start+5]=heads;
            reply[start+6]=cylinders>>16;reply[start+7]=cylinders>>8;reply[start+8]=cylinders;
            reply[start+9]=cylinders>>16;reply[start+10]=cylinders>>8;reply[start+11]=cylinders;
            reply[start+14]=255;reply[start+15]=255;reply[start+16]=255;
            /* Zero RPM: virtio has no rotating medium to report. */
        }
    }
    if(page==8 || page==63) {
        reply[n]=8;reply[n+1]=18;n+=20;
    }
    reply[0]=n-1;*size=n;return 0;
}
#endif
