/* MIT license. BSD OPENSTEP PTYs; POSIX host backend for behavioral tests. */
#include "pty-native.h"
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <sys/time.h>
#include <signal.h>
#include <errno.h>
#include <sys/stat.h>
#include <stdio.h>
#ifdef OPENSTEP_NATIVE
#include <libc.h>
#include <mach/mach.h>
#include <mach/mach_host.h>
#else
#include <pty.h>
#include <termios.h>
#include <dirent.h>
#include <stdio.h>
#endif
#ifndef FD_CLOEXEC
#define FD_CLOEXEC 01
#endif
void native_pty_init(struct native_pty *p)
{ memset(p,0,sizeof(*p));p->master=-1; }
int native_pty_resize(struct native_pty *p,unsigned rows,unsigned columns)
{
    struct winsize size;
    if(p->master<0 || rows<1 || rows>4096 || columns<1 || columns>4096) { errno=EINVAL;return -1; }
    memset(&size,0,sizeof(size));size.ws_row=rows;size.ws_col=columns;
    return ioctl(p->master,TIOCSWINSZ,&size);
}
void native_pty_poll(struct native_pty *p)
{
    int found;
#ifdef OPENSTEP_NATIVE
    union wait status;
#else
    int status;
#endif
    if(!p->pid || p->exited)return;
#ifdef OPENSTEP_NATIVE
    found=wait3(&status,WNOHANG,0);
#else
    found=waitpid(p->pid,&status,WNOHANG);
#endif
    if(found==p->pid) {
        p->exited=1;
#ifdef OPENSTEP_NATIVE
        if(WIFEXITED(status))p->exitcode=status.w_retcode;else p->signal_number=status.w_termsig;
#else
        if(WIFEXITED(status))p->exitcode=WEXITSTATUS(status);else p->signal_number=WTERMSIG(status);
#endif
    }
}
/* A job-control shell creates a separate process group for every job. Killing
 * only the shell/foreground groups therefore leaves background jobs alive.
 * Keep the master allocated until all processes on its terminal have exited.
 * OPENSTEP table(2) is indexed by PID, so enumerate Mach tasks first. The
 * compact ABI below is from NeXTMach mk-108.1/sys/table.h; the developer SDK
 * omits that header. pty-process-probe verifies it against the running kernel.
 */
