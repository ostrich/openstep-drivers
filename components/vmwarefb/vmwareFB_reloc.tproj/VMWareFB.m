/*
 * Copyright (c) 2002 by Atomic Object LLC
 * All rights reserved.
 *
 * VMWareFB.m -- driver for VMWare display driver
 *
 * Created by Bill Bereza 2001/01/17
 * $Id: VMWareFB.m,v 1.2 2002/02/14 22:37:38 bereza Exp $
 */

#import "VMWareFB.h"
#include <stdio.h>
#include <string.h>
#include "VMWareFBPolicy.h"
#import <driverkit/kernelDriver.h>
#import <driverkit/generalFuncs.h>
#import <kernserv/kern_server_types.h>
#import <machkit/NXLock.h>

#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>

/* The frameBuffer field is initialized to 0 since it's determined at
 * runtime. The parameters field is left at 0.
 *
 * This is the table of all _possible_ modes this driver supports.
 * Based on the capabilities returned from the device, a specific
 * mode will be selected.
 *
 * Depth will always be ignored, and automatically set to whatever
 * the VMWare device reports. All the listed modes below are for
 * 32-bit depth, while should let selectMode:count:valid: pick
 * the right mode based on the resolution selected by the user.
 */
static const IODisplayInfo modeTable[] = {
	{
		/* 640 x 480, RGB:888/32 */
		640, 480, 640, 2560, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	}
	,
	{
		/* 800 x 600, RGB:888/32 */
		800, 600, 800, 3200, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	}
	,
	{
		/* 1024 x 768, RGB:888/32 */
		1024, 768, 1024, 4096, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	}
	,
	{
		/* 1152 x 864, RGB:888/32 */
		1152, 864, 1152, 4608, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	}
	,
	{
		/* 1280 x 720, RGB:888/32 */
		1280, 720, 1280, 5120, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	}
	,
	{
		/* 1280 x 768, RGB:888/32 */
		1280, 768, 1280, 5120, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	}
	,
	{
		/* 1280 x 800, RGB:888/32 */
		1280, 800, 1280, 5120, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	}
	,
	{
		/* 1280 x 960, RGB:888/32 */
		1280, 960, 1280, 5120, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	}
	,
	{
		/* 1280 x 1024, RGB:888/32 */
		1280, 1024, 1280, 5120, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	}
	,
	{
		/* 1366 x 768, RGB:888/32 */
		1366, 768, 1366, 5464, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	}
	,
	{
		/* 1440 x 900, RGB:888/32 */
		1440, 900, 1440, 5760, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	}
	,
	{
		/* 1600 x 1200, RGB:888/32 */
		1600, 1200, 1600, 6400, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	}
	,
	{
		/* 1680 x 1050, RGB:888/32 */
		1680, 1050, 1680, 6720, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	}
	,
	{
		/* 1920 x 1080, RGB:888/32 */
		1920, 1080, 1920, 7680, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	}
	,
	{
		/* 1920 x 1200, RGB:888/32 */
		1920, 1200, 1920, 7680, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	}
	,
	{
		/* 2560 x 1440, RGB:888/32 */
		2560, 1440, 2560, 10240, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	}
	,
	{
		/* 2560 x 1600, RGB:888/32 */
		2560, 1600, 2560, 10240, 60, 0,
		IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
		0, 0
	}
    ,
    {
        /* 3840 x 2160, RGB:888/32 */
        3840, 2160, 3840, 15360, 60, 0,
        IO_24BitsPerPixel, IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB",
        0, 0
    }
};

#define modeTableCount (sizeof(modeTable) / sizeof(IODisplayInfo))

#define defaultMode 0;

@implementation VMWareFB

/*
 * Probe for existence of the VMWare device.
 * (Legacy FB memory range 0x7EFC0000 - 7FFC0000)
 *
 * This method performs the following steps:
 *
 * 1. Get PCI configuration information for the device. Use
 * getPCIConfig to get the base address.
 *
 * 2. Use the PCI chiptype to decide if the device is a 0710 legacy
 * chipset to get the index and value registers. Store index and value
 * registers.  (SVGA_INDEX_PORT, SVGA_VALUE_PORT)
 *
 * 3. Get the VMWare ID using getVMWareSVGAID(). If the id is
 *    SVGA_ID_INVALID or SVGA_ID_0, return NO.  (SVGA_REG_ID)
 *
 * 4. Read the frame buffer start and size the registers,
 * SVGA_REG_FB_START, SVGA_REG_FB_SIZE.  Set the framebuffer memory
 * range on the IODeviceDesciption with setMemoryRangeList:num: to set
 * the 0th memory range.  (SVGA_REG_FB_START, SVGA_REG_FB_SIZE)
 *
 * 5. Read the fifo memory start and size the registers,
 * SVGA_REG_MEM_START, SVGA_REG_MEM_SIZE.  Set the framebuffer memory
 * range on the IODeviceDesciption with setMemoryRangeList:num: to set
 * the 1th memory range.  (SVGA_REG_MEM_START, SVGA_REG_MEM_SIZE)
 *
 * 6. alloc an instance and call initFromDeviceDescription:
 *
 * 7. Return YES if initFromDeviceDescription: is successful return
 * YES, otherwise return NO.
 */
