/* Virtio 1.2 section 5.2. Legacy x86 wire layout; no native 64-bit ABI dependency. */
#ifndef OS42_VIRTIO_BLOCK_PROTOCOL_H
#define OS42_VIRTIO_BLOCK_PROTOCOL_H
#define VB_F_GEOMETRY (1U << 4)
#define VB_F_RO (1U << 5)
#define VB_F_BLK_SIZE (1U << 6)
#define VB_F_FLUSH (1U << 9)
#define VB_T_IN 0U
#define VB_T_OUT 1U
#define VB_T_FLUSH 4U
#define VB_S_OK 0U
#define VB_S_IOERR 1U
#define VB_S_UNSUPP 2U
#define VB_SECTOR_SIZE 512U
struct vb_header { unsigned type, reserved, sector_lo, sector_hi; };
/* Reject partial sectors and overflow before descriptor publication. A zero
 * byte operation is handled by the caller without a device request. Capacity
 * is a count, so a request ending exactly at capacity is valid. */
static int vb_range_valid(unsigned sector, unsigned bytes,
                          unsigned capacity_lo, unsigned capacity_hi)
{
    unsigned sectors;
    if(bytes & (VB_SECTOR_SIZE-1))return 0;
    sectors=bytes/VB_SECTOR_SIZE;
    /* OPENSTEP's unsigned block addressing: never wrap a split request. */
    if(sectors && sector > ~0U-(sectors-1))return 0;
    if(capacity_hi)return 1;
    if(sector>capacity_lo)return 0;
    return sectors<=capacity_lo-sector;
}
/* A completed error may account for all writable read descriptors even though
 * their data is invalid. Status is authoritative; used length is a bound check.
 * Return 1 success, 0 well-formed device error, -1 malformed completion. */
static int vb_completion_result(unsigned type,unsigned bytes,
                                unsigned used,unsigned status)
{
    unsigned expected;
    if(type!=VB_T_IN && type!=VB_T_OUT && type!=VB_T_FLUSH)return -1;
    if(status>VB_S_UNSUPP)return -1;
    if(type==VB_T_IN && bytes==~0U)return -1;
    expected=type==VB_T_IN?bytes+1:1;
    if(!used || used>expected)return -1;
    if(status!=VB_S_OK)return 0;
    return used==expected?1:-1;
}
#endif
