/* MIT license. Independently enabled root PTY service on logical port 2. */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <libc.h>
#include <signal.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <errno.h>
#include "console-transport.h"
#include "pty-native.h"
#include "pty-wire.h"
#include "service-runtime.h"
#include "pty-timeout.h"
static volatile sig_atomic_t stopping;
static void stop(int number) { stopping=number; }
static struct pty_frame frame;
static unsigned char outgoing[32768],pending[4096],cookie[8];
static unsigned out_count,out_cursor,in_count,in_cursor,active,exit_sent;
static struct native_pty terminal;
static struct pty_timeout frame_timeout,input_timeout;
static const char *shell="/bin/csh";
static int queue(unsigned type,const unsigned char *bytes,unsigned count)
{
    unsigned size;
    if(out_cursor) { memmove(outgoing,outgoing+out_cursor,out_count-out_cursor);out_count-=out_cursor;out_cursor=0; }
    size=pty_frame_encode(outgoing+out_count,sizeof(outgoing)-out_count,type,bytes,count);
    if(!size)return -1;
    out_count+=size;return 0;
}
static int cancel(void)
{
    active=exit_sent=0;in_count=in_cursor=out_count=out_cursor=0;pty_frame_clear(&frame);
    pty_timeout_clear(&frame_timeout);pty_timeout_clear(&input_timeout);
    return native_pty_close(&terminal);
}
static int cancel_preserving_output(void)
{
    unsigned saved_count=out_count,saved_cursor=out_cursor;int result;
    result=cancel();out_count=saved_count;out_cursor=saved_cursor;
    return result;
}
static int ready(void)
{
    unsigned char body[12];memcpy(body,cookie,8);pty_put32(body+8,terminal.pid);
    return queue(PTY_READY,body,sizeof(body));
}
static int dispatch(void)
{
    unsigned rows,columns;unsigned char next_cookie[8];
    if(frame.type==PTY_HELLO) {
        if(frame.length!=12)return -1;
        rows=frame.payload[8]|((unsigned)frame.payload[9]<<8);columns=frame.payload[10]|((unsigned)frame.payload[11]<<8);
        if(!rows || rows>4096 || !columns || columns>4096)return -1;
        if(active && !memcmp(cookie,frame.payload,8))return ready();
        memcpy(next_cookie,frame.payload,8);
        if(cancel_preserving_output())return -1;
        memcpy(cookie,next_cookie,8);
        if(native_pty_start(&terminal,shell,rows,columns))return -1;
        active=1;return ready();
    }
    if(frame.type==PTY_PING) {
        if(!active || frame.length!=8 || memcmp(cookie,frame.payload,8))return -1;
        return queue(PTY_PONG,cookie,sizeof(cookie));
    }
    if(!active || terminal.exited)return -1;
    if(frame.type==PTY_INPUT) {
        if(!frame.length || in_cursor<in_count)return -1;
        memcpy(pending,frame.payload,frame.length);in_count=frame.length;in_cursor=0;return 0;
    }
    if(frame.type==PTY_RESIZE) {
        if(frame.length!=4)return -1;
        rows=frame.payload[0]|((unsigned)frame.payload[1]<<8);columns=frame.payload[2]|((unsigned)frame.payload[3]<<8);
        return native_pty_resize(&terminal,rows,columns);
    }
    if(frame.type==PTY_CLOSE && !frame.length)return cancel_preserving_output();
    return -1;
}
static void notify_stop(struct agent_transport *transport)
{
    unsigned char packet[128];unsigned size,chunk,attempt=0;int result;
    /* Finish queued frames before appending an error. Inserting a header into
     * a partially transmitted payload would corrupt the host parser. */
    while(out_cursor<out_count && attempt++<1000) {
        chunk=out_count-out_cursor;if(chunk>512)chunk=512;
        result=agent_transport_write(transport,outgoing+out_cursor,chunk);
        if(result==0)out_cursor+=chunk;
        else if(result==1)usleep(1000);else return;
    }
    if(out_cursor<out_count)return;
    size=pty_frame_encode(packet,sizeof(packet),PTY_ERROR,
                          (const unsigned char *)"Terminal service stopping",25);
    while(attempt++<1000) {
        result=agent_transport_write(transport,packet,size);
        if(result!=1)return;
        usleep(1000);
    }
}
int main(int argc,char **argv)
{
    struct agent_transport transport;unsigned char incoming[512],bytes[4096];unsigned count=0,cursor=0,chunk,stall=0;
    struct service_runtime runtime;const char *command=0;
    int changed,result,n,failed=0;fd_set readers;struct timeval timeout,now;long deadline=0;
    if(argc>1 && (!strcmp(argv[1],"--start") || !strcmp(argv[1],"--stop") || !strcmp(argv[1],"--status"))) {
        command=argv[1];argc--;argv++;
    }
    if(argc==3 && !strcmp(argv[1],"--shell"))shell=argv[2];
    else if(argc!=1) { fprintf(stderr,"Usage: openstep-pty [--start|--stop|--status] [--shell /absolute/shell]\n");return 2; }
    if(shell[0]!='/')return 2;
    service_runtime_init(&runtime);result=service_runtime_command(&runtime,"/usr/adm","openstep-pty",command);
    if(result!=1) { if(result<0)perror("openstep-pty: lifecycle");service_runtime_close(&runtime);return result<0?1:result; }
    native_pty_init(&terminal);memset(&transport,0,sizeof(transport));transport.lock_fd=-1;
    signal(SIGPIPE,SIG_IGN);signal(SIGINT,stop);signal(SIGTERM,stop);signal(SIGHUP,stop);signal(SIGCHLD,SIG_DFL);
    if(agent_transport_open(&transport,2) || agent_transport_refresh(&transport,0)<0 || service_runtime_ready(&runtime)) {
        perror("openstep-pty: startup");service_runtime_close(&runtime);agent_transport_close(&transport);return 1;
    }
    fprintf(stderr,"openstep-pty: serving terminal port 2\n");
    while(!stopping) {
        result=service_runtime_poll(&runtime);if(result) { if(result<0)failed=1;break; }
        changed=agent_transport_refresh(&transport,0);
        if(changed<0) { failed=1;break; }
        if(changed) { if(cancel()) { failed=1;break; }count=cursor=stall=0; }
        if(!transport.connected) { usleep(10000);continue; }
        native_pty_poll(&terminal);
        if(gettimeofday(&now,0)) { failed=1;break; }
        if(pty_timeout_watch(&frame_timeout,now.tv_sec,frame.header_bytes!=0) ||
           pty_timeout_watch(&input_timeout,now.tv_sec,in_cursor<in_count)) {
            const char *message="Terminal request timed out";
            if(cancel_preserving_output() || queue(PTY_ERROR,(const unsigned char *)message,strlen(message))) { failed=1;break; }
            count=cursor=0;
        }
        if(out_cursor<out_count) {
            chunk=out_count-out_cursor;if(chunk>512)chunk=512;
            result=agent_transport_write(&transport,outgoing+out_cursor,chunk);
            if(result<0) { failed=1;break; }
            if(result==0) { out_cursor+=chunk;stall=0;gettimeofday(&now,0);deadline=now.tv_sec+30; }
            else if(result==1) {
                if(!stall) { gettimeofday(&now,0);deadline=now.tv_sec+30; }
                if(gettimeofday(&now,0) || now.tv_sec>=deadline || ++stall>30000) { failed=1;break; }
            }
        }
        if(active && in_cursor<in_count && !terminal.exited) {
            n=write(terminal.master,pending+in_cursor,in_count-in_cursor);
            if(n>0)in_cursor+=n;
            else if(n<0 && errno!=EAGAIN && errno!=EWOULDBLOCK && errno!=EINTR) { failed=1;break; }
        }
        if(active && sizeof(outgoing)-(out_count-out_cursor)>=PTY_HEADER_BYTES+sizeof(bytes)) {
            FD_ZERO(&readers);FD_SET(terminal.master,&readers);timeout.tv_sec=0;timeout.tv_usec=0;
            result=select(terminal.master+1,&readers,0,0,&timeout);
            if(result>0) {
                n=read(terminal.master,bytes,sizeof(bytes));
                if(n>0 && queue(PTY_OUTPUT,bytes,n)) { failed=1;break; }
                if(n<=0 && terminal.exited && !exit_sent) {
                    unsigned char status[8];pty_put32(status,terminal.exitcode);pty_put32(status+4,terminal.signal_number);
                    if(queue(PTY_EXIT,status,sizeof(status))) { failed=1;break; }exit_sent=1;
                }
            } else if(terminal.exited && !exit_sent) {
                unsigned char status[8];pty_put32(status,terminal.exitcode);pty_put32(status+4,terminal.signal_number);
                if(queue(PTY_EXIT,status,sizeof(status))) { failed=1;break; }exit_sent=1;
            }
        }
        if(in_cursor==in_count) {
            if(cursor==count) {
                cursor=0;count=sizeof(incoming);result=agent_transport_read(&transport,incoming,&count);
                if(result<0) { failed=1;break; }
                if(result==2)count=0;
            }
            while(cursor<count && in_cursor==in_count) {
                result=pty_frame_byte(&frame,incoming[cursor++]);
                if(result<0 || (result==1 && dispatch())) {
                    if(cancel_preserving_output()) { failed=1;break; }
                    if(queue(PTY_ERROR,(const unsigned char *)"Invalid terminal request or shell startup failure",48)) { failed=1;break; }
                }
                if(result==1) { pty_frame_clear(&frame);pty_timeout_clear(&frame_timeout); }
            }
        }
        if(failed)break;
        usleep(1000);
    }
    if(!failed && active && transport.connected)notify_stop(&transport);
    if(cancel())failed=1;
    service_runtime_quiesce(&runtime);
    agent_transport_close(&transport);
    service_runtime_close_result(&runtime,failed);
    if(failed)fprintf(stderr,"openstep-pty: stopped after terminal/transport failure\n");
    return failed?1:0;
}
