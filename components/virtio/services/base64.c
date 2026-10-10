/* MIT license. No allocation, locale dependency or implicit string lengths. */
#include "base64.h"
static const char alphabet[]="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static int digit(unsigned char c)
{
    if(c>='A' && c<='Z')return c-'A';
    if(c>='a' && c<='z')return c-'a'+26;
    if(c>='0' && c<='9')return c-'0'+52;
    if(c=='+')return 62;
    if(c=='/')return 63;
    return -1;
}
int agent_base64_encode(const unsigned char *src,size_t bytes,char *dst,
                        size_t capacity,size_t *written)
{
    size_t i=0,n=0,groups;unsigned a,b,c;
    if(!written)return -1;
    *written=0;
    if((bytes && !src) || (capacity && !dst))return -1;
    groups=bytes/3+(bytes%3!=0);
    if(groups>capacity/4)return -1;
    while(i<bytes) {
        a=src[i++];b=i<bytes?src[i++]:0;c=i<bytes?src[i++]:0;
        dst[n++]=alphabet[a>>2];dst[n++]=alphabet[((a&3)<<4)|(b>>4)];
        dst[n++]=alphabet[((b&15)<<2)|(c>>6)];dst[n++]=alphabet[c&63];
    }
    if(bytes%3) { dst[n-1]='=';if(bytes%3==1)dst[n-2]='='; }
    *written=n;return 0;
}
int agent_base64_decode(const char *src,size_t bytes,unsigned char *dst,
                        size_t capacity,size_t *written)
{
    size_t i,n=0,needed;int a,b,c,d;unsigned padding=0;
    if(!written)return -1;
    *written=0;
    if((bytes && !src) || (capacity && !dst) || bytes%4)return -1;
    if(!bytes)return 0;
    if(src[bytes-1]=='=')padding++;
    if(src[bytes-2]=='=')padding++;
    needed=(bytes/4)*3-padding;
    if(needed>capacity || (needed && !dst))return -1;
    for(i=0;i<bytes;i+=4) {
        a=digit(src[i]);b=digit(src[i+1]);
        c=src[i+2]=='='?-2:digit(src[i+2]);d=src[i+3]=='='?-2:digit(src[i+3]);
        if(a<0 || b<0 || c==-1 || d==-1)return -1;
        if(c==-2) {
            if(d!=-2 || i+4!=bytes || (b&15))return -1;
        } else if(d==-2) {
            if(i+4!=bytes || (c&3))return -1;
        }
        dst[n++]=(unsigned char)((a<<2)|(b>>4));
        if(c>=0)dst[n++]=(unsigned char)((b<<4)|(c>>2));
        if(d>=0)dst[n++]=(unsigned char)((c<<6)|d);
    }
    *written=n;return 0;
}
