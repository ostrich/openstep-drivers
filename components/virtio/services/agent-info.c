/* MIT license. No external commands or network lookups. */
#include "agent-info.h"
#include <string.h>
#include <unistd.h>
#include <sys/time.h>
#ifdef OPENSTEP_NATIVE
#include <libc.h>
#endif
int agent_info_request(const char *command,char *result,unsigned capacity,const char **error)
{
    struct timeval now;unsigned long long value;char reverse[32],hostname[256];unsigned n=0,i,count;
    *error=0;
    if(!strcmp(command,"guest-get-time")) {
        if(gettimeofday(&now,0) || now.tv_sec<0 || now.tv_usec<0 || now.tv_usec>=1000000) { *error="Unable to read guest time";return 1; }
        value=(unsigned long long)now.tv_sec*1000000000ULL+(unsigned long long)now.tv_usec*1000ULL;
        do { reverse[n++]=(char)('0'+value%10);value/=10; } while(value);
        if(capacity<=n) { *error="Information response buffer too small";return 1; }
        for(i=0;i<n;i++)result[i]=reverse[n-1-i];
        result[n]=0;return 1;
    }
    if(strcmp(command,"guest-get-host-name"))return 0;
    memset(hostname,0,sizeof(hostname));
    if(gethostname(hostname,sizeof(hostname)-1)) { *error="Unable to read hostname";return 1; }
    count=0;
    if(capacity<32) { *error="Information response buffer too small";return 1; }
    strcpy(result,"{\"host-name\":\"");count=strlen(result);
    for(i=0;hostname[i];i++) {
        unsigned c=(unsigned char)hostname[i];
        if(c<32 || c>=127) { *error="Hostname requires unsupported character encoding";return 1; }
        if(count+4>=capacity) { *error="Information response buffer too small";return 1; }
        if(c=='"' || c=='\\')result[count++]='\\';
        result[count++]=c;
    }
    strcpy(result+count,"\"}");return 1;
}