#ifdef OPENSTEP_NATIVE
struct os42_procinfo { int uid,pid,ppid,pgrp,ttyd,status,flag;char comm[20]; };
extern int table(int,int,char *,int,int);
static int signal_session(struct native_pty *p,int number)
{
    host_priv_t host;processor_set_name_t *sets=0;processor_set_t privileged;
    task_t *tasks=0;unsigned set_count=0,task_count=0,i,j;int pid,count=0,failed=0;
    struct os42_procinfo info;struct stat st;
    kern_return_t kr;
    if(stat(p->slave,&st)) { perror("PTY cleanup: slave stat");return -1; }
    host=host_priv_self();if(host==PORT_NULL) { errno=EPERM;return -1; }
    kr=host_processor_sets(host,&sets,&set_count);
    if(kr!=KERN_SUCCESS) { fprintf(stderr,"PTY cleanup: host_processor_sets: %d\n",kr);failed=1;goto done; }
    if(set_count>4096) { failed=1;goto release_sets; }
    for(i=0;i<set_count;i++) {
        kr=host_processor_set_priv(host,sets[i],&privileged);
        if(kr!=KERN_SUCCESS) { fprintf(stderr,"PTY cleanup: host_processor_set_priv: %d\n",kr);failed=1;continue; }
        kr=processor_set_tasks(privileged,&tasks,&task_count);
        if(kr!=KERN_SUCCESS) {
            fprintf(stderr,"PTY cleanup: processor_set_tasks: %d\n",kr);
            port_deallocate(task_self(),privileged);failed=1;continue;
        }
        if(task_count>4096)failed=1;
        for(j=0;j<task_count;j++) {
            if(task_count<=4096 && unix_pid(tasks[j],&pid)==KERN_SUCCESS && pid>1 && pid!=getpid()) {
                memset(&info,0,sizeof(info));
                if(table(10,pid,(char *)&info,1,sizeof(info))==1 && info.pid==pid &&
                   info.ttyd==(int)st.st_rdev && info.status==1) {
                    count++;
                    if(number && kill(pid,number) && errno!=ESRCH)failed=1;
                }
            }
            if(tasks[j]!=task_self())port_deallocate(task_self(),tasks[j]);
        }
        vm_deallocate(task_self(),(vm_address_t)tasks,task_count*sizeof(task_t));
        port_deallocate(task_self(),privileged);
    }
release_sets:
    for(i=0;i<set_count;i++)port_deallocate(task_self(),sets[i]);
    vm_deallocate(task_self(),(vm_address_t)sets,set_count*sizeof(processor_set_name_t));
done:
    /* host_priv_self() is a task-wide special port, also used by DriverKit.
     * Retain it like task_self(); releasing it invalidates cached RPC ports. */
    if(failed) { errno=EIO;return -1; }return count;
}
#else
/* Linux test backend: the shell creates a fresh session with setsid(). */
static int signal_session(struct native_pty *p,int number)
{
    DIR *directory;struct dirent *entry;FILE *file;char path[80],line[4096],*tail,state;
    int pid,parent,group,session,count=0,failed=0;
    directory=opendir("/proc");if(!directory)return -1;
    while((entry=readdir(directory))) {
        pid=atoi(entry->d_name);if(pid<=1 || pid==getpid())continue;
        snprintf(path,sizeof(path),"/proc/%d/stat",pid);file=fopen(path,"r");if(!file)continue;
        tail=fgets(line,sizeof(line),file)?strrchr(line,')'):0;fclose(file);
        if(!tail || sscanf(tail+1," %c %d %d %d",&state,&parent,&group,&session)!=4)continue;
        if(session!=p->pid || state=='Z' || state=='X')continue;
        count++;if(number && kill(pid,number) && errno!=ESRCH)failed=1;
    }
    closedir(directory);if(failed) { errno=EIO;return -1; }return count;
}
#endif
int native_pty_close(struct native_pty *p)
{
    unsigned i;int remaining=0,failed=0;
    if(p->master>=0 && p->pid) {
        if(signal_session(p,SIGHUP)<0)failed=1;
        if(signal_session(p,SIGTERM)<0)failed=1;
        for(i=0;i<20;i++) {
            native_pty_poll(p);remaining=signal_session(p,0);
            if(remaining<=0)break;
            usleep(5000);
        }
        for(i=0;i<200;i++) {
            remaining=signal_session(p,SIGKILL);native_pty_poll(p);
            if(remaining<=0)break;
            usleep(5000);
        }
        if(remaining<0)failed=1;
    }
    /* Startup can fail before the child acquires its controlling terminal. */
    if(p->pid && !p->exited)kill(p->pid,SIGKILL);
    if(p->master>=0) { close(p->master);p->master=-1; }
    for(i=0;p->pid && !p->exited && i<200;i++) { native_pty_poll(p);usleep(5000); }
    if(failed || remaining>0 || (p->pid && !p->exited)) {
        fprintf(stderr,"PTY cleanup: failed=%d remaining=%d child=%d reaped=%d\n",failed,remaining,p->pid,p->exited);
        errno=EBUSY;return -1;
    }
    native_pty_init(p);return 0;
}
int native_pty_start(struct native_pty *p,const char *shell,unsigned rows,unsigned columns)
{
    int child,slave=-1,ack[2],flags,i,error,ready;
    struct winsize size;fd_set readers;struct timeval timeout;
    if(p->pid || p->master>=0 || rows<1 || rows>4096 || columns<1 || columns>4096 || access(shell,X_OK))return -1;
#ifdef OPENSTEP_NATIVE
    {
        const char *banks="pqrstuvwxyz",*digits="0123456789abcdef";char path[]="/dev/ptyp0";unsigned b,d;
        for(b=0;banks[b] && p->master<0;b++)for(d=0;digits[d];d++) {
            path[8]=banks[b];path[9]=digits[d];p->master=open(path,O_RDWR|O_NDELAY);
            if(p->master>=0) { strcpy(p->slave,path);p->slave[5]='t';break; }
        }
    }
#else
    if(openpty(&p->master,&slave,p->slave,0,0))return -1;
#endif
    if(p->master<0)return -1;
    flags=fcntl(p->master,F_GETFL,0);
    if(flags<0 || fcntl(p->master,F_SETFL,flags|O_NDELAY) || fcntl(p->master,F_SETFD,FD_CLOEXEC) || pipe(ack))goto failed;
    if(fcntl(ack[1],F_SETFD,FD_CLOEXEC)) { close(ack[0]);close(ack[1]);goto failed; }
    child=fork();if(child<0) { close(ack[0]);close(ack[1]);goto failed; }
    if(!child) {
        int group;char *environment[]={"TERM=vt100","HOME=/","USER=root","LOGNAME=root","LANG=C",
            "PATH=/bin:/usr/bin:/usr/ucb:/usr/etc:/usr/local/bin:/usr/local/sbin",0};char *arguments[4];
#ifdef OPENSTEP_NATIVE
        int fd;
#endif
        signal(SIGPIPE,SIG_DFL);signal(SIGINT,SIG_DFL);signal(SIGQUIT,SIG_DFL);signal(SIGTERM,SIG_DFL);
        signal(SIGHUP,SIG_DFL);signal(SIGCHLD,SIG_DFL);signal(SIGTSTP,SIG_DFL);signal(SIGTTIN,SIG_DFL);signal(SIGTTOU,SIG_DFL);
#ifdef OPENSTEP_NATIVE
        fd=open("/dev/tty",O_RDWR);if(fd>=0) { ioctl(fd,TIOCNOTTY,0);close(fd); }
        if(setpgrp(0,0))goto child_failed;
        slave=open(p->slave,O_RDWR);if(slave<0)goto child_failed;
        group=getpid();if(setpgrp(0,group) || ioctl(slave,TIOCSPGRP,&group))goto child_failed;
        {
            struct sgttyb attributes;int local;
            if(ioctl(slave,TIOCGETP,&attributes))goto child_failed;
            attributes.sg_flags=(attributes.sg_flags&~(RAW|CBREAK))|ECHO|CRMOD;
            if(ioctl(slave,TIOCSETP,&attributes))goto child_failed;
            if(!ioctl(slave,TIOCLGET,&local)) { local|=LPASS8;ioctl(slave,TIOCLSET,&local); }
        }
#else
        if(setsid()<0 || ioctl(slave,TIOCSCTTY,0))goto child_failed;
        group=getpid();if(ioctl(slave,TIOCSPGRP,&group))goto child_failed;
#endif
        memset(&size,0,sizeof(size));size.ws_row=rows;size.ws_col=columns;
        if(ioctl(slave,TIOCSWINSZ,&size))goto child_failed;
        for(i=0;i<3;i++)if(dup2(slave,i)<0)goto child_failed;
        for(i=3;i<getdtablesize();i++)if(i!=ack[1])close(i);
        if(chdir("/"))goto child_failed;
        arguments[0]=(char *)shell;
        if(strstr(shell,"csh")) { arguments[1]="-f";arguments[2]="-i";arguments[3]=0; }
        else { arguments[1]="-i";arguments[2]=0; }
        execve((char *)shell,arguments,environment);
child_failed:
        error=errno;write(ack[1],&error,sizeof(error));_exit(127);
    }
    p->pid=child;if(slave>=0) { close(slave);slave=-1; }close(ack[1]);
    ready=0;
    for(i=0;i<200;i++) {
        FD_ZERO(&readers);FD_SET(ack[0],&readers);timeout.tv_sec=0;timeout.tv_usec=10000;
        flags=select(ack[0]+1,&readers,0,0,&timeout);
        if(flags>0) { ready=read(ack[0],&error,sizeof(error))==0;break; }
        if(flags<0 && errno!=EINTR)break;
    }
    close(ack[0]);if(ready)return 0;
    native_pty_close(p);return -1;
failed:
    if(slave>=0)close(slave);
    if(p->master>=0)close(p->master);
    native_pty_init(p);return -1;
}
