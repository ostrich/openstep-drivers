/* MIT license. Shared by the standard agent and separate PTY daemon. */
#import <driverkit/IODeviceMaster.h>
#import <driverkit/return.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <libc.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <errno.h>
#include "console-transport.h"
/* OPENSTEP's SDK exposes this documented 01 flag only under _POSIX_SOURCE.
 * Keep the default NeXT/BSD declarations needed by the DriverKit interface. */
#ifndef FD_CLOEXEC
#define FD_CLOEXEC 01
#endif
void agent_transport_close(struct agent_transport *t)
{
    if(t->master)[(id)t->master free];
    if(t->lock_fd>=0 && (t->port==1 || t->port==2))close(t->lock_fd);
    memset(t,0,sizeof(*t));t->lock_fd=-1;
}
int agent_transport_open(struct agent_transport *t,unsigned port)
{
    const char *lock;struct stat before,after;id master;IOString kind,name;unsigned object;int fd;
    memset(t,0,sizeof(*t));t->lock_fd=-1;
    if(geteuid()!=0) { errno=EACCES;return -1; }
    if(port!=1 && port!=2) { errno=EINVAL;return -1; }
    lock=port==1?"/usr/adm/virtio-console.lock":"/usr/adm/virtio-console2.lock";
    if(lstat(lock,&before))return -1;
    if((before.st_mode&S_IFMT)!=S_IFREG || before.st_uid || before.st_nlink!=1 || (before.st_mode&022)) { errno=EACCES;return -1; }
    fd=open(lock,O_RDONLY|O_NDELAY);if(fd<0)return -1;
    if(fstat(fd,&after) || before.st_dev!=after.st_dev || before.st_ino!=after.st_ino ||
       (after.st_mode&S_IFMT)!=S_IFREG || after.st_uid || after.st_nlink!=1 || (after.st_mode&022)) {
        close(fd);errno=EACCES;return -1;
    }
    if(flock(fd,LOCK_EX|LOCK_NB)) { int saved=errno;close(fd);errno=saved;return -1; }
    if(fcntl(fd,F_SETFD,FD_CLOEXEC)) { int saved=errno;close(fd);errno=saved;return -1; }
    master=[IODeviceMaster new];if(!master) { close(fd);errno=ENOMEM;return -1; }
    for(object=0;object<256;object++)if([master lookUpByObjectNumber:object deviceKind:&kind deviceName:&name]==IO_R_SUCCESS && !strcmp(name,"VirtioConsole0"))break;
    if(object==256) { [master free];close(fd);errno=ENODEV;return -1; }
    t->master=master;t->object=object;t->port=port;t->lock_fd=fd;return 0;
}
int agent_transport_refresh(struct agent_transport *t,unsigned *stats)
{
    unsigned values[12],count=12,connected;IOReturn result;int changed;
    if(!t->master) { errno=ENODEV;return -1; }
    result=[(id)t->master getIntValues:values forParameter:t->port==1?"VirtioConsoleStats":"VirtioConsoleStats2" objectNumber:t->object count:&count];
    if(result || count!=12) { errno=EIO;return -1; }
    connected=values[0] && values[1] && values[2];
    changed=t->generation!=values[3] || t->connected!=connected;
    t->generation=values[3];t->connected=connected;
    if(stats)memcpy(stats,values,sizeof(values));return changed;
}
int agent_transport_read(struct agent_transport *t,unsigned char *bytes,unsigned *count)
{
    IOParameterName name;IOReturn result;unsigned wanted=*count;
    *count=0;
    if(!t->connected)return 2;
    if(!wanted || wanted>512) { errno=EINVAL;return -1; }
    sprintf(name,t->port==1?"VirtioConsoleRead.%08x":"VirtioConsoleRead2.%08x",t->generation);
    *count=wanted;result=[(id)t->master getCharValues:bytes forParameter:name objectNumber:t->object count:count];
    if(result) { *count=0;if(result==IO_R_NOT_READY)return 2;errno=EIO;return -1; }
    if(*count>wanted) { *count=0;errno=EIO;return -1; }
    return 0;
}
int agent_transport_write(struct agent_transport *t,unsigned char *bytes,unsigned count)
{
    IOParameterName name;IOReturn result;
    if(!t->connected)return 2;
    if(!count || count>512) { errno=EINVAL;return -1; }
    sprintf(name,t->port==1?"VirtioConsoleWrite.%08x":"VirtioConsoleWrite2.%08x",t->generation);
    result=[(id)t->master setCharValues:bytes forParameter:name objectNumber:t->object count:count];
    if(result==IO_R_BUSY)return 1;
    if(result==IO_R_NOT_READY)return 2;
    if(result) { errno=EIO;return -1; }
    return 0;
}
