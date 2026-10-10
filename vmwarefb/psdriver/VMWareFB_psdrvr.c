/* Experimental OPENSTEP 4.2/i386 WindowServer adapter.
 * Layout is recovered from the exported MPStart and generic driver table.
 * No WindowServer executable bytes are modified.
 */

extern int MPStart(void *driver);
extern int GenDrvComposite(void *,void *,void *);
extern void *_bm38XXXX[];
#ifdef VMWAREFB_UPLOAD
extern void *_bm38[];
#endif
extern unsigned BM38XXXXredShift,BM38XXXXgreenShift,BM38XXXXblueShift,BM38XXXXalphaShift;
extern int DevPrimIsRect(void *);
extern int GenDrvMark(void *,unsigned,void *,void *,void *);
extern void MPHideCursor(void *);
extern void MPShowCursor(void *);
extern void MPObscureCursor(void *);
extern void MPRevealCursor(void *);
extern void MPShieldCursor(void *,void *);
extern void MPUnshieldCursor(void *);
extern int MPSetCursor(void *,void *,unsigned,unsigned,void *);
extern void SysHideCursor(void *);
extern void SysShowCursor(void *);
extern void ev_lock(void *);
extern void ev_unlock(void *);
extern int os_fprintf(void *,const char *,...);
extern void *os_stderr;
extern unsigned device_master_self(void);
extern int _IOLookupByDeviceName(unsigned,const char *,unsigned *,char *);
extern int _IOSetIntValues(unsigned,unsigned,const char *,int *,unsigned);
static void *traceFile(void)
{
#ifdef VMWAREFB_TRACE
    return os_stderr;
#else
    return 0;
#endif
}
static void *functions[23];
static unsigned composites,screenCopies;
#ifdef VMWAREFB_UPLOAD
static unsigned uploads,convertedUploads;
#endif
/* Optional workload profiling. TSC deltas include scheduling and IPC waits;
 * they are elapsed guest ticks, not CPU time or monitor presentation rates.
 * Default builds do not add counters, clock reads, or profile output. */
#ifdef VMWAREFB_PROFILE
 typedef unsigned long long ProfileTicks;
 typedef struct {
     unsigned calls,pixels;
     ProfileTicks render,damage;
 } CompositeProfile;
 static CompositeProfile profiles[256];
 static unsigned profileSamples;
 static ProfileTicks profileClock(void)
 {
     unsigned lo,hi;
     __asm__ volatile("rdtsc" : "=a"(lo),"=d"(hi) : : "memory");
     return ((ProfileTicks)hi<<32)|lo;
 }
 static void profileComposite(unsigned flags,unsigned pixels,
                              ProfileTicks render,ProfileTicks update)
 {
     CompositeProfile *p=&profiles[flags];unsigned i;
     p->calls++;p->pixels+=pixels;p->render+=render;p->damage+=update;
     if(++profileSamples%256) return;
#ifdef VMWAREFB_UPLOAD
     os_fprintf(os_stderr,"VMWareUploads: samples=%u converted=%u\n",uploads,convertedUploads);
#endif
     for(i=0;i<256;i++) if(profiles[i].calls) {
         p=&profiles[i];
         os_fprintf(os_stderr,"VMWareProfile: sample=%u flags=%02x calls=%u pixels=%u render=%08x%08x damage=%08x%08x\n",
             profileSamples,i,p->calls,p->pixels,
             (unsigned)(p->render>>32),(unsigned)p->render,
             (unsigned)(p->damage>>32),(unsigned)p->damage);
     }
 }
#endif
static unsigned master,display;
static int ready;
/* Observe userspace hide/show/shield changes after the stock semaphore
 * operations. The kernel timer must not poll an event mapping's lifetime. */