+ (BOOL)probe: deviceDescription
{
	uint16 indexRegister, valueRegister;	/* index and value registers */
	uint32 id;					/* SVGA ID of vmware device */
	CARD32 physicalMemoryBase;	/* frame buffer start */
	CARD32 physicalMemorySize;	/* frame buffer size */
	// 2002-02-13 removed
	CARD32 fifoBase;			/* FIFO start */
	CARD32 fifoSize;			/* FIFO size */
	int numRanges;				/* number of memory ranges */
	IORange *oldRange, newRange[3];	/* Memory ranges. Should always be
																	 * 3. This will be checked.
																	 */
	VMWareFB *newDriver;					// instance of VMWareFB driver

	if( [ self getIndexRegister: &indexRegister valueRegister: &valueRegister
						 withDeviceDescription: deviceDescription ]
		!= IO_R_SUCCESS)
	{
		IOLog("VMWareFB: problem getting index and value registers.\n");
		return NO;
	}

	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWare SVGA regs at (0x%04x, 0x%04x)\n",
		indexRegister, valueRegister);
#endif
    }

	// Get the ID of the version of the VMWare device
	id = [self getVMWareSVGAIDAtIndexRegister: indexRegister valueRegister: valueRegister];

	// don't support version 0 or INVALID
	if ( id == SVGA_ID_0 || id == SVGA_ID_INVALID ) {
		IOLog("VMWareFB: No supported VMWare SVGA found (read ID 0x%08x).\n", id);
		return NO;
	}

	// Get the start and size of the frame buffer in physical memory
	physicalMemoryBase = vmwareReadReg(indexRegister, valueRegister, SVGA_REG_FB_START);
	physicalMemorySize = vmwareReadReg(indexRegister, valueRegister, SVGA_REG_FB_SIZE);

	// 2002-02-13 not using fifo
	// Get the start and size of the command FIFO in physical memory
	fifoBase = vmwareReadReg(indexRegister, valueRegister, SVGA_REG_MEM_START);
	fifoSize = vmwareReadReg(indexRegister, valueRegister, SVGA_REG_MEM_SIZE);

	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: framebuffer range: 0x%08x-0x%08x\n",
		physicalMemoryBase,
		physicalMemoryBase + physicalMemorySize);
#endif
    }

	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: framebuffer size: 0x%08x\n",
		physicalMemorySize);
#endif
    }

	//VMLog("VMWareFB: fifo address: 0x%08x\n",
	//	fifoBase);

	// get the existing array of memory ranges
	oldRange = [deviceDescription memoryRangeList];
	numRanges = [deviceDescription numMemoryRanges];
	if (numRanges == 3) {
    int     ret;
    int     i;

    /* replace the address */
    for (i = 0; i < numRanges; i++) {
			newRange[i] = oldRange[i];
    }
    // frame buffer
    newRange[0].start = physicalMemoryBase;
    newRange[0].size = physicalMemorySize;
		// 2002-02-13 removed fifo uses
    // command fifo
    newRange[1].start = fifoBase;
    newRange[1].size = fifoSize > 65536 ? 65536 : fifoSize;

    ret = [deviceDescription setMemoryRangeList:newRange num:3];
    if (ret) {
        IOLog("VMWareFB: cannot register framebuffer/FIFO ranges\n");
        return NO;
    }
	} else {
		IOLog("%s: Incorrect number of address ranges: %d.\n",
			[self name], numRanges);
		return NO;
	}

	// 2002-02-14: Maybe we should just return [super probe] here?

	newDriver = [[self alloc] initFromDeviceDescription: deviceDescription ];

	if(newDriver == NULL)
	{
		IOLog("VMWareFB probe: problem initializing instance.\n");
		return NO;
	}

	[newDriver setDeviceKind: "Linear Framebuffer"];
	[newDriver registerDevice];

	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: display initialized and ready to go.\n");
