/* MIT license. Never wait for command completion in the request dispatcher. */
#include "agent-exec.h"
#include "base64.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/time.h>
#include <errno.h>
#ifdef OPENSTEP_NATIVE
#include <libc.h>
#endif
#ifndef FD_CLOEXEC
#define FD_CLOEXEC 01
#endif
extern char **environ;
static void close_fd(int *fd) { if(*fd>=0)close(*fd);*fd=-1; }
static void reset_job(struct agent_job *job)
{
    unsigned i;for(i=0;i<3;i++)close_fd(&job->fd[i]);
    memset(job,0,sizeof(*job));for(i=0;i<3;i++)job->fd[i]=-1;
}
void agent_exec_init(struct agent_exec *exec)
{
    unsigned i,j;memset(exec,0,sizeof(*exec));
    for(i=0;i<AGENT_EXEC_LIMIT;i++)for(j=0;j<3;j++)exec->jobs[i].fd[j]=-1;
}
static int nonblocking(int fd)
{
    int flags=fcntl(fd,F_GETFL,0);
    return flags<0 || fcntl(fd,F_SETFL,flags|O_NDELAY) || fcntl(fd,F_SETFD,FD_CLOEXEC)?-1:0;
}
static void signal_job(struct agent_job *job,int number)
{
    if(job->pid && !job->exited) {
        /* Child and parent establish a separate group before exec. */
        kill(-job->pid,number);kill(job->pid,number);
    }
}
static void drain(struct agent_job *job,unsigned stream)
{
    unsigned steps;int n;unsigned char bytes[4096];unsigned available,take;
    for(steps=0;job->fd[stream+1]>=0 && steps<8;steps++) {
        n=read(job->fd[stream+1],bytes,sizeof(bytes));
        if(n>0) {
            available=AGENT_EXEC_CAPTURE-job->size[stream];take=(unsigned)n<available?(unsigned)n:available;
            memcpy(job->output[stream]+job->size[stream],bytes,take);job->size[stream]+=take;
            if(take<(unsigned)n)job->truncated[stream]=1;
        } else if(!n)close_fd(&job->fd[stream+1]);
        else if(errno!=EINTR && errno!=EAGAIN && errno!=EWOULDBLOCK) {
            job->truncated[stream]=1;close_fd(&job->fd[stream+1]);
        } else if(errno!=EINTR)break;
    }
}
void agent_exec_poll(struct agent_exec *exec)
{
    unsigned i;int pid,n;struct timeval now;
#ifdef OPENSTEP_NATIVE
    union wait status;
#else
    int status;
#endif
    /* wait3 is the actually exported OPENSTEP API; waitpid is not linked. */
    for(;;) {
        pid=wait3(&status,WNOHANG,0);if(pid<=0)break;
        for(i=0;i<AGENT_EXEC_LIMIT;i++)if(exec->jobs[i].pid==pid && !exec->jobs[i].exited) {
            struct agent_job *job=&exec->jobs[i];job->exited=1;close_fd(&job->fd[0]);
#ifdef OPENSTEP_NATIVE
            if(WIFEXITED(status))job->exitcode=status.w_retcode;else job->signal_number=status.w_termsig;
#else
            if(WIFEXITED(status))job->exitcode=WEXITSTATUS(status);else job->signal_number=WTERMSIG(status);
#endif
            break;
        }
    }
    if(gettimeofday(&now,0))now.tv_sec=0;
    for(i=0;i<AGENT_EXEC_LIMIT;i++)if(exec->jobs[i].pid) {
        struct agent_job *job=&exec->jobs[i];
        drain(job,0);drain(job,1);
        if(job->fd[0]>=0) {
            n=write(job->fd[0],job->input+job->input_cursor,job->input_count-job->input_cursor);
            if(n>0)job->input_cursor+=n;
            else if(n<0 && errno!=EINTR && errno!=EAGAIN && errno!=EWOULDBLOCK)close_fd(&job->fd[0]);
            if(job->input_cursor==job->input_count)close_fd(&job->fd[0]);
        }
        if(!job->exited && ((now.tv_sec && now.tv_sec>=job->deadline) || ++job->ticks>=3600000U))signal_job(job,SIGKILL);
        /* Descendants may keep a pipe open after the direct command exits.
         * Drain what is available; after bounded polls close inherited pipes
         * and mark incomplete capture rather than waiting indefinitely. */
        if(job->exited && ++job->exit_ticks>=100) {
            unsigned s;for(s=0;s<2;s++)if(job->fd[s+1]>=0) { job->truncated[s]=1;close_fd(&job->fd[s+1]); }
        }
        if(job->abandoned && job->exited)reset_job(job);
    }
}
unsigned agent_exec_clear(struct agent_exec *exec)
{
    unsigned i,step,remaining=0;
    for(i=0;i<AGENT_EXEC_LIMIT;i++)if(exec->jobs[i].pid) { exec->jobs[i].abandoned=1;signal_job(&exec->jobs[i],SIGTERM); }
    for(step=0;step<20;step++) {
        agent_exec_poll(exec);remaining=0;
        for(i=0;i<AGENT_EXEC_LIMIT;i++)if(exec->jobs[i].pid && !exec->jobs[i].exited)remaining++;
        if(!remaining)break;
        usleep(5000);
    }
    for(i=0;i<AGENT_EXEC_LIMIT;i++)signal_job(&exec->jobs[i],SIGKILL);
    for(step=0;step<100;step++) {
        agent_exec_poll(exec);remaining=0;
        for(i=0;i<AGENT_EXEC_LIMIT;i++)if(exec->jobs[i].pid && !exec->jobs[i].exited)remaining++;
        if(!remaining)break;
        usleep(5000);
    }
    for(i=0;i<AGENT_EXEC_LIMIT;i++)if(exec->jobs[i].pid) {
        unsigned fd;for(fd=0;fd<3;fd++)close_fd(&exec->jobs[i].fd[fd]);
        if(exec->jobs[i].exited)reset_job(&exec->jobs[i]);
    }
    return remaining;
}
static int strings(const struct agent_json *j,size_t args,const char *name,
                   char *storage,size_t capacity,char **pointers,unsigned limit,int env)
{
    size_t token,i,n,used=0;unsigned count=0;int found=agent_json_member(j,args,name,&token);
    if(found<0)return -1;
    if(!found) { pointers[0]=0;return 0; }
    if(j->tokens[token].type!=AJ_ARRAY)return -1;
    for(i=token+1;i<j->tokens[token].next;i=j->tokens[i].next) {
        if(count==limit || agent_json_string(j,i,storage+used,capacity-used,&n) || strlen(storage+used)!=n)return -1;
        if(env && (!strchr(storage+used,'=') || storage[used]=='='))return -1;
        pointers[count++]=storage+used;used+=n+1;
    }
    pointers[count]=0;return 1;
}
static int group(int pid)
{
#ifdef OPENSTEP_NATIVE
    return setpgrp(pid,pid);
#else
    return setpgid(pid,pid);
#endif
}
int agent_exec_request(struct agent_exec *exec,const char *command,const struct agent_json *j,
                       size_t args,int has_args,const char **result,const char **error)
{
    unsigned slot,i,mode=0;size_t token,n,length;long long requested_pid;int found,env,child,read_count,start[2]={-1,-1},pipes[3][2],null_fd=-1,failed=0;
    struct agent_job *job;struct timeval now;char capture[16];
    if(strcmp(command,"guest-exec") && strcmp(command,"guest-exec-status"))return 0;
    *error=0;*result=exec->result;agent_exec_poll(exec);
    if(!has_args) { *error="Execution requires arguments";return 1; }
    if(!strcmp(command,"guest-exec-status")) {
        if(agent_json_member(j,args,"pid",&token)!=1 || agent_json_integer(j,token,&requested_pid) || requested_pid<=0 || requested_pid>2147483647LL) { *error="Invalid process ID";return 1; }
        for(slot=0;slot<AGENT_EXEC_LIMIT;slot++)if(exec->jobs[slot].pid==requested_pid && !exec->jobs[slot].abandoned)break;
        if(slot==AGENT_EXEC_LIMIT) { *error="Process is unknown or its status was already collected";return 1; }
        job=&exec->jobs[slot];
        if(!job->exited || job->fd[1]>=0 || job->fd[2]>=0) { strcpy(exec->result,"{\"exited\":false}");return 1; }
        length=sprintf(exec->result,job->signal_number?"{\"exited\":true,\"signal\":%d":"{\"exited\":true,\"exitcode\":%d",job->signal_number?job->signal_number:job->exitcode);
        for(i=0;i<2;i++)if(job->mode&(1U<<i)) {
            if(agent_base64_encode(job->output[i],job->size[i],exec->encoded,sizeof(exec->encoded),&n)) { *error="Unable to encode captured output";return 1; }
            length+=sprintf(exec->result+length,",\"%s-data\":\"",i?"err":"out");
            memcpy(exec->result+length,exec->encoded,n);length+=n;
            length+=sprintf(exec->result+length,"\",\"%s-truncated\":%s",i?"err":"out",job->truncated[i]?"true":"false");
        }
        strcpy(exec->result+length,"}");reset_job(job);return 1;
    }
    for(slot=0;slot<AGENT_EXEC_LIMIT && exec->jobs[slot].pid;slot++);
    if(slot==AGENT_EXEC_LIMIT) { *error="Process limit reached; collect completed status";return 1; }
    job=&exec->jobs[slot];
    if(agent_json_member(j,args,"path",&token)!=1 || agent_json_string(j,token,exec->path,sizeof(exec->path),&n) || !n || strlen(exec->path)!=n) { *error="Invalid executable path";return 1; }
    exec->argv[0]=exec->path;
    if(strings(j,args,"arg",exec->arguments,sizeof(exec->arguments),exec->argv+1,32,0)<0 ||
       (env=strings(j,args,"env",exec->environment,sizeof(exec->environment),exec->envp,64,1))<0) { *error="Invalid or oversized arguments/environment";return 1; }
    found=agent_json_member(j,args,"capture-output",&token);
    if(found<0) { *error="Ambiguous capture mode";return 1; }
    if(found) {
        if(j->tokens[token].type==AJ_TRUE)mode=3;
        else if(j->tokens[token].type==AJ_FALSE)mode=0;
        else if(!agent_json_string(j,token,capture,sizeof(capture),&n) && strlen(capture)==n) {
            if(!strcmp(capture,"none"))mode=0;else if(!strcmp(capture,"stdout"))mode=1;
            else if(!strcmp(capture,"stderr"))mode=2;else if(!strcmp(capture,"separated"))mode=3;
            else if(!strcmp(capture,"merged"))mode=5;else mode=8;
        } else mode=8;
        if(mode==8) { *error="Invalid capture mode";return 1; }
    }
    job->mode=mode==5?1:mode;job->input_count=0;
    found=agent_json_member(j,args,"input-data",&token);
    if(found<0 || (found && (agent_json_string(j,token,exec->encoded,sizeof(exec->encoded),&n) || strlen(exec->encoded)!=n ||
       agent_base64_decode(exec->encoded,n,job->input,sizeof(job->input),&length)))) { *error="Invalid or oversized input data";return 1; }
    if(found)job->input_count=length;
    for(i=0;i<3;i++)pipes[i][0]=pipes[i][1]=-1;
    null_fd=open("/dev/null",O_RDWR);
    if(null_fd<0 || pipe(start) || nonblocking(start[0]) || fcntl(start[1],F_SETFD,FD_CLOEXEC))goto spawn_failed;
    for(i=0;i<3;i++)if((i==0 && found) || (i==1 && (job->mode&1)) || (i==2 && (job->mode&2))) {
        if(pipe(pipes[i]) || nonblocking(pipes[i][i==0?1:0]))goto spawn_failed;
    }
    child=fork();if(child<0)goto spawn_failed;
    if(!child) {
        int descriptor,source,err,limit;
        signal(SIGPIPE,SIG_DFL);signal(SIGINT,SIG_DFL);signal(SIGTERM,SIG_DFL);signal(SIGHUP,SIG_DFL);signal(SIGCHLD,SIG_DFL);
        if(group(getpid()) || chdir("/"))goto child_failed;
        for(i=0;i<3;i++) {
            source=pipes[i][i==0?0:1]>=0?pipes[i][i==0?0:1]:null_fd;
            if(i==2 && mode==5)source=pipes[1][1];
            if(dup2(source,i)<0)goto child_failed;
        }
        limit=getdtablesize();for(descriptor=3;descriptor<limit;descriptor++)if(descriptor!=start[1])close(descriptor);
        if(env)environ=exec->envp;
#ifdef OPENSTEP_NATIVE
        execvp(exec->path,(const char **)exec->argv);
#else
        execvp(exec->path,exec->argv);
#endif
child_failed:
        err=errno;write(start[1],&err,sizeof(err));_exit(127);
    }
    /* Returned identifiers are kernel PIDs, as required by QGA. A PID reused
     * after an earlier exit supersedes that obsolete collected-late record. */
    for(i=0;i<AGENT_EXEC_LIMIT;i++)if(i!=slot && exec->jobs[i].pid==child && exec->jobs[i].exited)reset_job(&exec->jobs[i]);
    group(child);job->pid=child;
    for(i=0;i<3;i++) { close_fd(&pipes[i][i==0?0:1]);job->fd[i]=pipes[i][i==0?1:0];pipes[i][i==0?1:0]=-1; }
    close_fd(&null_fd);close_fd(&start[1]);
    if(gettimeofday(&now,0))now.tv_sec=0;
    job->deadline=now.tv_sec+3600;
    for(i=0;i<400;i++) {
        read_count=read(start[0],&failed,sizeof(failed));
        if(read_count==0)break;
        if(read_count>0) { failed=1;break; }
        if(errno!=EINTR && errno!=EAGAIN && errno!=EWOULDBLOCK) { failed=1;break; }
        agent_exec_poll(exec);usleep(5000);
    }
    close_fd(&start[0]);
    if(i==400 || failed) {
        job->abandoned=1;signal_job(job,SIGKILL);
        for(i=0;i<100 && job->pid;i++) { agent_exec_poll(exec);usleep(5000); }
        *error="Unable to execute program";return 1;
    }
    sprintf(exec->result,"{\"pid\":%d}",child);return 1;
spawn_failed:
    close_fd(&null_fd);close_fd(&start[0]);close_fd(&start[1]);
    for(i=0;i<3;i++) { close_fd(&pipes[i][0]);close_fd(&pipes[i][1]); }
    reset_job(job);*error="Unable to allocate process resources";return 1;
}