static unsigned notifiedFrame,notifiedVisible;
static int cursorStateKnown;
static void cursorRefresh(void *device)
{
    unsigned char *shared=*(unsigned char **)((unsigned char *)device+0x28);
    unsigned frame,visible;
    if(!ready || !shared) return;
    ev_lock(shared+4);frame=*(unsigned *)shared;visible=shared[8]==0;ev_unlock(shared+4);
#ifndef VMWAREFB_NO_CURSOR_COALESCE
    /* Movement is handled by kernel event callbacks. Repeated shield calls
     * outside the cursor do not change its frame or visibility. */
    if(cursorStateKnown && frame==notifiedFrame && visible==notifiedVisible) return;
#endif
    if(!_IOSetIntValues(master,display,"VMWareCursorRefresh",0,0)) {
        notifiedFrame=frame;notifiedVisible=visible;cursorStateKnown=1;
    }
}
static void hideCursor(void *device) {MPHideCursor(device);cursorRefresh(device);}
static void showCursor(void *device) {MPShowCursor(device);cursorRefresh(device);}
static void obscureCursor(void *device) {MPObscureCursor(device);cursorRefresh(device);}
static void revealCursor(void *device) {MPRevealCursor(device);cursorRefresh(device);}
static void shieldCursor(void *device,void *bounds) {MPShieldCursor(device,bounds);cursorRefresh(device);}
static void unshieldCursor(void *device) {MPUnshieldCursor(device);cursorRefresh(device);}
static int setCursor(void *device,void *bitmap,unsigned hotspot,unsigned frame,void *flags)
{
    static unsigned reports;
    int result=MPSetCursor(device,bitmap,hotspot,frame,flags);
    cursorStateKnown=0;
    if(ready && frame<4) {
        unsigned char *shared=*(unsigned char **)((unsigned char *)device+0x28);
        unsigned values[258],i;
        int uploaded,current;
        values[0]=frame;values[1]=hotspot;
        ev_lock(shared+4);
        for(i=0;i<256;i++) values[i+2]=((unsigned *)(shared+0x48+frame*1024))[i];
        current=*(unsigned *)shared==frame;
        if(current) SysHideCursor(device);
        uploaded=_IOSetIntValues(master,display,"VMWareCursorImage",(int *)values,258);
        if(!uploaded) for(i=0;i<256;i++) ((unsigned *)(shared+0x48+frame*1024))[i]=0;
        if(current) SysShowCursor(device);
        ev_unlock(shared+4);
        if(_IOSetIntValues(master,display,"VMWareCursorRefresh",(int *)values,0) && !uploaded) {
            ev_lock(shared+4);
            current=*(unsigned *)shared==frame;
            if(current) SysHideCursor(device);
            for(i=0;i<256;i++) ((unsigned *)(shared+0x48+frame*1024))[i]=values[i+2];
            if(current) SysShowCursor(device);
            ev_unlock(shared+4);
            _IOSetIntValues(master,display,"VMWareCursorFallback",(int *)values,1);
        }
    }
    if(frame<4 && reports++<12) {
        unsigned char *shared=*(unsigned char **)((unsigned char *)device+0x28);
        unsigned *pixels=(unsigned *)(shared+0x48+frame*1024);
        unsigned i,zero=0,opaque=0,partial=0;
        for(i=0;i<256;i++) {
            unsigned alpha=pixels[i]>>24;
            if(!alpha) zero++;else if(alpha==255) opaque++;else partial++;
        }
        if(traceFile()) os_fprintf(traceFile(),"VMWarePS: cursor frame=%u hotspot=%x alpha0=%u alpha255=%u partial=%u pixels=%x,%x,%x,%x\n",frame,hotspot,zero,opaque,partial,pixels[0],pixels[17],pixels[34],pixels[255]);
    }
    return result;
}
static void damage(short *bounds)
{
    int values[4];
    if(!ready) return;
    if(bounds) {
        values[0]=bounds[0]<0 ? 0 : bounds[0];
        values[1]=bounds[2]<0 ? 0 : bounds[2];
        values[2]=bounds[1]-values[0];values[3]=bounds[3]-values[1];
        if(values[2]<=0 || values[3]<=0) return;
    } else {values[0]=values[1]=0;values[2]=values[3]=32767;}
    _IOSetIntValues(master,display,"VMWareDamage",values,4);
}
static int solidFill(void *bag,unsigned type,unsigned *ctx,short *bounds)
{
    unsigned *bitmap,*dp,*clip,*alpha;
    unsigned char *flags;
    int rectangle[4],values[5],i;
    if(!ready || type!=1 || !ctx || !bounds || !ctx[1] || ctx[10] || ctx[11]) return 0;
    bitmap=*(unsigned **)((unsigned char *)bag+0x18);
    /* Only the recovered 4.2/i386 RGB framebuffer class, with native
     * channel shifts and no pending bitmap format conversion. */
    if(!bitmap || (void *)bitmap[0]!=(void *)_bm38XXXX ||
       BM38XXXXredShift!=16 || BM38XXXXgreenShift!=8 ||
       BM38XXXXblueShift!=0 || BM38XXXXalphaShift!=24) return 0;
    flags=(unsigned char *)bitmap;
    if(flags[0x1d]&3) return 0;
    dp=(unsigned *)ctx[1];clip=(unsigned *)ctx[2];
    if(dp[3] || !DevPrimIsRect(dp)) return 0;
    if(clip && (clip[3] || !DevPrimIsRect(clip))) return 0;
    /* The bitmap's constant-color setup reads RGB from MarkInfo+12 and
     * alpha from **(MarkInfo+20)+4. Reject partial alpha before submission. */
    if(!ctx[8] || !*(unsigned *)ctx[8]) return 0;
    alpha=(unsigned *)*(unsigned *)ctx[8];
    if(((unsigned char *)alpha)[4]!=255) return 0;
    for(i=0;i<4;i++) rectangle[i]=((short *)(dp+1))[i]+(int)ctx[12+(i>=2)];
    if(clip) {
        short *c=(short *)(clip+1);
        for(i=0;i<4;i++) {
            int edge=c[i]+(int)ctx[12+(i>=2)];
            if((!(i&1) && edge>rectangle[i]) || ((i&1) && edge<rectangle[i])) rectangle[i]=edge;
        }
    }
    for(i=0;i<4;i++) if((!(i&1) && bounds[i]>rectangle[i]) || ((i&1) && bounds[i]<rectangle[i])) rectangle[i]=bounds[i];
    if(rectangle[0]<0 || rectangle[2]<0 || rectangle[1]<=rectangle[0] || rectangle[3]<=rectangle[2]) return 0;
    values[0]=rectangle[0];values[1]=rectangle[2];
    values[2]=rectangle[1]-rectangle[0];values[3]=rectangle[3]-rectangle[2];
    values[4]=((ctx[6]&255)<<16)|(ctx[6]&0xff00)|((ctx[6]>>16)&255);
    if(_IOSetIntValues(master,display,"VMWareFillRectangle",values,5)) return 0;
    /* Mirror only the generic bitmap dirty/data bookkeeping. */
    flags[0x1c]=(flags[0x1c]|4)&~0x40;
    return 1;
}
static int mark(void *bag,unsigned type,void *markContext,void *markBounds,void *clipBounds)
{
    static unsigned marks,smallMarks;
    int result;
    short rectangle[4];
    unsigned i;
    int haveBounds=markBounds && clipBounds;
    if(haveBounds) {
        short *a=markBounds,*b=clipBounds;
        for(i=0;i<4;i++) rectangle[i]=b[i];
        if(a[0]>rectangle[0]) rectangle[0]=a[0];
        if(a[1]<rectangle[1]) rectangle[1]=a[1];
        if(a[2]>rectangle[2]) rectangle[2]=a[2];
        if(a[3]<rectangle[3]) rectangle[3]=a[3];
    }
    if(type==1 && markBounds && clipBounds && (marks++<8 ||
       (((short *)clipBounds)[1]-((short *)clipBounds)[0]>=59 &&
        ((short *)clipBounds)[1]-((short *)clipBounds)[0]<=61 &&
        ((short *)clipBounds)[3]-((short *)clipBounds)[2]>=79 &&
        ((short *)clipBounds)[3]-((short *)clipBounds)[2]<=81 && smallMarks++<4))) {
        short *c=markBounds,*b=clipBounds;
        if(traceFile()) os_fprintf(traceFile(),"VMWarePS: mark clip=%d,%d,%d,%d bounds=%d,%d,%d,%d\n",c[0],c[1],c[2],c[3],b[0],b[1],b[2],b[3]);
    }
    if(type==1 && markContext) {
        static unsigned reports;
        unsigned *ctx=markContext;
        if(ctx[1] && DevPrimIsRect((void *)ctx[1]) && reports++<40) {
            unsigned *dp=(unsigned *)ctx[1];
            if(traceFile()) os_fprintf(traceFile(),"VMWarePS: rectangle context=%x,%x,%x,%x,%x,%x,%x,%x,%x,%x,%x,%x,%x,%x dp=%x,%x,%x,%x,%x,%x,%x,%x,%x\n",
              ctx[0],ctx[1],ctx[2],ctx[3],ctx[4],ctx[5],ctx[6],ctx[7],ctx[8],ctx[9],ctx[10],ctx[11],ctx[12],ctx[13],
              dp[0],dp[1],dp[2],dp[3],dp[4],dp[5],dp[6],dp[7],dp[8]);
        }
    }
    if(haveBounds && solidFill(bag,type,(unsigned *)markContext,rectangle)) return 0;
    result=GenDrvMark(bag,type,markContext,markBounds,clipBounds);
    if(type==1) damage(haveBounds ? rectangle : 0);
    return result;
}
#ifdef VMWAREFB_UPLOAD
/* Experimental native-format backing-store COPY. No offscreen SVGA command
 * exists for this source: copy process-memory rows into the mapped screen.
 * Keep the generic renderer for blending, conversion and unverified layouts. */
