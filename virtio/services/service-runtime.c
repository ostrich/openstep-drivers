/* MIT license. OPENSTEP BSD process detachment and local control sockets. */
#include "service-runtime.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#ifdef OPENSTEP_NATIVE
#include <libc.h>
#endif
#ifndef FD_CLOEXEC
#define FD_CLOEXEC 01
#endif
void service_runtime_init(struct service_runtime *r)
{ memset(r,0,sizeof(*r));r->listener=r->ack=r->stop_fd=-1; }
static int readable(int fd,int milliseconds)
{
    fd_set readers;struct timeval timeout;int result;
    FD_ZERO(&readers);FD_SET(fd,&readers);
    timeout.tv_sec=milliseconds/1000;timeout.tv_usec=(milliseconds%1000)*1000;
    result=select(fd+1,&readers,0,0,&timeout);
    return result;
}
static int control(const char *path,unsigned char command)
{
    struct sockaddr_un address;int fd,result;unsigned char reply;
    memset(&address,0,sizeof(address));address.sun_family=AF_UNIX;
    if(strlen(path)>=sizeof(address.sun_path)) { errno=ENAMETOOLONG;return -1; }
    strcpy(address.sun_path,path);fd=socket(AF_UNIX,SOCK_STREAM,0);if(fd<0)return -1;
    if(connect(fd,(struct sockaddr *)&address,sizeof(address))) {
        result=errno;close(fd);errno=result;
        return result==ENOENT || result==ECONNREFUSED?0:-1;
    }
    if(write(fd,&command,1)!=1 || readable(fd,command=='S'?30000:1000)!=1 || read(fd,&reply,1)!=1 || reply!='R') {
        close(fd);errno=EIO;return -1;
    }
    close(fd);return 1;
}
int service_runtime_command(struct service_runtime *r,const char *directory,
                            const char *name,const char *command)
{
    int result,pipefd[2],child,fd,i;unsigned char ack;char log[256];struct stat st;
    if(strlen(directory)+strlen(name)+10>=sizeof(r->socket_path)) { errno=ENAMETOOLONG;return -1; }
    sprintf(r->socket_path,"%s/%s.control",directory,name);
    if(!command)return 1;
    signal(SIGPIPE,SIG_IGN);
    if(!strcmp(command,"--status") || !strcmp(command,"--stop")) {
        result=control(r->socket_path,!strcmp(command,"--stop")?'S':'Q');
        if(result<0)return -1;
        if(!strcmp(command,"--status")) {
            printf("%s: %s\n",name,result?"running":"stopped");
            return result?0:3;
        }
        for(i=0;result && i<300;i++) {
            usleep(100000);
            if(lstat(r->socket_path,&st)) { if(errno!=ENOENT)return -1;result=0; }
        }
        if(result) { errno=EBUSY;return -1; }
        printf("%s: stopped\n",name);return 0;
    }
    if(strcmp(command,"--start")) { errno=EINVAL;return -1; }
    result=control(r->socket_path,'Q');if(result<0)return -1;
    if(result) { printf("%s: already running\n",name);return 0; }
    if(pipe(pipefd))return -1;
    child=fork();if(child<0) { close(pipefd[0]);close(pipefd[1]);return -1; }
    if(child) {
        close(pipefd[1]);result=readable(pipefd[0],30000);
        if(result==1)result=read(pipefd[0],&ack,1)==1 && ack=='R';else result=0;
        close(pipefd[0]);
        if(!result) { kill(child,SIGTERM);errno=EIO;return -1; }
        printf("%s: started\n",name);return 0;
    }
    close(pipefd[0]);r->ack=pipefd[1];
#ifdef OPENSTEP_NATIVE
    fd=open("/dev/tty",O_RDWR);if(fd>=0) { ioctl(fd,TIOCNOTTY,0);close(fd); }
    if(setpgrp(0,0))return -1;
#else
    if(setsid()<0)return -1;
#endif
    if(chdir("/"))return -1;
    umask(077);
    sprintf(log,"%s/%s.log",directory,name);
    if(!lstat(log,&st) && ((st.st_mode&S_IFMT)!=S_IFREG || st.st_uid!=geteuid() || st.st_nlink!=1)) { errno=EACCES;return -1; }
    fd=open(log,O_WRONLY|O_APPEND|O_CREAT,0600);if(fd<0)return -1;
    if(fstat(fd,&st) || (st.st_mode&S_IFMT)!=S_IFREG || st.st_uid!=geteuid() || st.st_nlink!=1) { close(fd);errno=EACCES;return -1; }
    if(dup2(fd,1)<0 || dup2(fd,2)<0)return -1;
    fd=open("/dev/null",O_RDONLY);if(fd<0 || dup2(fd,0)<0)return -1;
    for(i=3;i<getdtablesize();i++)if(i!=r->ack)close(i);
    return 1;
}
int service_runtime_ready(struct service_runtime *r)
{
    struct sockaddr_un address;struct stat st;int flags;
    if(lstat(r->socket_path,&st)==0) {
        if((st.st_mode&S_IFMT)!=S_IFSOCK || st.st_uid!=geteuid() || st.st_nlink!=1) { errno=EACCES;return -1; }
        if(unlink(r->socket_path))return -1;
    } else if(errno!=ENOENT)return -1;
    r->listener=socket(AF_UNIX,SOCK_STREAM,0);if(r->listener<0)return -1;
    memset(&address,0,sizeof(address));address.sun_family=AF_UNIX;strcpy(address.sun_path,r->socket_path);
    if(bind(r->listener,(struct sockaddr *)&address,sizeof(address)) || chmod(r->socket_path,0600) || listen(r->listener,4))return -1;
    flags=fcntl(r->listener,F_GETFL,0);
    if(flags<0 || fcntl(r->listener,F_SETFL,flags|O_NDELAY) || fcntl(r->listener,F_SETFD,FD_CLOEXEC))return -1;
    if(r->ack>=0) { unsigned char ack='R';if(write(r->ack,&ack,1)!=1)return -1;close(r->ack);r->ack=-1; }
    return 0;
}
int service_runtime_poll(struct service_runtime *r)
{
    int fd,result;unsigned char command,reply='R';
    if(r->listener<0)return 0;
    result=readable(r->listener,0);if(result<=0)return result<0 && errno!=EINTR?-1:0;
    fd=accept(r->listener,0,0);if(fd<0)return errno==EAGAIN || errno==EWOULDBLOCK || errno==EINTR?0:-1;
    result=readable(fd,100);
    if(result==1 && read(fd,&command,1)==1 && (command=='Q' || command=='S')) {
        if(command=='S') { r->stop_fd=fd;return 1; }
        result=write(fd,&reply,1)==1?0:-1;
    } else result=0;
    close(fd);return result;
}
void service_runtime_quiesce(struct service_runtime *r)
{
    if(r->listener>=0) { close(r->listener);unlink(r->socket_path);r->listener=-1; }
}
void service_runtime_close(struct service_runtime *r)
{ service_runtime_close_result(r,0); }
void service_runtime_close_result(struct service_runtime *r,int failed)
{
    unsigned char reply=failed?'E':'R';
    service_runtime_quiesce(r);
    if(r->stop_fd>=0) { write(r->stop_fd,&reply,1);close(r->stop_fd);r->stop_fd=-1; }
    if(r->ack>=0) { close(r->ack);r->ack=-1; }
}