#endif
    }
	return YES;
}

/*
 * Initialize the the device driver, and Driver instance.
 *
 * 0. Call [super init...]
 *
 * 1. Map the frame buffer and and command FIFO into memory.
 *    (SVGA_REG_FB_START, SVGA_REG_FB_SIZE, SVGA_REG_MEM_START,
 *     SVGA_REG_MEM_SIZE)
 *
 * 2. Get the device capabilities and frame buffer dimensions.
 *    Set boolean capability i-vars to values.
 *    (SVGA_REG_CAPABILITIES, SVGA_REG_MAX_WIDTH, SVGA_REG_MAX_HEIGHT,
 *     SVGA_REG_HOST_BITS_PER_PIXEL -or- SVGA_REG_BITS_PER_PIXEL)
 *    (If SVGA_CAP_8BIT_EMULATIONS is not set, then it is possible that
 *     SVGA_REG_HOST_BITS_PER_PIXEL does not exist and
 *     SVGA_REG_BITS_PER_PIXEL should be read instead.)
 *
 * 3. Report the Guest Operating System. (SVGA_REG_GUEST_ID)
 *
 * 4. Call selectMode:count:valid: to select the display mode.
 *
 * 5. Get displayInfo and set it up using selected mode and
 * framebuffer address. Using returned capabilities. (See IODisplay
 * displayInfo method docs). Do not actually enable SVGA.
 * That happens when enterLinearMode is called.
 *
 * 6. Set the mode.
 * 	  Set SVGA_REG_WIDTH, SVGA_REG_HEIGHT, SVGA_REG_BITS_PER_PIXEL
 *	  Read SVGA_REG_FB_OFFSET
 *	  (SVGA_REG_FB_OFFSET is the offset from SVGA_REG_FB_START of the
 *	   visible portion of the frame buffer)
 *	  Read SVGA_REG_BYTES_PER_LINE, SVGA_REG_DEPTH, SVGA_REG_PSEUDOCOLOR,
 *	  SVGA_REG_RED_MASK, SVGA_REG_GREEN_MASK, SVGA_REG_BLUE_MASK
 */
/* Compile only in the disposable kernel failure-test build. Normal builds
 * neither parse this key nor contain the injection branches. */
#ifdef VMWAREFB_TEST_INIT_FAILURE
static BOOL initFailure(IOConfigTable *configuration,const char *stage)
{
    const char *value=[configuration valueForStringKey:"VMWareFB Test Failure"];
    if(value && !strcmp(value,stage)) {
        IOLog("VMWareFBTest: failure at %s\n",stage);return YES;
    }
    return NO;
}
#else
#define initFailure(configuration,stage) NO
#endif

- initFromDeviceDescription: deviceDescription
{
	IODisplayInfo *displayInfo;		// selected display info
	const IORange *range;					// framebuffer and fifo memory range
	BOOL validModes[modeTableCount]; // flags for checking valid modes
	int loop;											// loop variable
	const char *accelString;
    const char *cacheString;
    IOCache framebufferCache = IO_WriteThrough;
    unsigned framebufferCacheFlags = IO_DISPLAY_CACHE_WRITETHROUGH;
	IOConfigTable *configuration;	// config table for this driver instance

	// VMWare register values
	int maxWidth;									// maximum width as reported by device
	int maxHeight;								// maximum height as reported by device
	int bitsPerPixel;
	int depth;
	CARD32 redMask;
	CARD32 greenMask;
	CARD32 blueMask;
	int fbOffset;
	int bytesPerLine;
    unsigned framebufferSize;
	// vmwareCapability is an int i-var

	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: initFromDeviceDescription.\n");
#endif
    }

	if([super initFromDeviceDescription:deviceDescription] == nil)
	{
		return [super free];
	}

	fifo = NULL;

	/*
	 * Get the index and value registers into our i-vars.
	 */
	if( [ isa getIndexRegister: &indexReg valueRegister: &valueReg
						 withDeviceDescription: deviceDescription ]
		!= IO_R_SUCCESS)
	{
		IOLog("VMWareFB: problem getting index and value registers.\n");
		return [self free];
	}

	/* Preserve the boot console's mode for any initialization unwind. */
    savedEnable=[self readRegister:SVGA_REG_ENABLE];
    savedConfig=[self readRegister:SVGA_REG_CONFIG_DONE];
    savedWidth=[self readRegister:SVGA_REG_WIDTH];
    savedHeight=[self readRegister:SVGA_REG_HEIGHT];
    savedBpp=[self readRegister:SVGA_REG_BITS_PER_PIXEL];
    savedGuest=[self readRegister:SVGA_REG_GUEST_ID];
    savedCursor=[self readRegister:SVGA_REG_CURSOR_ON];
    hardwareStateSaved=YES;
