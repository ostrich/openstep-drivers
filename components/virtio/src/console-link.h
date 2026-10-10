/* MIT license. Single-port control policy, serialized by the driver.
 * No DMA or peer-delivery guarantee. A generation change invalidates user sessions. */
#ifndef OS42_CONSOLE_LINK_H
#define OS42_CONSOLE_LINK_H
#define VC_PORT_ID 1U
#define VC_LINK_CLEAR 1
#define VC_LINK_READY 2
#define VC_LINK_OPEN 4
struct vc_link { unsigned present,host_open,generation; };
static void vc_link_next(struct vc_link *s)
{ s->generation++;if(!s->generation)s->generation=1; }
static void vc_link_init(struct vc_link *s)
{ s->present=0;s->host_open=0;s->generation=1; }
static void vc_link_reset(struct vc_link *s)
{ vc_link_next(s);s->present=0;s->host_open=0; }
/* -1 malformed/incompatible, -2 unsupported port, 0 ignored, positive action bits.
 * Caller handles CLEAR before delivering data completions from the same IRQ.
 * CLEAR invalidates software data/session state, not DMA ownership. Outstanding
 * descriptors remain device-owned until completion or acknowledged reset. */
static int vc_link_control_port(struct vc_link *s,unsigned port_id,const unsigned char *packet,unsigned bytes)
{
    unsigned id,event,value;
    if(!packet || bytes<8)return -1;
    id=(unsigned)packet[0]|((unsigned)packet[1]<<8)|((unsigned)packet[2]<<16)|((unsigned)packet[3]<<24);
    event=(unsigned)packet[4]|((unsigned)packet[5]<<8);
    value=(unsigned)packet[6]|((unsigned)packet[7]<<8);
    if(!port_id || id!=port_id)return -2;
    if(event==1) {
        if(bytes!=8 || value!=1)return -1;
        if(s->present)return VC_LINK_READY|VC_LINK_OPEN;
        vc_link_next(s);s->present=1;s->host_open=0;
        return VC_LINK_CLEAR|VC_LINK_READY|VC_LINK_OPEN;
    }
    if(event==2) {
        if(bytes!=8 || value!=1)return -1;
        if(!s->present)return 0;
        vc_link_next(s);s->present=0;s->host_open=0;return VC_LINK_CLEAR;
    }
    if(event==6) {
        if(bytes!=8 || value>1)return -1;
        /* A host chardev callback can enqueue OPEN before PORT_ADD, even
         * during discovery/reset. Do not expose a data session yet. Sending
         * PORT_READY after ADD obtains the current connected state again. */
        if(!s->present)return 0;
        if(s->host_open==value)return 0;
        vc_link_next(s);s->host_open=value;return VC_LINK_CLEAR;
    }
    /* This channel requires virtserialport, whose backpressure differs from console. */
    if(event==4)return -1;
    if(event==7) {
        if(bytes<9 || packet[bytes-1]!=0)return -1;
        return 0;
    }
    return 0;
}
/* Preserve the existing single-port API for shipped drivers and utilities. */
static int vc_link_control(struct vc_link *s,const unsigned char *packet,unsigned bytes)
{ return vc_link_control_port(s,VC_PORT_ID,packet,bytes); }
static void vc_control_encode(unsigned char *packet,unsigned event,unsigned value,unsigned id)
{
    packet[0]=id;packet[1]=id>>8;packet[2]=id>>16;packet[3]=id>>24;
    packet[4]=event;packet[5]=event>>8;packet[6]=value;packet[7]=value>>8;
}
#endif
