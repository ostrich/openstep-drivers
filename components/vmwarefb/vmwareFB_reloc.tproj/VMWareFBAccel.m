/*
 * Copyright (c) 2002 by Atomic Object LLC
 * All rights reserved.
 *
 * VMWareFBAccel.m -- accel methods for VMWare display driver
 *
 * Created by Bill Bereza 2001/01/17
 * $Id$
 */

#import "VMWareFB.h"
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>

#include <string.h>

/* The 'VMWareFBAccell' category of 'VMWareFB' */
@implementation VMWareFB (Accel)

/*
 * Do accelerated FIFO commands based on parameters.
 * Print out unknown params before passing to super, for debug.
 */
- (IOReturn) setIntValues: (unsigned int *) array
						 forParameter: (IOParameterName) parameter
										count: (unsigned int) count
{
    if (!strcmp(parameter,"VMWareCursorImage")) return [self installCursorImage:array count:count];
    if (!strcmp(parameter,"VMWareCursorRefresh")) {
        if(count) return IO_R_INVALID_ARG;
        cursorRefreshRequests++;return [self syncHardwareCursor];
    }
    if (!strcmp(parameter,"VMWareCursorFallback")) {
        if(count!=1 || array[0]>=4) return IO_R_INVALID_ARG;
        [fifoLock lock];cursorEligible[array[0]]=NO;[fifoLock unlock];
        [self syncHardwareCursor];return IO_R_SUCCESS;
    }
    if (!strcmp(parameter,"VMWareFillEnabled")) {
        if(count!=1 || array[0]>1) return IO_R_INVALID_ARG;
        fillEnabled=array[0];return IO_R_SUCCESS;
    }
    if (!strcmp(parameter,"VMWareFillRectangle")) {
        IODisplayInfo *info=[self displayInfo];
        CARD32 words[6];
        unsigned x,y,w,h;
        if(count!=5 || array[4]>0xffffff) return IO_R_INVALID_ARG;
        x=array[0];y=array[1];w=array[2];h=array[3];
        if(!w || !h) return IO_R_SUCCESS;
        if(x>=info->width || y>=info->height || w>info->width-x || h>info->height-y)
            return IO_R_INVALID_ARG;
        if(acceleration!=DEFAULT_ACCELERATION || !fillEnabled || !active || !(vmwareCapability & SVGA_CAP_RECT_FILL) ||
           info->bitsPerPixel!=IO_24BitsPerPixel) return IO_R_UNSUPPORTED;
        words[0]=SVGA_CMD_RECT_FILL;words[1]=array[4];words[2]=x;words[3]=y;
        words[4]=w;words[5]=h;
        if(![self submitCommand:words count:6]) return IO_R_RESOURCE;
        fillCount++;return IO_R_SUCCESS;
    }
    if (!strcmp(parameter,"VMWareRefreshConfig")) {
        if(count!=2 || array[0]<1 || array[0]>1000 || array[1]>1) return IO_R_INVALID_ARG;
        [fifoLock lock];refreshInterval=array[0];damageTracking=array[1];[fifoLock unlock];
        return IO_R_SUCCESS;
    }
    if (!strcmp(parameter,"VMWareDamage")) {
        if(count!=4) return IO_R_INVALID_ARG;
        [self damageX:array[0] y:array[1] width:array[2] height:array[3]];
        return IO_R_SUCCESS;
    }
    if (!strcmp(parameter,IO_DISPLAY_DO_BLIT)) {
        IODisplayInfo *info = [self displayInfo];
        CARD32 words[7];
        unsigned sx,sy,w,h,dx,dy;
        if (count != IO_DISPLAY_BLIT_SIZE) return IO_R_INVALID_ARG;
        sx=array[0]; sy=array[1]; w=array[2]; h=array[3]; dx=array[4]; dy=array[5];
        if (!w || !h) return IO_R_SUCCESS;
        if (sx >= info->width || dx >= info->width || sy >= info->height || dy >= info->height ||
            w > info->width-sx || w > info->width-dx ||
            h > info->height-sy || h > info->height-dy) return IO_R_INVALID_ARG;
        if (acceleration!=DEFAULT_ACCELERATION || !(vmwareCapability & SVGA_CAP_RECT_COPY) || !active) return IO_R_RESOURCE;
        words[0]=SVGA_CMD_RECT_COPY; words[1]=sx; words[2]=sy;
        words[3]=dx; words[4]=dy; words[5]=w; words[6]=h;
        if (![self submitCommand:words count:7]) return IO_R_RESOURCE;
        ++blitCount;
        if (blitCount <= 8) {
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: accelerated blit %u,%u %ux%u -> %u,%u\n",sx,sy,w,h,dx,dy);
#endif
    }
        return IO_R_SUCCESS;
    }
    if (!strcmp(parameter,VMWAREUPDATE_PARAM)) {
        [self updateFullScreen];return IO_R_SUCCESS;
    }
    if (!strcmp(parameter,"VMWareBlitCount")) return IO_R_UNSUPPORTED;
    return [super setIntValues:array forParameter:parameter count:count];
}


