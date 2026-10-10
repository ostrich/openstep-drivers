/* Disk command translation for the OPENSTEP IOSCSIController interface.
 * QEMU transport remains virtio-blk, not virtio-scsi. MIT license. */
#ifndef OS42_VIRTIO_BLOCK_SCSI_H
#define OS42_VIRTIO_BLOCK_SCSI_H
#include "block-protocol.h"
struct vb_rw_command { unsigned sector, bytes, type; };
/* Return 0 valid, otherwise SCSI ASC with ILLEGAL REQUEST sense key.
 * Caller checks LUN/target, data direction and write protection separately.
 * max_bytes is the request buffer extent, not a substitute for CDB length. */
static unsigned vb_decode_rw(const unsigned char *cdb,unsigned cdb_length,
                             unsigned max_bytes,unsigned capacity_lo,
                             unsigned capacity_hi,struct vb_rw_command *out)
{
    unsigned sector,count,type;
    if(!cdb || !out || !cdb_length)return 0x24;
    switch(cdb[0]) {
    case 0x08: case 0x0a:
        if(cdb_length!=6 || (cdb[1]&0xe0) || cdb[5])return 0x24;
        sector=((unsigned)(cdb[1]&31)<<16)|((unsigned)cdb[2]<<8)|cdb[3];
        count=cdb[4]?cdb[4]:256;
        type=cdb[0]==0x08?VB_T_IN:VB_T_OUT;
        break;
    case 0x28: case 0x2a:
        /* Accept DPO/FUA: writes are durable before successful completion.
         * Protection, relative-addressing, group and control bits unsupported. */
        if(cdb_length!=10 || (cdb[1]&~0x18U) || cdb[6] || cdb[9])return 0x24;
        sector=((unsigned)cdb[2]<<24)|((unsigned)cdb[3]<<16)|
               ((unsigned)cdb[4]<<8)|cdb[5];
        count=((unsigned)cdb[7]<<8)|cdb[8];
        type=cdb[0]==0x28?VB_T_IN:VB_T_OUT;
        break;
    default:return 0x20;
    }
    if(count>max_bytes/VB_SECTOR_SIZE)return 0x24;
    if(!vb_range_valid(sector,count*VB_SECTOR_SIZE,capacity_lo,capacity_hi))return 0x21;
    out->sector=sector;out->bytes=count*VB_SECTOR_SIZE;out->type=type;
    return 0;
}
#endif
