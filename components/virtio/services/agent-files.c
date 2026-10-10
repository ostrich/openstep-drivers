/* MIT license. Regular files only: never block the daemon on devices/FIFOs. */
#include "agent-files.h"
#include "base64.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#ifdef OPENSTEP_NATIVE
#include <libc.h>
#endif
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
#ifndef FD_CLOEXEC
#define FD_CLOEXEC 01
#endif
#ifndef FNOSPC
#define FNOSPC 0
#endif
void agent_files_init(struct agent_files *f)
{
    unsigned i;memset(f,0,sizeof(*f));f->next_handle=1;
    for(i=0;i<AGENT_FILE_LIMIT;i++)f->descriptors[i]=-1;
}
void agent_files_clear(struct agent_files *f)
{
    unsigned i;
    for(i=0;i<AGENT_FILE_LIMIT;i++) {
        if(f->descriptors[i]>=0)close(f->descriptors[i]);
        f->descriptors[i]=-1;f->handles[i]=0;
    }
}
static int member_integer(const struct agent_json *j,size_t args,const char *name,long long *value)
{
    size_t token;return agent_json_member(j,args,name,&token)==1 && !agent_json_integer(j,token,value)?0:-1;
}
static int member_string(const struct agent_json *j,size_t args,const char *name,char *out,size_t capacity)
{
    size_t token,n;
    if(agent_json_member(j,args,name,&token)!=1 || agent_json_string(j,token,out,capacity,&n) || strlen(out)!=n)return -1;
    return 0;
}
int agent_files_request(struct agent_files *f,const char *command,const struct agent_json *j,
                        size_t args,int has_args,const char **result,const char **error)
{
    unsigned slot;long long handle,count,offset,whence;size_t token,n,length;int fd,flags,truncate_file=0,status;
    char path[1024],mode[8],origin[8];struct stat st;off_t position;int transferred;
    if(strncmp(command,"guest-file-",11))return 0;
    if(strcmp(command,"guest-file-open") && strcmp(command,"guest-file-read") &&
       strcmp(command,"guest-file-write") && strcmp(command,"guest-file-seek") &&
       strcmp(command,"guest-file-flush") && strcmp(command,"guest-file-close"))return 0;
    *error=0;*result=f->result;
    if(!has_args) { *error="File operation requires arguments";return 1; }
    if(!strcmp(command,"guest-file-open")) {
        if(member_string(j,args,"path",path,sizeof(path)) || path[0]!='/') { *error="A full file path is required";return 1; }
        status=agent_json_member(j,args,"mode",&token);strcpy(mode,"r");
        if(status<0 || (status && member_string(j,args,"mode",mode,sizeof(mode)))) { *error="Invalid file mode";return 1; }
        if(!strcmp(mode,"r") || !strcmp(mode,"rb"))flags=O_RDONLY;
        else if(!strcmp(mode,"r+") || !strcmp(mode,"rb+") || !strcmp(mode,"r+b"))flags=O_RDWR;
        else if(!strcmp(mode,"w") || !strcmp(mode,"wb")) { flags=O_WRONLY|O_CREAT;truncate_file=1; }
        else if(!strcmp(mode,"w+") || !strcmp(mode,"wb+") || !strcmp(mode,"w+b")) { flags=O_RDWR|O_CREAT;truncate_file=1; }
        else if(!strcmp(mode,"a") || !strcmp(mode,"ab"))flags=O_WRONLY|O_CREAT|O_APPEND;
        else if(!strcmp(mode,"a+") || !strcmp(mode,"ab+") || !strcmp(mode,"a+b"))flags=O_RDWR|O_CREAT|O_APPEND;
        else { *error="Unsupported file mode";return 1; }
        for(slot=0;slot<AGENT_FILE_LIMIT && f->descriptors[slot]>=0;slot++);
        if(slot==AGENT_FILE_LIMIT || !f->next_handle) { *error="File handle limit reached";return 1; }
        if(!stat(path,&st) && (st.st_mode&S_IFMT)!=S_IFREG) { *error="Only regular files are supported";return 1; }
        fd=open(path,flags|O_NDELAY|FNOSPC,0666);
        if(fd<0) { *error="Unable to open file";return 1; }
        if(fstat(fd,&st) || (st.st_mode&S_IFMT)!=S_IFREG || fcntl(fd,F_SETFD,FD_CLOEXEC) || (truncate_file && ftruncate(fd,0))) {
            close(fd);*error="Unable to prepare regular file";return 1;
        }
        f->descriptors[slot]=fd;f->handles[slot]=f->next_handle++;
        sprintf(f->result,"%u",f->handles[slot]);return 1;
    }
    if(member_integer(j,args,"handle",&handle) || handle<=0 || handle>4294967295LL) { *error="Invalid file handle";return 1; }
    for(slot=0;slot<AGENT_FILE_LIMIT;slot++)if(f->descriptors[slot]>=0 && f->handles[slot]==(unsigned)handle)break;
    if(slot==AGENT_FILE_LIMIT) { *error="File handle is closed or belongs to another connection";return 1; }
    fd=f->descriptors[slot];
    if(!strcmp(command,"guest-file-close")) {
        status=close(fd);f->descriptors[slot]=-1;f->handles[slot]=0;
        if(status)*error="Unable to close file";else strcpy(f->result,"{}");return 1;
    }
    if(!strcmp(command,"guest-file-flush")) {
        /* Descriptor writes are unbuffered. fsync adds a persistence barrier. */
        if(fsync(fd))*error="Unable to flush file";else strcpy(f->result,"{}");return 1;
    }
    if(!strcmp(command,"guest-file-seek")) {
        if(member_integer(j,args,"offset",&offset) || agent_json_member(j,args,"whence",&token)!=1) { *error="Seek requires offset and whence";return 1; }
        if(j->tokens[token].type==AJ_STRING) {
            if(member_string(j,args,"whence",origin,sizeof(origin))) { *error="Invalid seek origin";return 1; }
            if(!strcmp(origin,"set"))whence=0;else if(!strcmp(origin,"cur"))whence=1;else if(!strcmp(origin,"end"))whence=2;else whence=-1;
        } else if(agent_json_integer(j,token,&whence))whence=-1;
        if(whence<0 || whence>2 || (long long)(off_t)offset!=offset) { *error="Seek offset or origin is unsupported";return 1; }
        position=lseek(fd,(off_t)offset,whence==0?SEEK_SET:whence==1?SEEK_CUR:SEEK_END);
        if(position<0) { *error="Unable to seek file";return 1; }
        sprintf(f->result,"{\"position\":%ld,\"eof\":false}",(long)position);return 1;
    }
    if(!strcmp(command,"guest-file-read")) {
        count=4096;status=agent_json_member(j,args,"count",&token);
        if(status<0 || (status && agent_json_integer(j,token,&count)) || count<0 || count>AGENT_FILE_CHUNK) { *error="Read count must be 0 through 32768";return 1; }
        do { transferred=read(fd,f->bytes,(size_t)count); } while(transferred<0 && errno==EINTR);
        if(transferred<0) { *error="Unable to read file";return 1; }
        if(agent_base64_encode(f->bytes,transferred,f->encoded,sizeof(f->encoded),&n)) { *error="Unable to encode file bytes";return 1; }
        length=sprintf(f->result,"{\"count\":%u,\"buf-b64\":\"",(unsigned)transferred);
        memcpy(f->result+length,f->encoded,n);length+=n;
        strcpy(f->result+length,transferred<count?"\",\"eof\":true}":"\",\"eof\":false}");return 1;
    }
    if(member_string(j,args,"buf-b64",f->encoded,sizeof(f->encoded)) ||
       agent_base64_decode(f->encoded,strlen(f->encoded),f->bytes,sizeof(f->bytes),&n)) { *error="Invalid or oversized base64 payload";return 1; }
    count=n;status=agent_json_member(j,args,"count",&token);
    if(status<0 || (status && agent_json_integer(j,token,&count)) || count<0 || (unsigned long long)count>n) { *error="Write count exceeds decoded payload";return 1; }
    do { transferred=write(fd,f->bytes,(size_t)count); } while(transferred<0 && errno==EINTR);
    if(transferred<0) { *error="Unable to write file";return 1; }
    sprintf(f->result,"{\"count\":%u,\"eof\":false}",(unsigned)transferred);return 1;
}
