/* MIT license. Single-consumer byte-stream utility, not a TTY.
 * Success of a write means local acceptance, not acknowledgment by the peer. */
#import <driverkit/IODeviceMaster.h>
#import <driverkit/return.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libc.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <errno.h>
#include <signal.h>

#define CONSOLE_LOCK "/usr/adm/virtio-console.lock"
static const char *consumerLock=CONSOLE_LOCK;
static volatile sig_atomic_t interrupted;
/* Diagnostics must not hang an otherwise bounded operation on a full stderr
 * pipe. A diagnostic may be dropped when its destination cannot accept it. */
static void diagnostic(const char *text)
{
    int flags=fcntl(2,F_GETFL,0);
    if(flags<0 || fcntl(2,F_SETFL,flags|O_NDELAY|FNOSPC))return;
    write(2,text,strlen(text));fcntl(2,F_SETFL,flags);
}
static void stopOperation(int signalNumber) { interrupted=signalNumber; }
static int expired(long deadline,unsigned idle)
{
    struct timeval now;
    if(interrupted || gettimeofday(&now,0))return 1;
    return now.tv_sec>=deadline || idle>=30000;
}
/* The root-owned, preinstalled inode is never unlinked or replaced while in use.
 * An advisory lock serializes cooperating utilities; raw RPC clients must obey
 * the same contract. O_RDONLY permits unprivileged readers without allowing
 * callers to modify the lock inode. */
static int acquireConsumer(void)
{
    struct stat before,after;int fd;
    if(lstat(consumerLock,&before) || (before.st_mode&S_IFMT)!=S_IFREG ||
       before.st_uid || before.st_nlink!=1 || (before.st_mode&022)) {
        diagnostic("Install a root-owned, non-writable console lock first\n");return -1;
    }
    fd=open(consumerLock,O_RDONLY|O_NDELAY);
    if(fd<0)return -1;
    if(fstat(fd,&after) || after.st_dev!=before.st_dev || after.st_ino!=before.st_ino ||
       (after.st_mode&S_IFMT)!=S_IFREG || after.st_uid || after.st_nlink!=1 ||
       (after.st_mode&022) || flock(fd,LOCK_EX|LOCK_NB)) {
        diagnostic("Console is busy or its lock inode is unsafe\n");close(fd);return -1;
    }
    return fd;
}
/* Nonblocking descriptor I/O replaces stdio buffering. Partial reads/writes,
 * pipe stalls, EOF and EPIPE are explicit, and the same deadline covers both
 * host transport and local descriptor waits. */