- (IOReturn) getIntValues: (unsigned int *)array
						 forParameter: (IOParameterName) parameter
										count: (unsigned int *)count
{
    if (!strcmp(parameter,"VMWareCursorPosition") && *count>=3) {
        [fifoLock lock];array[0]=[self readRegister:SVGA_REG_CURSOR_X];
        array[1]=[self readRegister:SVGA_REG_CURSOR_Y];array[2]=[self readRegister:SVGA_REG_CURSOR_ON];
        [fifoLock unlock];*count=3;return IO_R_SUCCESS;
    }
    if (!strcmp(parameter,"VMWareCursorImage") && *count>=258) {
        unsigned frame=hardwareFrame;
        if(frame>=4) return IO_R_UNSUPPORTED;
        [fifoLock lock];array[0]=frame;array[1]=cursorHotspots[frame];
        memcpy(array+2,cursorImages[frame],1024);[fifoLock unlock];
        *count=258;return IO_R_SUCCESS;
    }
    if (!strcmp(parameter,"VMWareCursorStats") && *count>=5) {
        unsigned i,mask=0;
        for(i=0;i<4;i++) if(cursorEligible[i]) mask|=1U<<i;
        array[0]=hardwareCursor;array[1]=hardwareFrame;array[2]=cursorDefinitions;
        array[3]=cursorMoves;array[4]=mask;
        if(*count>=6) {array[5]=cursorRefreshRequests;*count=6;} else *count=5;
        return IO_R_SUCCESS;
    }
    if (!strcmp(parameter,"VMWareFillCount") && *count>=1) {
        array[0]=fillCount;*count=1;return IO_R_SUCCESS;
    }
    if (!strcmp(parameter,"VMWareRefreshStats") && *count >= 5) {
        array[0]=pollCount;array[1]=requestedRows;array[2]=updatedRows;
        array[3]=fullUpdates;array[4]=refreshInterval;*count=5;
        return IO_R_SUCCESS;
    }
    if (!strcmp(parameter,"VMWareDisplayInfo") && *count >= 6) {
        IODisplayInfo *info=[self displayInfo];
        array[0]=info->width;array[1]=info->height;array[2]=info->rowBytes;
        array[3]=info->flags;array[4]=vmwareCapability;array[5]=active;*count=6;
        return IO_R_SUCCESS;
    }
    if (!strcmp(parameter,"VMWareBlitCount") && *count >= 2) {
        array[0]=blitCount; array[1]=updateCount; *count=2; return IO_R_SUCCESS;
    }

	return [super getIntValues: array
								forParameter: parameter
								count: count];
}



- (IOReturn) getCharValues: (unsigned char *) array
							forParameter: (IOParameterName) parameter
										 count: (unsigned int *)count
{
	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: getCharValues for param: %s\n", parameter);
#endif
    }

	return [super getCharValues: array
								forParameter: parameter
								count: count];
}


- (IOReturn) setCharValues: (unsigned char *)array
							forParameter: (IOParameterName) parameter
										 count: (unsigned int) count
{
	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: setCharValues for param: %s\n", parameter);
#endif
    }

	return [super setCharValues: array
								forParameter: parameter
								count: count];
}


@end