#ifdef VMWAREFB_TEST_INIT_FAILURE
    IOLog("VMWareFBTest: saved mode %ux%u bpp %u enable %u config %u\n",
          savedWidth,savedHeight,savedBpp,savedEnable,savedConfig);
#endif

	/* Read the capabilities to determine maximum width and height.
	 * We will use this information to eliminate some modes.
	 */
	maxWidth = [self readRegister: SVGA_REG_MAX_WIDTH ];
	maxHeight = [self readRegister: SVGA_REG_MAX_HEIGHT ];
	vmwareCapability = [self readRegister: SVGA_REG_CAPABILITIES ];

	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: capabilities: maxWidth=%d, maxHeight=%d, vmwareCapability=%d\n",
		maxWidth, maxHeight, vmwareCapability);
#endif
    }

	/* special handling needed for bits per pixel.
	 * In any case, it always ends up being the host
	 * machine's bpp.
	 */
	if(vmwareCapability & SVGA_CAP_8BIT_EMULATION)
	{
		{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: SVGA_CAP_8BIT_EMULATION: bits-per-pixel == host-bits-per-pixel\n");
#endif
    }

		bitsPerPixel = [self readRegister: SVGA_REG_HOST_BITS_PER_PIXEL ];

		if(bitsPerPixel != 8 && bitsPerPixel != 16 && bitsPerPixel != 32)
		{
			// OpenStep only supports 8, 16 or 32bpp
			// since this vmware system can do 8-bit, then change to 8
			IOLog("VMWareFB: using 8 bit emulation because host bpp [%d] is unsupported. Suggest you change host display mode.\n",
				bitsPerPixel);

			bitsPerPixel = 8;
		}

		deviceConfigured=YES;
		[self writeRegister: SVGA_REG_BITS_PER_PIXEL value: bitsPerPixel ];
	}
	else
	{
		bitsPerPixel = [self readRegister: SVGA_REG_BITS_PER_PIXEL ];
	}

	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: first bits-per-pixel: %d\n", bitsPerPixel);
#endif
    }

	/* report the guest OS */
	deviceConfigured=YES;
	[self writeRegister: SVGA_REG_GUEST_ID value: GUEST_OS_OTHER];

	/* Get the acceleration flag from the config table, and set the
	 * acceleration i-var to one of our acceleration values.
	 */
	configuration = [deviceDescription configTable];
	accelString = [configuration valueForStringKey: VMACCELERATION_KEY];

	acceleration = DEFAULT_ACCELERATION;
    if(initFailure(configuration,"Lock")) return [self free];
    fifoLock = [[NXLock alloc] init];
    if(!fifoLock) return [self free];
    if(accelString && !strcmp(accelString,VMACCELERATION_NONE)) acceleration=NO_ACCELERATION;
    else if(accelString && !strcmp(accelString,VMACCELERATION_CURSOR)) acceleration=CURSOR_ACCELERATION;
    stopping = NO; active = NO; refreshRunning = NO;
    blitCount = 0; updateCount = 0;
    fillCount=0;
    damagePending=NO;safetyTicks=0;
    pollCount = requestedRows = updatedRows = fullUpdates = 0;
    refreshInterval = 16;
    damageTracking=YES;
    cursorKnown=NO;
    memset(cursorEligible,0,sizeof(cursorEligible));
    hardwareCursor=NO;hardwareFrame=~0U;cursorDefinitions=cursorMoves=cursorRefreshRequests=0;fillEnabled=YES;
    if(initFailure(configuration,"Modes")) return [self free];
    driverModes = IOMalloc(sizeof(modeTable));
    if (!driverModes) return [self free];
    memcpy(driverModes,modeTable,sizeof(modeTable));
    for (loop=0;loop<modeTableCount;loop++) {
        if (acceleration==DEFAULT_ACCELERATION && (vmwareCapability & SVGA_CAP_RECT_COPY))
            driverModes[loop].flags |= IO_DISPLAY_CAN_BLIT;
    }

	range=[deviceDescription memoryRangeList];
    framebufferSize=range[FB_MEMRANGE].size;

	/* Eliminate modes that exceed dimensions or available framebuffer RAM. */
	for( loop = 0; loop < modeTableCount; loop++ )
	{
		if(( modeTable[loop].width > maxWidth )
			|| ( modeTable[loop].height > maxHeight )
            || !vmwareFramebufferFits(framebufferSize,0,modeTable[loop].width*(bitsPerPixel/8),
                 modeTable[loop].width,modeTable[loop].height,bitsPerPixel))
		{
			validModes[loop] = NO;
		}
		else
		{
			validModes[loop] = YES;
		}
	}

	/* selectedMode is a driver-define instance variable */
	selectedMode = [self selectMode:driverModes
											 count: modeTableCount
											 valid: validModes];

	if(selectedMode < 0)
	{
		IOLog("%s: Sorry, can not use requested display mode.\n",
			[self name]);

		for(loop=0;loop<modeTableCount && !validModes[loop];loop++);
        if(loop==modeTableCount) return [self free];
        selectedMode=loop;
	}

	/* get our display info */
	displayInfo = [self displayInfo];
	*displayInfo = driverModes[selectedMode];

	/* Set the width and height registers from the selected
	 * mode. This will give us framebuffer offset and
	 * bytes per line, and other value, with which we can
	 * change the displayInfo struct.
	 */
	deviceConfigured=YES;
	[self writeRegister: SVGA_REG_ENABLE value: 0];	// in-case
	[self writeRegister: SVGA_REG_WIDTH value: displayInfo->width];
	[self writeRegister: SVGA_REG_HEIGHT value: displayInfo->height];

	fbOffset = [self readRegister: SVGA_REG_FB_OFFSET];

	if(fbOffset > 0)
	{
		IOLog("VMWareFB: nonzero framebuffer offset is unsupported\n");
        return [self free];
	}

	bytesPerLine = [self readRegister: SVGA_REG_BYTES_PER_LINE];

	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: bytes-per-line: %d\n", bytesPerLine);
