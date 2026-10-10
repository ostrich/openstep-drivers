/* MIT license. Root daemon implementing supported standard QGA commands. */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <libc.h>
#include <signal.h>
#include <sys/time.h>
#include "console-transport.h"
#include "agent-protocol.h"
#include "native-shutdown.h"
#include "service-runtime.h"
static volatile sig_atomic_t stopping;
static void stop(int number) { stopping=number; }
struct framing {
    char bytes[65536];unsigned count,depth,quoted,escape,discard;
};
static struct framing frame;
static char reply[73728];
static struct agent_protocol protocol;
/* Return 1 when a complete frame or malformed line is ready for dispatch.
 * 0xff always resets framing, as required by guest-sync-delimited clients. */
static int input_byte(unsigned char c)
{
    if(c==255) { memset(&frame,0,sizeof(frame));return 0; }
    if(frame.discard) {
        if(c=='\n') { memset(&frame,0,sizeof(frame));return 1; }
        return 0;
    }
    if(!frame.count && (c==' ' || c=='\r' || c=='\n' || c=='\t'))return 0;
    if(frame.count==sizeof(frame.bytes)) { frame.discard=1;return 0; }
    frame.bytes[frame.count++]=c;
    if(frame.quoted) {
        if(frame.escape)frame.escape=0;
        else if(c=='\\')frame.escape=1;
        else if(c=='"')frame.quoted=0;
    } else {
        if(c=='"')frame.quoted=1;
        else if(c=='{' || c=='[')frame.depth++;
        else if(c=='}' || c==']') {
            if(!frame.depth)return 1;
            if(!--frame.depth)return 1;
        } else if(c=='\n' && !frame.depth)return 1;
    }
    return 0;
}
int main(int argc,char **argv)
{
    struct agent_transport transport;unsigned char input[512];unsigned count=0,cursor=0;
    struct service_runtime runtime;
    size_t reply_count=0,reply_cursor=0;unsigned stall=0;int result,exit_code=0;struct timeval now;long deadline=0;
    if(argc>2) { fprintf(stderr,"Usage: openstep-qga [--start|--stop|--status]\n");return 2; }
    service_runtime_init(&runtime);
    result=service_runtime_command(&runtime,"/usr/adm","openstep-qga",argc==2?argv[1]:0);
    if(result!=1) { if(result<0)perror("openstep-qga: lifecycle");service_runtime_close(&runtime);return result<0?1:result; }
    agent_protocol_init(&protocol);protocol.shutdown=agent_native_shutdown;
    signal(SIGPIPE,SIG_IGN);signal(SIGINT,stop);signal(SIGTERM,stop);signal(SIGHUP,stop);
    memset(&transport,0,sizeof(transport));transport.lock_fd=-1;
    if(agent_transport_open(&transport,1) || agent_transport_refresh(&transport,0)<0 || service_runtime_ready(&runtime)) {
        perror("openstep-qga: startup");service_runtime_close(&runtime);agent_transport_close(&transport);return 1;
    }
    fprintf(stderr,"openstep-qga: serving guest-agent port 1\n");
    signal(SIGCHLD,SIG_DFL);
    while(!stopping) {
        result=service_runtime_poll(&runtime);
        if(result) { if(result<0)exit_code=1;break; }
        agent_protocol_poll(&protocol);
        result=agent_transport_refresh(&transport,0);
        if(result<0) { exit_code=1;break; }
        if(result) {
            agent_protocol_clear(&protocol);
            memset(&frame,0,sizeof(frame));count=cursor=0;reply_count=reply_cursor=0;stall=0;
        }
        if(protocol.shutdown_pending) { usleep(10000);continue; }
        if(!transport.connected) { usleep(10000);continue; }
        if(reply_cursor<reply_count) {
            unsigned chunk=reply_count-reply_cursor;
            if(chunk>512)chunk=512;
            result=agent_transport_write(&transport,(unsigned char *)reply+reply_cursor,chunk);
            if(result<0) { exit_code=1;break; }
            if(result==2)continue;
            if(result==1) {
                if(gettimeofday(&now,0) || now.tv_sec>=deadline || ++stall>=3000) { exit_code=1;break; }
                usleep(10000);continue;
            }
            reply_cursor+=chunk;continue;
        }
        if(cursor==count) {
            cursor=0;count=sizeof(input);result=agent_transport_read(&transport,input,&count);
            if(result<0) { exit_code=1;break; }
            if(result==2)continue;
            if(!count) { usleep(10000);continue; }
        }
        while(cursor<count)if(input_byte(input[cursor++])) {
            if(agent_protocol_request_context(&protocol,frame.bytes,frame.count,reply,sizeof(reply),&reply_count)) { exit_code=1;break; }
            reply_cursor=0;memset(&frame,0,sizeof(frame));stall=0;
            if(gettimeofday(&now,0)) { exit_code=1;break; }
            deadline=now.tv_sec+30;break;
        }
        if(exit_code)break;
    }
    agent_protocol_clear(&protocol);
    service_runtime_quiesce(&runtime);
    agent_transport_close(&transport);
    service_runtime_close_result(&runtime,exit_code);
    if(exit_code)fprintf(stderr,"openstep-qga: stopped after transport or response failure\n");
    return exit_code;
}
