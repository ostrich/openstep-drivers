/*
 * Copyright (c) 2002 by Atomic Object LLC
 * All rights reserved.
 *
 * VMWareFBRegisters.m -- registers methods for VMWare display driver
 *
 * Created by Bill Bereza 2001/01/17
 * $Id$
 */

#import "VMWareFB.h"

#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#include <string.h>
#include "VMWareFBPolicy.h"

/* The 'VMWareFBRegisters category of 'VMWareFB' */
@implementation VMWareFB (Registers)

/*
 * Return the VMWare SVGA ID using the given index and value ports.
 */
+ (uint32) getVMWareSVGAIDAtIndexRegister: (uint16)indexRegister
														valueRegister: (uint16)valueRegister
{
	return VMXGetVMwareSvgaId(indexRegister, valueRegister);
}

/*
 * Get the index and value I/O register addresses from the PCI
 * configuration using the given device description.
 * Return IO_R_SUCCESS if values are retrieved.
 */
+ (IOReturn)getIndexRegister: (uint16 *)indexRegister
							 valueRegister: (uint16 *)valueRegister
			 withDeviceDescription: deviceDescription
{
	IOPCIConfigSpace pciConfig;	/* PCI Configuration */
	IOReturn configReturn;				// return value from getPCIConfigSpace

	if( ( configReturn =  [self getPCIConfigSpace: &pciConfig
															withDeviceDescription: deviceDescription] )
		!= IO_R_SUCCESS ) {
		IOLog("VMWareFB: Failed to get PCI config data.\n");
		return configReturn;
	}

	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: getting registers for PCI device: %04x vendor: %04x.\n",
		pciConfig.DeviceID, pciConfig.VendorID);
#endif
    }

	// sanity check to see that the vendor id is VMWares
	if ( pciConfig.VendorID != PCI_VENDOR_ID_VMWARE ) {
		IOLog("VMWareFB: Got called for some other vendor: %04x\n",
			pciConfig.VendorID);
		return IO_R_NO_DEVICE;
	}

	// the old device has a fixed base port
	if ( pciConfig.DeviceID == PCI_DEVICE_ID_VMWARE_SVGA ) {
		{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: Legacy device found.\n");
#endif
    }
		*indexRegister = SVGA_LEGACY_BASE_PORT + SVGA_INDEX_PORT * sizeof(uint32);
		*valueRegister = SVGA_LEGACY_BASE_PORT + SVGA_VALUE_PORT * sizeof(uint32);
	} else {
		// assume a new model vmware device
		// base port is base address register 0

		unsigned long basePort;

		// Use the NextStep masks to see if the base address for this
		// PCI device is actually an I/O port address
		if( (pciConfig.BaseAddress[0] & PCI_BASE_ADDRESS_SPACE)
			!= PCI_BASE_ADDRESS_SPACE_IO )
		{
			// This shouldn't happen. Don't know what to do if it does.
			IOLog("VMWareFB: WARNING: BaseAddress[0] may not be an I/O address!\n");
			// FIXME: not returning failure may be mistake
		}

		basePort = pciConfig.BaseAddress[0] & PCI_BASE_ADDRESS_IO_MASK;

		*indexRegister = basePort + SVGA_INDEX_PORT;
		*valueRegister = basePort + SVGA_VALUE_PORT;
	}

	return IO_R_SUCCESS;
}

/* VMWare specific methods. */

- (CARD32) readRegister: (int) index
{
	return vmwareReadReg(indexReg, valueReg, index);
}

- (void) writeRegister: (int) index value: (CARD32) value
{
	vmwareWriteReg(indexReg, valueReg, index, value);
}

static void fifoSync(void *device)
{
    [(VMWareFB *)device writeRegister:SVGA_REG_SYNC value:1];
}
static unsigned fifoBusy(void *device)
{
    return [(VMWareFB *)device readRegister:SVGA_REG_BUSY];
}
static void fifoDelay(void *device) { IODelay(100); }

/* A failure return always means that the command was not published. */
- (BOOL)submitCommand:(const CARD32 *)words count:(unsigned int)count
{
    int result=VM_FIFO_REJECTED;
    [fifoLock lock];
    if(active) result=vmwareFifoSubmit(fifo,fifoLength,words,count,
                                     self,fifoSync,fifoBusy,fifoDelay);
    if(result==VM_FIFO_UNCERTAIN) {
        /* Reset cannot establish whether an overlapping copy already ran.
         * A device that never completes cannot safely permit CPU fallback.
         * Fail closed instead of silently corrupting framebuffer contents. */
        IOPanic("VMWareFB: published FIFO command did not complete");
        for(;;) IODelay(1000);
    }
    [fifoLock unlock];return result==VM_FIFO_COMPLETE;
}

- (void) updateDisplayX1:(int)x1 Y1:(int)y1 X2:(int)x2 Y2:(int)y2
{
    CARD32 words[5];
    words[0]=SVGA_CMD_UPDATE;words[1]=x1;words[2]=y1;words[3]=x2;words[4]=y2;
    if ([self submitCommand:words count:5]) updateCount++;
}

- (void) updateFullScreen
{
	IODisplayInfo *displayInfo;		// current display info

	/* get our display info */
	displayInfo = [self displayInfo];

	[self updateDisplayX1: 0
				Y1: 0
				X2: displayInfo->width
				Y2: displayInfo->height];
}

/* Damage is collected without reading VRAM. CPU framebuffer reads were
 * prohibitively expensive on the tested KVM mapping. */
- (void)damageX:(unsigned)x y:(unsigned)y width:(unsigned)w height:(unsigned)h
{
    IODisplayInfo *info=[self displayInfo];
    if (!w || !h || x>=info->width || y>=info->height) return;
    if (w>info->width-x) w=info->width-x;
    if (h>info->height-y) h=info->height-y;
    [fifoLock lock];
    if (!damagePending) { damageLeft=x;damageTop=y;damageRight=x+w;damageBottom=y+h; }
    else {
        if(x<damageLeft) damageLeft=x;
        if(y<damageTop) damageTop=y;
        if(x+w>damageRight) damageRight=x+w;
        if(y+h>damageBottom) damageBottom=y+h;
    }
    damagePending=YES;requestedRows+=h;
    [fifoLock unlock];
}

- (void) flushDamage
{
    IODisplayInfo *info=[self displayInfo];
    CARD32 words[5];
    BOOL pending;
    [fifoLock lock];
    pollCount++;pending=damagePending;
    if(!damageTracking || ++safetyTicks>=50) {
        words[0]=SVGA_CMD_UPDATE;words[1]=words[2]=0;
        words[3]=info->width;words[4]=info->height;
        pending=YES;damagePending=NO;safetyTicks=0;
    } else if(pending) {
        words[0]=SVGA_CMD_UPDATE;words[1]=damageLeft;words[2]=damageTop;
        words[3]=damageRight-damageLeft;words[4]=damageBottom-damageTop;
        damagePending=NO;
    }
    [fifoLock unlock];
    if(pending) {
        if ([self submitCommand:words count:5]) {
            updateCount++;updatedRows+=words[4];
            if(!words[1] && !words[2] && words[3]==info->width && words[4]==info->height) fullUpdates++;
        } else [self damageX:words[1] y:words[2] width:words[3] height:words[4]];
    }
}

@end