#endif
    }

	if([self readRegister: SVGA_REG_PSEUDOCOLOR] == 1)
	{
		// FIXME: Supporting color mapped mode should be pretty simple.
		// FIXME: It should just be a matter of implementing the transfer
		// FIXME: table stuff.
		// FIXME: Implement this feature some day.
		// Bill Bereza 2002-02-13
		IOLog("VMWareFB: Colormapped mode not supported! Suggest you change host display mode.\n");
		return [self free];
	}

	/* Re-read bitsPerPixel. The README says to. */
	bitsPerPixel = [self readRegister: SVGA_REG_BITS_PER_PIXEL ];

	redMask = [self readRegister: SVGA_REG_RED_MASK];
	greenMask = [self readRegister: SVGA_REG_GREEN_MASK];
	blueMask = [self readRegister: SVGA_REG_BLUE_MASK];

	depth = [self readRegister: SVGA_REG_DEPTH];

	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: bits-per-pixel: %d\n", bitsPerPixel);
#endif
    }
	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: redMask: %08x\n", redMask);
#endif
    }
	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: greenMask: %08x\n", greenMask);
#endif
    }
	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: blueMask: %08x\n", blueMask);
#endif
    }
	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: depth: %d\n", depth);
#endif
    }

	if(bitsPerPixel != 8 && bitsPerPixel != 16 && bitsPerPixel != 32)
	{
		// OpenStep only supports 8, 16 or 32bpp
		IOLog("VMWareFB: Unsupported bits per pixel [%d]. Suggest you change host display mode.\n",
			bitsPerPixel);
		return [self free];
	}

	if(!vmwareFramebufferFits(framebufferSize,(unsigned)fbOffset,(unsigned)bytesPerLine,
                              displayInfo->width,displayInfo->height,bitsPerPixel)) {
        IOLog("VMWareFB: selected framebuffer layout exceeds mapped memory\n");
        return [self free];
    }

	/*
	 * In certain cases, the Windows host appears to
	 * report 16 bpp and 16 depth but 555 weight.  Just
	 * silently convert it to depth of 15.
	 */
	if(depth == 16
		&& bitsPerPixel == 16
		&& vmwareCalculateWeight(greenMask) == 5)
	{
		depth = 15;
	}

	/*
	 * There is no 32 bit depth, apparently it can get
	 * reported this way sometimes on the Windows host.
	 */
	if(depth == 32 && bitsPerPixel == 32)
	{
		depth = 24;
	}

	/* modify display info using bytesPerLine, depth, and color masks. */

	/* bytesPerLine should be the same as IODisplayInfo rowBytes */
	displayInfo->rowBytes = bytesPerLine;

	/* Find the right IOBitsPerPixel value from depth.
	 * What the VMWare device calls depth, NextStep calls IOBitsPerPixel.
	 */
	switch(depth)
	{
	case 8:
		displayInfo->bitsPerPixel = IO_8BitsPerPixel;
		break;
	case 12:
		displayInfo->bitsPerPixel = IO_12BitsPerPixel;
		break;
	case 16:
		// probably a 565 color weight
		IOLog("VMWareFB: WARNING. 16 bit depth. Suggest you change host display mode.\n");

		if(redMask == 0xf800 && greenMask == 0x7e0 && blueMask == 0x1f)
		{
			// yup
			IOLog("VMWareFB: WARNING. Hacking around 565 color weight.");
			greenMask = 0x7c0;				// ignore LSB
		}
		// no-break we will use 15 bits per pixel mode
	case 15:
		displayInfo->bitsPerPixel = IO_15BitsPerPixel;
		break;
	case 24:
		displayInfo->bitsPerPixel = IO_24BitsPerPixel;
		break;
	default:
		IOLog("VMWareFB: Unsupported depth [%d] reported from VMWare device. Suggest you change host display mode.\n",
			depth);
		return [self free];
		break;
	}

	/* Use bits per-pixel and color masks to generate a pixel
	 * encoding string.
	 */
	[self setPixelEncoding: displayInfo->pixelEncoding
				bitsPerPixel: bitsPerPixel
				redMask: redMask
				greenMask: greenMask
				blueMask: blueMask];

	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: pixel encoding [%s]\n", displayInfo->pixelEncoding);
