/* Legacy SVGA hardware cursor. OPENSTEP 4.2's converted cursor bank is
 * shared with WindowServer. Keep the parent's hide/show/shield bookkeeping,
 * but substitute transparent pixels for shapes represented by hardware.
 * Partial alpha and unsupported hotspots retain the original software image.
 */
#import "VMWareFB.h"
#import <objc/objc-runtime.h>
#include <string.h>

static unsigned char *sharedCursor(id object)
{
    void *shared=0;
    if(!object_getInstanceVariable(object,"priv",&shared)) return 0;
    return shared;
}

@implementation VMWareFB (Cursor)
- (IOReturn)installCursorImage:(unsigned *)values count:(unsigned)count
{
    unsigned frame,hot,i;
    BOOL eligible;
    unsigned char *shared=sharedCursor(self);
    if(count!=258 || values[0]>=4 || !shared) return IO_R_INVALID_ARG;
    frame=values[0];hot=values[1];
    eligible=active && acceleration!=NO_ACCELERATION && (vmwareCapability & SVGA_CAP_CURSOR) &&
        (hot&65535)<16 && (hot>>16)<16 &&
        [self displayInfo]->bitsPerPixel==IO_24BitsPerPixel;
    for(i=0;i<256;i++) {
        unsigned p=values[i+2],alpha=p>>24;
        if((alpha!=0 && alpha!=255) || (!alpha && p)) eligible=NO;
    }
    /* WindowServer owns the shared-cursor semaphore during this call.
     * Cache only; never spin on a userspace-owned lock from the kernel. */
    [fifoLock lock];
    memcpy(cursorImages[frame],values+2,1024);cursorHotspots[frame]=hot;
    cursorEligible[frame]=eligible;hardwareFrame=~0U;
    [fifoLock unlock];
    return eligible ? IO_R_SUCCESS : IO_R_UNSUPPORTED;
}

- (IOReturn)syncHardwareCursor
{
    unsigned char *shared=sharedCursor(self);
    unsigned frame,i,hot,visible;
    unsigned *pixels;
    Point point;
    short bounds[4];
    BOOL hadHardware=hardwareCursor;
    BOOL eligible=NO;
    IOReturn result=IO_R_SUCCESS;
    CARD32 words[536];
    if(!shared || !active) return IO_R_UNSUPPORTED;
    if(!ev_try_lock((ev_lock_t)(shared+4))) return IO_R_RESOURCE;
    frame=*(unsigned *)shared;visible=shared[8]==0;
    memcpy(&point,shared+0x1c,sizeof(point));
    memcpy(bounds,shared+0x20,sizeof(bounds));
    if(frame<4 && cursorEligible[frame]) {
        eligible=YES;pixels=(unsigned *)(shared+0x48+frame*1024);
        /* A new MPSetCursor image may arrive before its notification.
         * Never display an old hardware shape over a new software image. */
        for(i=0;i<256;i++) if(pixels[i]) {eligible=NO;cursorEligible[frame]=NO;break;}
    }
    if(eligible && hardwareFrame!=frame) {
        hot=cursorHotspots[frame];
        memset(words,0,sizeof(words));
        words[0]=SVGA_CMD_DEFINE_CURSOR;words[1]=0;
        words[2]=hot&65535;words[3]=hot>>16;
        /* Legacy masks have 32-bit row alignment. QEMU's cursor helper
         * assumes byte-packed rows; width 32 satisfies both layouts. */
        words[4]=32;words[5]=16;words[6]=1;words[7]=32;
        for(i=0;i<16;i++) words[8+i]=~0U;
        for(i=0;i<256;i++) {
            unsigned x=i%16,y=i/16;
            if(cursorImages[frame][i]>>24)
                words[8+y]&=~(1U<<((x/8)*8+7-x%8));
            words[24+y*32+x]=cursorImages[frame][i]&0xffffff;
        }
        if([self submitCommand:words count:536]) {
            hardwareFrame=frame;cursorDefinitions++;
        } else {
            eligible=NO;result=IO_R_RESOURCE;cursorEligible[frame]=NO;
            memcpy(shared+0x48+frame*1024,cursorImages[frame],1024);
        }
    }
    ev_unlock((ev_lock_t)(shared+4));
    /* Userspace SysHide/SysShow also write the framebuffer. Notify the
     * actual cursor rectangle for software visibility changes and for
     * software-to-hardware transitions; hardware-only changes need no blit. */
    if(!eligible || !hadHardware) {
        int x=bounds[0]<0 ? 0 : bounds[0],y=bounds[2]<0 ? 0 : bounds[2];
        if(bounds[1]>x && bounds[3]>y)
            [self damageX:x y:y width:bounds[1]-x height:bounds[3]-y];
    }
    [fifoLock lock];
    if(eligible) {
        [self writeRegister:SVGA_REG_CURSOR_X value:(int)point.x];
        [self writeRegister:SVGA_REG_CURSOR_Y value:(int)point.y];
        [self writeRegister:SVGA_REG_CURSOR_ON value:visible ? 1 : 0];
        cursorMoves++;
    } else [self writeRegister:SVGA_REG_CURSOR_ON value:0];
    hardwareCursor=eligible;
    [fifoLock unlock];
    return result;
}

- (void)disableHardwareCursor
{
    unsigned frame;
    /* The event-driver mapping may already be gone at mode teardown.
     * Its pixels are discarded with that mapping; do not dereference priv. */
    [fifoLock lock];
    for(frame=0;frame<4;frame++) cursorEligible[frame]=NO;
    [self writeRegister:SVGA_REG_CURSOR_ON value:0];
    hardwareCursor=NO;hardwareFrame=~0U;
    [fifoLock unlock];
}
@end
