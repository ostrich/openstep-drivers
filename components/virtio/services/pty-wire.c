/* MIT license. Fixed little-endian header, arbitrary binary payloads. */
#include "pty-wire.h"
#include <string.h>
static const unsigned char magic[8]={'O','S','4','2','P','T','Y','1'};
unsigned pty_get32(const unsigned char *p)
{ return (unsigned)p[0]|((unsigned)p[1]<<8)|((unsigned)p[2]<<16)|((unsigned)p[3]<<24); }
void pty_put32(unsigned char *p,unsigned value)
{ p[0]=value;p[1]=value>>8;p[2]=value>>16;p[3]=value>>24; }
void pty_frame_clear(struct pty_frame *frame) { memset(frame,0,sizeof(*frame)); }
int pty_frame_byte(struct pty_frame *f,unsigned char byte)
{
    if(f->header_bytes<8) {
        if(byte==magic[f->header_bytes])f->header[f->header_bytes++]=byte;
        else { f->header_bytes=byte==magic[0]?1:0;if(f->header_bytes)f->header[0]=byte; }
        return 0;
    }
    if(f->header_bytes<PTY_HEADER_BYTES) {
        f->header[f->header_bytes++]=byte;
        if(f->header_bytes<PTY_HEADER_BYTES)return 0;
        f->type=pty_get32(f->header+8);f->length=pty_get32(f->header+12);
        if(f->type<PTY_HELLO || f->type>PTY_PONG || f->length>PTY_PAYLOAD_MAX) { pty_frame_clear(f);return -1; }
        return f->length==0?1:0;
    }
    if(f->payload_bytes>=f->length)return -1;
    f->payload[f->payload_bytes++]=byte;return f->payload_bytes==f->length?1:0;
}
unsigned pty_frame_encode(unsigned char *out,unsigned capacity,unsigned type,
                          const unsigned char *payload,unsigned length)
{
    if(type<PTY_HELLO || type>PTY_PONG || length>PTY_PAYLOAD_MAX || capacity<PTY_HEADER_BYTES+length || (length && !payload))return 0;
    memcpy(out,magic,8);pty_put32(out+8,type);pty_put32(out+12,length);
    if(length)memcpy(out+16,payload,length);
    return PTY_HEADER_BYTES+length;
}