#endif
    }

	/* Get memory ranges from device description */
	range = [deviceDescription memoryRangeList];

	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: framebuffer range: 0x%08x-0x%08x\n",
		range[FB_MEMRANGE].start,
		range[FB_MEMRANGE].start +range[FB_MEMRANGE].size);
#endif
    }

	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: framebuffer size: 0x%08x\n",
		range[FB_MEMRANGE].size);
#endif
    }

    /* IOCache and IODisplayInfo cache flags are different enumerations.
     * Passing IO_DISPLAY_CACHE_WRITETHROUGH (0) here selected IO_CacheOff.
     * QEMU's virtual VRAM is coherent host RAM; CopyBack is selected by
     * the bundled configuration. Preserve conservative mapping for older
     * instance tables that do not specify a cache policy. */
    cacheString = [configuration valueForStringKey:"Framebuffer Cache"];
    if (cacheString && !strcmp(cacheString,"CopyBack")) {
        framebufferCache = IO_CopyBack;
        framebufferCacheFlags = IO_DISPLAY_CACHE_COPYBACK;
    } else if (cacheString && !strcmp(cacheString,"Off")) {
        framebufferCache = IO_CacheOff;
        framebufferCacheFlags = IO_DISPLAY_CACHE_OFF;
    }
    displayInfo->flags = (displayInfo->flags & ~IO_DISPLAY_CACHE_MASK) |
                         framebufferCacheFlags;
    {
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: framebuffer cache mode %u, display flags %x\n",
          (unsigned)framebufferCache, displayInfo->flags);
#endif
    }
	if(initFailure(configuration,"Framebuffer")) return [self free];
	/* map frame buffer. */
	if( [self mapMemoryRange: FB_MEMRANGE
						to: (vm_address_t *)&(displayInfo->frameBuffer)
						findSpace: YES
						cache: framebufferCache] != IO_R_SUCCESS)
	{
		IOLog("VMWareFB: problem mapping framebuffer.\n");
		return [self free];
	}

	// 2002-02-14: old way of mapping frame buffer
	//displayInfo->frameBuffer = (void *)
	//	[self mapFrameBufferAtPhysicalAddress: range[FB_MEMRANGE].start
	//				length: range[FB_MEMRANGE].size ];


	if(displayInfo->frameBuffer == 0)
	{
		IOLog("VMWareFB: couldn't map frame buffer memory!\n");
		return [self free];
	}

    framebufferMapped=YES;
    if(initFailure(configuration,"FIFO")) return [self free];
    fifoLength = range[FIFO_MEMRANGE].size;
    if (fifoLength < 16 + 10240 ||
        [self mapMemoryRange:FIFO_MEMRANGE to:(vm_address_t *)&fifo
            findSpace:YES cache:IO_CacheOff] != IO_R_SUCCESS) {
        IOLog("VMWareFB: cannot map a valid command FIFO\n");
        return [self free];
    }
    displayInfo->flags &= ~IO_DISPLAY_CAN_BLIT;
    if (acceleration==DEFAULT_ACCELERATION && (vmwareCapability & SVGA_CAP_RECT_COPY))
        displayInfo->flags |= IO_DISPLAY_CAN_BLIT;

	initializationComplete=YES;
	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: initialized.\n");
