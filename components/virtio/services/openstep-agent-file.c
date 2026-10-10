/* MIT license. Atomic file commit helper, invoked through standard guest-exec.
 * No shell interpretation and no elevated privileges beyond the calling user. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <errno.h>
#ifdef OPENSTEP_NATIVE
#include <libc.h>
#endif
int main(int argc,char **argv)
{
    int fd,directory;struct stat st;unsigned long mode;char *end,*slash,parent[1024];
    if(argc==2 && !strcmp(argv[1],"probe"))return 0;
    if(argc==3 && !strcmp(argv[1],"remove")) {
        if(argv[2][0]!='/')return 2;
        if(unlink(argv[2]) && errno!=ENOENT) { perror("remove temporary file");return 1; }
        return 0;
    }
    if(argc!=5 || strcmp(argv[1],"commit") || argv[2][0]!='/' || argv[3][0]!='/' || strlen(argv[3])>=sizeof(parent)) {
        fprintf(stderr,"Usage: openstep-agent-file commit SOURCE DESTINATION MODE | remove PATH\n");return 2;
    }
    mode=strtoul(argv[4],&end,8);if(!argv[4][0] || *end || mode>0777)return 2;
    if(!stat(argv[3],&st)) {
        if((st.st_mode&S_IFMT)!=S_IFREG) { fprintf(stderr,"Destination is not a regular file\n");return 1; }
    } else if(errno!=ENOENT) { perror("inspect destination");return 1; }
    strcpy(parent,argv[3]);slash=strrchr(parent,'/');if(slash==parent)slash[1]=0;else *slash=0;
    directory=open(parent,O_RDONLY);if(directory<0) { perror("open destination directory");return 1; }
    fd=open(argv[2],O_RDWR|O_NDELAY);
    if(fd<0) { perror("open temporary file");close(directory);return 1; }
    if(fstat(fd,&st) || (st.st_mode&S_IFMT)!=S_IFREG || fchmod(fd,(int)mode) || fsync(fd)) {
        perror("prepare temporary file");close(fd);close(directory);return 1;
    }
    if(rename(argv[2],argv[3])) { perror("atomic file rename");close(fd);close(directory);return 1; }
    close(fd);
    if(fsync(directory)) { perror("sync committed directory; rename already completed");close(directory);return 1; }
    close(directory);return 0;
}