static int uploadCopy(unsigned char *op,short *dst)
{
    unsigned *d,*s;
    short *db,*sb,*src=(short *)(op+16);
    unsigned ds,ss,dn,sn,dp,sp,y,w,h;
    int convert;
    unsigned char *drow,*srow;
    if(!ready || !dst || op[8]!=0x21 || op[9]!=4 ||
       op[10]!=1 || op[11] || !((unsigned *)op)[0] ||
       !((unsigned *)op)[1] ||
       *(unsigned char *)((unsigned *)op)[0]!=0x67 ||
       *(unsigned char *)((unsigned *)op)[1]!=0x67) return 0;
    d=*(unsigned **)((unsigned char *)((unsigned *)op)[0]+0x18);
    s=*(unsigned **)((unsigned char *)((unsigned *)op)[1]+0x1c);
    if(!d || !s || d==s || (void *)d[0]!=(void *)_bm38XXXX ||
       ((void *)s[0]!=(void *)_bm38XXXX && (void *)s[0]!=(void *)_bm38) ||
       BM38XXXXredShift!=16 || BM38XXXXgreenShift!=8 ||
       BM38XXXXblueShift!=0 || BM38XXXXalphaShift!=24 ||
       (((unsigned char *)d)[0x1d]&3) ||
       (((unsigned char *)s)[0x1d]&3) ||
       !(((unsigned char *)d)[0x13]&4)) return 0;
    convert=(void *)s[0]==(void *)_bm38;
    db=(short *)(d+1);sb=(short *)(s+1);
    if(dst[0]<db[0] || dst[1]>db[1] || dst[2]<db[2] || dst[3]>db[3] ||
       src[0]<sb[0] || src[1]>sb[1] || src[2]<sb[2] || src[3]>sb[3] ||
       dst[1]<=dst[0] || dst[3]<=dst[2] ||
       src[1]-src[0]!=dst[1]-dst[0] || src[3]-src[2]!=dst[3]-dst[2] ||
       dst[0]-src[0]!=((short *)op)[6] ||
       dst[2]-src[2]!=((short *)op)[7]) return 0;
    ds=d[6];ss=s[6];dp=d[8];sp=s[8];
    if(db[1]<=db[0] || db[3]<=db[2] || sb[1]<=sb[0] || sb[3]<=sb[2] ||
       !ds || !ss || (ds&3) || (ss&3) || ds>65536 || ss>65536 ||
       ds<(unsigned)(db[1]-db[0])*4 || ss<(unsigned)(sb[1]-sb[0])*4 ||
       !dp || !sp) return 0;
    dn=ds*(unsigned)(db[3]-db[2]);sn=ss*(unsigned)(sb[3]-sb[2]);
    if(dn>0xffffffffU-dp || sn>0xffffffffU-sp ||
       !(dp+dn<=sp || sp+sn<=dp)) return 0;
    w=dst[1]-dst[0];h=dst[3]-dst[2];
    drow=(unsigned char *)dp+(dst[2]-db[2])*ds+(dst[0]-db[0])*4;
    srow=(unsigned char *)sp+(src[2]-sb[2])*ss+(src[0]-sb[0])*4;
    for(y=0;y<h;y++) {
        unsigned *to=(unsigned *)drow,*from=(unsigned *)srow,count=w;
        if(convert) {
            while(count--) {
                unsigned pixel=*from++;
                *to++=(pixel>>8)|(pixel<<24);
            }
        } else {
            __asm__ volatile("cld; rep; movsl" : "=D"(to),"=S"(from),"=c"(count) : "0"(to),"1"(from),"2"(count) : "memory","cc");
        }
        drow+=ds;srow+=ss;
    }
    ((unsigned char *)d)[0x1c]=(((unsigned char *)d)[0x1c]|4)&~0x40;
    uploads++;
    if(convert) convertedUploads++;
    return 1;
}
#endif
static int composite(void *operation,void *bounds,void *extra)
{
    unsigned char *op=operation;
    short *src=(short *)(op+16),*dst=bounds;
    /* First deliberately narrow case: an opaque, unscaled copy within
     * one screen bag. Reject every unverified operation layout. */
    if(ready && op[8]==0x11 && op[9]==3 && op[10]==1 && op[11]==0 &&
       ((unsigned *)op)[0]==((unsigned *)op)[1] &&
       src[1]-src[0]==dst[1]-dst[0] && src[3]-src[2]==dst[3]-dst[2] &&
       dst[0]-src[0]==((short *)op)[6] &&
       dst[2]-src[2]==((short *)op)[7]) {
        int values[6];
        values[0]=src[0];values[1]=src[2];
        values[2]=src[1]-src[0];values[3]=src[3]-src[2];
        values[4]=dst[0];values[5]=dst[2];
        if(!_IOSetIntValues(master,display,"IODisplayDoBlit",values,6)) {
            if(traceFile()) os_fprintf(traceFile(),"VMWarePS: accelerated screen copy\n");
            return 0;
        }
    }
    if(composites++<8 || (op[8]==0x11 && screenCopies++<32))
        if(traceFile()) os_fprintf(traceFile(),"VMWarePS: composite flags=%02x,%02x op=%u alpha=%u delta=%d,%d bags=%x,%x src=%d,%d,%d,%d dst=%d,%d,%d,%d\n",
            op[8],op[9],op[10],op[11],((short *)op)[6],((short *)op)[7],((unsigned *)op)[0],((unsigned *)op)[1],
            src[0],src[1],src[2],src[3],dst[0],dst[1],dst[2],dst[3]);
    {
        int screen=(op[8]&15)==1;
        short rectangle[4];unsigned i;
        int result;
#ifdef VMWAREFB_PROFILE
        ProfileTicks before,after,updated;
        unsigned profileFlags=op[8];
        static unsigned layoutReports;
        if(op[8]==0x21 && layoutReports++<8 &&
           ((unsigned *)op)[1] && *(unsigned char *)((unsigned *)op)[1]==0x67) {
            unsigned *d=*(unsigned **)((unsigned char *)((unsigned *)op)[0]+0x18);
            unsigned *s=*(unsigned **)((unsigned char *)((unsigned *)op)[1]+0x1c);
            if(d && s) os_fprintf(os_stderr,"VMWareLayout: op=%02x,%02x,%02x,%02x dst=%x,%x,%x,%x,%x,%x,%x,%x,%x,%x src=%x,%x,%x,%x,%x,%x,%x,%x,%x,%x\n",
                op[8],op[9],op[10],op[11],
                d[0],d[1],d[2],d[3],d[4],d[5],d[6],d[7],d[8],d[9],
                s[0],s[1],s[2],s[3],s[4],s[5],s[6],s[7],s[8],s[9]);
        }
#endif
        for(i=0;i<4;i++) rectangle[i]=dst[i];
#ifdef VMWAREFB_PROFILE
        before=profileClock();
#endif
#ifdef VMWAREFB_UPLOAD
        if(uploadCopy(op,dst)) result=0;
        else
#endif
        result=GenDrvComposite(operation,bounds,extra);
#ifdef VMWAREFB_PROFILE
        after=profileClock();
#endif
        if(screen) damage(rectangle);
#ifdef VMWAREFB_PROFILE
        updated=profileClock();
        profileComposite(profileFlags,
            rectangle[1]>rectangle[0] && rectangle[3]>rectangle[2] ?
            (unsigned)(rectangle[1]-rectangle[0])*(rectangle[3]-rectangle[2]) : 0,
            after-before,updated-after);
#endif
        return result;
    }
}
int Start(void *driver)
{
    unsigned i;
    int result=MPStart(driver);
    void **original=((void ***)driver)[3];
    if(result) return result;
    cursorStateKnown=0;
    if(original[0]!=(void *)GenDrvComposite) return result;
    {
        char kind[256];
        master=device_master_self();
        ready=!_IOLookupByDeviceName(master,"Display0",&display,kind);
    }
    for(i=0;i<23;i++) functions[i]=original[i];
    functions[0]=(void *)composite;
    if(original[4]==(void *)GenDrvMark) functions[4]=(void *)mark;
    if(original[12]==(void *)MPSetCursor) functions[12]=(void *)setCursor;
    if(original[13]==(void *)MPHideCursor) functions[13]=(void *)hideCursor;
    if(original[14]==(void *)MPShowCursor) functions[14]=(void *)showCursor;
    if(original[15]==(void *)MPObscureCursor) functions[15]=(void *)obscureCursor;
    if(original[16]==(void *)MPRevealCursor) functions[16]=(void *)revealCursor;
    if(original[17]==(void *)MPShieldCursor) functions[17]=(void *)shieldCursor;
    if(original[18]==(void *)MPUnshieldCursor) functions[18]=(void *)unshieldCursor;
    ((void ***)driver)[3]=functions;
    if(traceFile()) os_fprintf(traceFile(),"VMWarePS: attached generic display composite adapter\n");
    return result;
}