#endif
    }
	#ifdef VMWAREFB_DEBUG
    [self logInfo];
#endif
    IOLog("VMWareFB: ready, %ux%u, %u bits per pixel\n",
          displayInfo->width, displayInfo->height, bitsPerPixel);

	return self;
}

/*
 * Configure display to enter advanced framebuffer mode.
 *
 * 1. Enable SVGA.
 *    Set SVGA_REG_ENABLE to 1
 *    (Set to 0 to disable (to enable VGA))
 *
 * 2. Initialize the command FIFO. (See README)
 *
 * 3. Set SVGA_REG_CONFIG_DONE to 1 (Set to 0 to stop the device reading FIFO)
 */
static void refreshThread(void *arg)
{
    [(VMWareFB *)arg refresh];
    IOExitThread();
}

- (void)enterLinearMode
{
    [self disableHardwareCursor];
    [fifoLock lock];
    [self writeRegister:SVGA_REG_CONFIG_DONE value:0];
    fifo[SVGA_FIFO_MIN] = 16;
    fifo[SVGA_FIFO_MAX] = fifoLength & ~3;
    fifo[SVGA_FIFO_NEXT_CMD] = 16;
    fifo[SVGA_FIFO_STOP] = 16;
    [self writeRegister:SVGA_REG_CONFIG_DONE value:1];
    [self writeRegister:SVGA_REG_ENABLE value:1];
    damagePending=YES;damageLeft=damageTop=0;
    damageRight=[self displayInfo]->width;damageBottom=[self displayInfo]->height;
    active = YES;
    [fifoLock unlock];
    if (!refreshRunning) {
        refreshRunning = YES;
        if (!IOForkThread(refreshThread,self)) refreshRunning = NO;
    }
    {
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: SVGA enabled, FIFO %lu bytes, blit capability %d\n",
        fifoLength,!!(vmwareCapability & SVGA_CAP_RECT_COPY));
#endif
    }
}

- refresh
{
    ns_time_t timestamp;
    unsigned deadline;
    IOGetTimestamp(&timestamp);deadline=(unsigned)timestamp;
    while (!stopping) {
        unsigned period;
        int remaining;
        if (active) [self flushDamage];
        /* Cursor shared memory belongs to the event-driver connection.
         * Never access it from a timer after WindowServer disconnects. */
        IOGetTimestamp(&timestamp);
        if(!damageTracking) {
            /* Retain the original policy for diagnostic A/B comparisons. */
            deadline=(unsigned)timestamp;IOSleep(refreshInterval);
            continue;
        }
        period=refreshInterval*1000000;
        deadline+=period;
        remaining=(int)(deadline-(unsigned)timestamp);
        /* Subtract work and previous sleep overshoot from the next wait.
         * Low-word modular arithmetic is safe for these <=1 second periods.
         * Skip missed deadlines rather than running a catch-up busy loop. */
        if(remaining<=0 || remaining>(int)period) {
            deadline=(unsigned)timestamp;remaining=1000000;
        }
        IOSleep(remaining>=1000000 ? remaining/1000000 : 1);
    }
    refreshRunning = NO;
    return self;
}

- (void)revertToVGAMode
{
    [self disableHardwareCursor];
    [fifoLock lock];
    active = NO;
    [self writeRegister:SVGA_REG_CONFIG_DONE value:0];
    [self writeRegister:SVGA_REG_ENABLE value:0];
    [fifoLock unlock];
    [super revertToVGAMode];
}

/* Kernel cursor writes do not pass through WindowServer's composite hook.
 * The stock 4.2 cursor is 16x16; leave a conservative margin for its hotspot. */
- (void)damageCursorAt:(Point *)point
{
    IODisplayInfo *info=[self displayInfo];
    int left=point->x-32,top=point->y-32,right=point->x+32,bottom=point->y+32;
    if(left<0) left=0;if(top<0) top=0;
    if(right>(int)info->width) right=info->width;
    if(bottom>(int)info->height) bottom=info->height;
    if(right>left && bottom>top) [self damageX:left y:top width:right-left height:bottom-top];
}

