/* MIT license. Invoke administration utilities so OPENSTEP performs its own
 * service termination and filesystem shutdown, rather than bypassing them. */
#include "native-shutdown.h"
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/time.h>
#include <errno.h>
#ifdef OPENSTEP_NATIVE
#include <libc.h>
#endif
#ifndef FD_CLOEXEC
#define FD_CLOEXEC 01
#endif
int agent_native_shutdown(const char *mode)
{
    const char *path;int p[2],child,flags,i,fd,err,result;fd_set readers;struct timeval timeout;
    if(!strcmp(mode,"halt"))path="/usr/etc/halt";
    else if(!strcmp(mode,"reboot"))path="/usr/etc/reboot";
    else return -1;
    if(access(path,X_OK) || pipe(p))return -1;
    if(fcntl(p[1],F_SETFD,FD_CLOEXEC)) { close(p[0]);close(p[1]);return -1; }
    child=fork();
    if(child<0) { close(p[0]);close(p[1]);return -1; }
    if(!child) {
        signal(SIGTERM,SIG_DFL);signal(SIGINT,SIG_DFL);signal(SIGHUP,SIG_DFL);signal(SIGPIPE,SIG_DFL);
#ifdef OPENSTEP_NATIVE
        setpgrp(getpid(),getpid());
#else
        setpgid(0,0);
#endif
        fd=open("/dev/null",O_RDWR);
        if(fd<0)goto failed;
        for(i=0;i<3;i++)if(dup2(fd,i)<0)goto failed;
        for(i=3;i<getdtablesize();i++)if(i!=p[1])close(i);
        execl(path,mode,(char *)0);
failed:
        err=errno;write(p[1],&err,sizeof(err));_exit(127);
    }
    close(p[1]);flags=fcntl(p[0],F_GETFL,0);
    if(flags<0 || fcntl(p[0],F_SETFL,flags|O_NDELAY)) { close(p[0]);return -1; }
    /* The child is intentionally outside connection-scoped exec cleanup. A
     * client disconnect after this accepted request must not cancel shutdown. */
    for(i=0;i<200;i++) {
        FD_ZERO(&readers);FD_SET(p[0],&readers);timeout.tv_sec=0;timeout.tv_usec=10000;
        result=select(p[0]+1,&readers,0,0,&timeout);
        if(result>0) {
            result=read(p[0],&err,sizeof(err));close(p[0]);return result==0?0:-1;
        }
        if(result<0 && errno!=EINTR)break;
    }
    close(p[0]);return -1;
}