static IOReturn descriptorIO(int fd,unsigned char *bytes,unsigned count,int writing,
                            long deadline,unsigned *idle)
{
    unsigned offset=0;int n,ready;fd_set set;struct timeval wait;
    if(fd<0 || fd>=FD_SETSIZE)return IO_R_INVALID_ARG;
    while(offset<count) {
        if(expired(deadline,*idle))return IO_R_TIMEOUT;
        n=writing?write(fd,bytes+offset,count-offset):read(fd,bytes+offset,count-offset);
        if(n>0) { offset+=n;continue; }
        if(!n)return IO_R_IO;
        if(errno==EINTR)continue;
        if(errno!=EWOULDBLOCK && errno!=EAGAIN)return IO_R_IO;
        FD_ZERO(&set);FD_SET(fd,&set);wait.tv_sec=0;wait.tv_usec=100000;
        ready=select(fd+1,writing?0:&set,writing?&set:0,0,&wait);
        if(ready<0 && errno!=EINTR)return IO_R_IO;
        /* Count every wait, including spurious readiness, to retain a finite
         * bound if the wall clock moves backwards or the descriptor spins. */
        *idle+=ready==0?100:1;
    }
    return IO_R_SUCCESS;
}
int main(int argc,char **argv)
{
    id master=nil;IOString kind,name;IOParameterName readName,writeName;
    unsigned object,count,stats[12],generation=0,left=0,idle=0,portID=1;char *statsName="VirtioConsoleStats";int mode=0,exitCode=1,lockFD=-1,ioFD=-1,savedFlags=-1;
    unsigned char bytes[512];char message[512];IOReturn result=IO_R_NO_DEVICE;struct timeval now;long deadline;
    signal(SIGPIPE,SIG_IGN);signal(SIGINT,stopOperation);signal(SIGTERM,stopOperation);signal(SIGHUP,stopOperation);
    if(argc>=3 && !strcmp(argv[1],"--port")) {
        if(!strcmp(argv[2],"2")) { portID=2;statsName="VirtioConsoleStats2";consumerLock="/usr/adm/virtio-console2.lock"; }
        else if(strcmp(argv[2],"1")) { diagnostic("Port must be 1 or 2\n");return 2; }
        argc-=2;argv+=2;
    }
    if(portID==2 && argc>1 && !strcmp(argv[1],"--reset")) {
        diagnostic("Reset is controller-wide; use port 1 explicitly\n");return 2;
    }
    /* OPENSTEP protects setChar/setInt RPCs. Reject echo before its first
     * read, otherwise an unprivileged caller would consume input and only
     * discover the restriction when trying to transmit the reply. */
    if(geteuid()!=0 && argc>1 && (!strcmp(argv[1],"--write") ||
       !strcmp(argv[1],"--echo") || !strcmp(argv[1],"--reset"))) {
        diagnostic("--write, --echo and --reset require root on OPENSTEP\n");return 1;
    }
    master=[IODeviceMaster new];if(!master)return 1;
    for(object=0;object<256;object++)if([master lookUpByObjectNumber:object deviceKind:&kind deviceName:&name]==IO_R_SUCCESS && !strcmp(name,"VirtioConsole0"))break;
    if(object==256) { diagnostic("VirtioConsole0 not found\n");goto done; }
    #ifdef VIRTIO_CONSOLE_TESTING
    if(argc==2 && (!strcmp(argv[1],"--test-rx-completion") || !strcmp(argv[1],"--test-tx-completion"))) {
        stats[0]=!strcmp(argv[1],"--test-rx-completion")?1:2;
        result=[master setIntValues:stats forParameter:"VirtioConsoleTestFault" objectNumber:object count:1];exitCode=result?1:0;goto done;
    }
#endif
    if(argc==2 && !strcmp(argv[1],"--reset")) {
        lockFD=acquireConsumer();if(lockFD<0) { result=IO_R_BUSY;goto done; }
        stats[0]=1;result=[master setIntValues:stats forParameter:"VirtioConsoleReset" objectNumber:object count:1];exitCode=result?1:0;goto done;
    }
    count=12;result=[master getIntValues:stats forParameter:statsName objectNumber:object count:&count];if(result || count!=12)goto done;
    if(argc==2 && !strcmp(argv[1],"--stats")) {
        count=sprintf(message,"online=%u present=%u host_open=%u generation=%u rx_buffered=%u rx_reserved=%u tx_pending=%u received=%u accepted_tx=%u errors=%u resets=%u interrupts=%u\n",stats[0],stats[1],stats[2],stats[3],stats[4],stats[5],stats[6],stats[7],stats[8],stats[9],stats[10],stats[11]);
        ioFD=1;savedFlags=fcntl(ioFD,F_GETFL,0);
        if(savedFlags<0 || fcntl(ioFD,F_SETFL,savedFlags|O_NDELAY|FNOSPC) || gettimeofday(&now,0)) { result=IO_R_IO;goto done; }
        result=descriptorIO(ioFD,(unsigned char *)message,count,1,now.tv_sec+30,&idle);exitCode=result?1:0;goto done;
    }
    if(argc==3) {
        char *end;errno=0;left=strtoul(argv[2],&end,10);
        if(argv[2][0]>='0' && argv[2][0]<='9' && errno!=ERANGE && !*end && left && left<=16777216) {
            if(!strcmp(argv[1],"--read"))mode=1;
            if(!strcmp(argv[1],"--write"))mode=2;
            if(!strcmp(argv[1],"--echo"))mode=3;
        }
    }
    if(!mode) { diagnostic("Usage: virtio-console [--port 1|2] --stats | --reset | --read N | --write N | --echo N (1..16777216 bytes)\n");exitCode=2;goto done; }
    lockFD=acquireConsumer();if(lockFD<0) { result=IO_R_BUSY;goto done; }
    count=12;result=[master getIntValues:stats forParameter:statsName objectNumber:object count:&count];if(result || count!=12)goto done;
    if(mode==1 || mode==2) {
        ioFD=mode==1?1:0;savedFlags=fcntl(ioFD,F_GETFL,0);
        if(savedFlags<0 || fcntl(ioFD,F_SETFL,savedFlags|O_NDELAY|FNOSPC)) { result=IO_R_IO;goto done; }
    }
    if(!stats[0] || !stats[2]) { result=IO_R_NOT_READY;goto done; }
    generation=stats[3];sprintf(readName,portID==1?"VirtioConsoleRead.%08x":"VirtioConsoleRead2.%08x",generation);sprintf(writeName,portID==1?"VirtioConsoleWrite.%08x":"VirtioConsoleWrite2.%08x",generation);
    if(gettimeofday(&now,0)) { result=IO_R_IO;goto done; }deadline=now.tv_sec+30;
    while(left) {
        if(expired(deadline,idle)) { result=IO_R_TIMEOUT;goto done; }
        count=left>512?512:left;
        if(mode==2) {
            result=descriptorIO(ioFD,bytes,count,0,deadline,&idle);if(result)goto done;
        } else {
            result=[master getCharValues:bytes forParameter:readName objectNumber:object count:&count];
            if(result)goto done; /* Never trust returned count on an error RPC. */
            if(count>512 || count>left) { result=IO_R_IO;goto done; }
            if(!count) { idle++;usleep(1000);continue; }
        }
        if(mode==2 || mode==3) {
            for(;;) {
                result=[master setCharValues:bytes forParameter:writeName objectNumber:object count:count];
                if(result!=IO_R_BUSY)break;
                if(expired(deadline,++idle)) { result=IO_R_TIMEOUT;goto done; }
                usleep(1000);
            }
            if(result)goto done;
        } else {
            result=descriptorIO(ioFD,bytes,count,1,deadline,&idle);if(result)goto done;
        }
        left-=count;
    }
    exitCode=0;
done:
    if(savedFlags>=0 && ioFD>=0 && fcntl(ioFD,F_SETFL,savedFlags)) { result=IO_R_IO;exitCode=1; }
    if(lockFD>=0)close(lockFD);
    if(exitCode==1) { sprintf(message,"VirtioConsole operation failed: %d (remaining %u, generation %u); uncertain output is not replayed\n",result,left,generation);diagnostic(message); }
    [master free];return exitCode;
}