- moveCursor:(Point *)point frame:(int)frame token:(int)token
{
    id result=[super moveCursor:point frame:frame token:token];
    [self syncHardwareCursor];
    if(!hardwareCursor) {
        if(cursorKnown) [self damageCursorAt:&lastCursor];
        [self damageCursorAt:point];
    }
    lastCursor=*point;cursorKnown=YES;
    return result;
}

- showCursor:(Point *)point frame:(int)frame token:(int)token
{
    id result=[super showCursor:point frame:frame token:token];
    [self syncHardwareCursor];
    if(!hardwareCursor) {
        if(cursorKnown) [self damageCursorAt:&lastCursor];
        [self damageCursorAt:point];
    }
    lastCursor=*point;cursorKnown=YES;
    return result;
}

- hideCursor:(int)token
{
    id result=[super hideCursor:token];
    [self syncHardwareCursor];
    if(!hardwareCursor && cursorKnown) [self damageCursorAt:&lastCursor];
    return result;
}

- free
{
    IODisplayInfo *info;
    IODisplayInfo *modes=driverModes;
    id lock=fifoLock;
    id result;
    #ifdef VMWAREFB_TEST_INIT_FAILURE
    IOLog("VMWareFBTest: unwind lock %u modes %u framebuffer %u fifo %u configured %u\n",
          lock!=nil,modes!=0,framebufferMapped,fifo!=0,deviceConfigured);
#endif
    stopping=YES;
    while(refreshRunning) IOSleep(10);
    active=NO;
    if(deviceConfigured) {
        [self disableHardwareCursor];
        [self writeRegister:SVGA_REG_CONFIG_DONE value:0];
        [self writeRegister:SVGA_REG_ENABLE value:0];
        if(!initializationComplete && hardwareStateSaved) {
            [self writeRegister:SVGA_REG_WIDTH value:savedWidth];
            [self writeRegister:SVGA_REG_HEIGHT value:savedHeight];
            [self writeRegister:SVGA_REG_BITS_PER_PIXEL value:savedBpp];
            [self writeRegister:SVGA_REG_GUEST_ID value:savedGuest];
            [self writeRegister:SVGA_REG_ENABLE value:savedEnable];
            [self writeRegister:SVGA_REG_CONFIG_DONE value:savedConfig];
            [self writeRegister:SVGA_REG_CURSOR_ON value:savedCursor];
        }
        deviceConfigured=NO;
    }
    if(fifo) {
        [self unmapMemoryRange:FIFO_MEMRANGE from:(vm_address_t)fifo];
        fifo=0;
    }
    if(framebufferMapped) {
        info=[self displayInfo];
        [self unmapMemoryRange:FB_MEMRANGE from:(vm_address_t)info->frameBuffer];
        info->frameBuffer=0;framebufferMapped=NO;
    }
    driverModes=0;
    result=[super free];
    [lock free];
    if(modes) IOFree(modes,sizeof(modeTable));
#ifdef VMWAREFB_TEST_INIT_FAILURE
    IOLog("VMWareFBTest: unwind complete\n");
#endif
    return result;
}

/* disabled to be removed when updating fully implemented

- (port_t) devicePort
{
	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: devicePort\n");
#endif
    }
	return [super devicePort];
}

- hideCursor: (int) token
{
	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: hideCursor\n");
#endif
    }
	return [super hideCursor: token];
}

- moveCursor: (Point *)cursorLoc
			 frame: (int) frame
			 token: (int) token
{
	[self updateFullScreen];
	return [super moveCursor: cursorLoc
								frame: frame
								token: token];
}


- setBrightness: (int) level
					token: (int) token
{
	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: setBrightness\n");
#endif
    }
	return [super setBrightness: level
								token: token];
}


- showCursor: (Point *)cursorLocation
			 frame: (int) frame
			 token: (int) token
{
	{
#ifdef VMWAREFB_DEBUG
    IOLog("VMWareFB: showCursor\n");
#endif
    }
	return [super showCursor: cursorLocation
								frame: frame
								token: token];
}
*/

@end

/* OPENSTEP DriverKit loader metadata. */
kern_server_t VMWareFB_instance;
@interface VMWareFBKernelServerInstance : Object
@end
@implementation VMWareFBKernelServerInstance
+ (kern_server_t *)kernelServerInstance { return &VMWareFB_instance; }
@end
@interface VMWareFBVersion : IODevice
@end
@implementation VMWareFBVersion
+ (int)driverKitVersionForVMWareFB { return IO_DRIVERKIT_VERSION; }
@end
