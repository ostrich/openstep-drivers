/* MIT license. Only implemented commands are advertised. */
#include "agent-protocol.h"
#include "agent-json.h"
#include "agent-info.h"
#include <string.h>
#include <stdio.h>
struct response { char *data;size_t count,capacity;int failed; };
static void append(struct response *r,const char *text,size_t bytes)
{
    if(bytes>r->capacity-r->count) { r->failed=1;return; }
    memcpy(r->data+r->count,text,bytes);r->count+=bytes;
}
static void literal(struct response *r,const char *text)
{ append(r,text,strlen(text)); }
static void capabilities(struct agent_protocol *context,char *out)
{
    static const char *names[]={"guest-sync","guest-sync-delimited","guest-ping","guest-info",
        "guest-file-open","guest-file-read","guest-file-write","guest-file-seek","guest-file-flush","guest-file-close",
        "guest-exec","guest-exec-status","guest-get-time","guest-get-host-name","guest-shutdown"};
    unsigned i,length;
    length=sprintf(out,"{\"version\":\"0.1\",\"supported_commands\":[");
    for(i=0;i<sizeof(names)/sizeof(names[0]);i++)length+=sprintf(out+length,
        "%s{\"name\":\"%s\",\"enabled\":%s,\"success-response\":%s}",i?",":"",names[i],
        i==14 && (!context || !context->shutdown)?"false":"true",i==14?"false":"true");
    strcpy(out+length,"]}");
}
void agent_protocol_init(struct agent_protocol *context) { agent_files_init(&context->files);agent_exec_init(&context->exec);context->shutdown=0;context->shutdown_pending=0; }
void agent_protocol_clear(struct agent_protocol *context) { agent_files_clear(&context->files);agent_exec_clear(&context->exec); }
void agent_protocol_poll(struct agent_protocol *context) { agent_exec_poll(&context->exec); }
int agent_protocol_request_context(struct agent_protocol *context,const char *input,size_t bytes,char *output,
                           size_t capacity,size_t *written)
{
    struct agent_json j;struct agent_json_token tokens[256];struct response r;
    size_t execute=0,args=0,id=0,sync=0,n;int has_args=0,has_id=0,delimited=0;
    const char *error=0,*error_class="GenericError",*result="{}";char command[64],information[2048];long long integer;
    if(!written || !output)return -1;
    *written=0;r.data=output;r.count=0;r.capacity=capacity;r.failed=0;
    if(bytes>65536 || agent_json_parse(&j,input,bytes,tokens,256) || tokens[0].type!=AJ_OBJECT)error="Invalid JSON request";
    else {
        has_id=agent_json_member(&j,0,"id",&id);
        has_args=agent_json_member(&j,0,"arguments",&args);
        if(has_id<0 || has_args<0 || agent_json_member(&j,0,"execute",&execute)!=1 ||
           agent_json_string(&j,execute,command,sizeof(command),&n) || strlen(command)!=n ||
           (has_args && tokens[args].type!=AJ_OBJECT))error="Invalid request members";
        else if(has_id==1 && tokens[id].end-tokens[id].start>4096)error="Request id exceeds supported size";
        else if(!strcmp(command,"guest-sync") || !strcmp(command,"guest-sync-delimited")) {
            if(!has_args || agent_json_member(&j,args,"id",&sync)!=1 || agent_json_integer(&j,sync,&integer))error="Sync requires a signed 64-bit id";
            else { result=0;delimited=!strcmp(command,"guest-sync-delimited"); }
        } else if(!strcmp(command,"guest-ping")) {
            if(has_args && tokens[args].next!=args+1)error="guest-ping takes no arguments";
        } else if(!strcmp(command,"guest-info")) {
            if(has_args && tokens[args].next!=args+1)error="guest-info takes no arguments";
            else { capabilities(context,information);result=information; }
        } else if(!strcmp(command,"guest-shutdown")) {
            char mode[16];size_t mode_token,mode_bytes;int found=has_args?agent_json_member(&j,args,"mode",&mode_token):0;
            strcpy(mode,"powerdown");
            if(found<0 || (found && (agent_json_string(&j,mode_token,mode,sizeof(mode),&mode_bytes) || strlen(mode)!=mode_bytes)))error="Invalid shutdown mode";
            else if(!strcmp(mode,"powerdown"))error="OPENSTEP supports halt or reboot, not machine powerdown";
            else if(strcmp(mode,"halt") && strcmp(mode,"reboot"))error="Invalid shutdown mode";
            else if(!context || !context->shutdown)error="Shutdown is unavailable in this process";
            else if(context->shutdown_pending)error="Shutdown is already pending";
            else if(context->shutdown(mode))error="Unable to launch native shutdown program";
            else { context->shutdown_pending=1;*written=0;return 0; }
        } else if(!strcmp(command,"guest-get-time") || !strcmp(command,"guest-get-host-name")) {
            if(has_args && tokens[args].next!=args+1)error="Information command takes no arguments";
            else { agent_info_request(command,information,sizeof(information),&error);result=information; }
        } else if(context && agent_exec_request(&context->exec,command,&j,args,has_args,&result,&error)) {
        } else if(context && agent_files_request(&context->files,command,&j,args,has_args,&result,&error)) {
        } else { error="Command is not supported";error_class="CommandNotFound"; }
    }
    /* Failed parsing/member validation must not leave an untrusted ID span. */
    if(error && (!strcmp(error,"Invalid JSON request") || !strcmp(error,"Invalid request members")))has_id=0;
    if(delimited)append(&r,"\xff",1);
    if(error) {
        literal(&r,"{\"error\":{\"class\":\"");literal(&r,error_class);
        literal(&r,"\",\"desc\":\"");literal(&r,error);literal(&r,"\"}");
    } else {
        literal(&r,"{\"return\":");
        if(result)literal(&r,result);
        else append(&r,input+tokens[sync].start,tokens[sync].end-tokens[sync].start);
    }
    if(has_id==1) {
        literal(&r,",\"id\":");append(&r,input+tokens[id].start,tokens[id].end-tokens[id].start);
    }
    literal(&r,"}\n");if(r.failed)return -1;
    *written=r.count;return 0;
}

int agent_protocol_request(const char *input,size_t bytes,char *output,size_t capacity,size_t *written)
{
    static struct agent_protocol context;static int initialized;
    if(!initialized) { agent_protocol_init(&context);initialized=1; }
    return agent_protocol_request_context(&context,input,bytes,output,capacity,written);
}
