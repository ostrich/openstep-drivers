/* MIT license. C89-compatible syntax with the native compiler's long long. */
#include "agent-json.h"
#include <string.h>
static int hex(unsigned char c)
{
    if(c>='0' && c<='9')return c-'0';
    if(c>='a' && c<='f')return c-'a'+10;
    if(c>='A' && c<='F')return c-'A'+10;
    return -1;
}
static void space(struct agent_json *j)
{
    while(j->pos<j->bytes && (j->text[j->pos]==' ' || j->text[j->pos]=='\n' ||
          j->text[j->pos]=='\r' || j->text[j->pos]=='\t'))j->pos++;
}
static int unicode(const char *text,size_t end,size_t *pos,unsigned *code)
{
    unsigned v=0,i;int n;
    if(end-*pos<4)return -1;
    for(i=0;i<4;i++) { n=hex(text[(*pos)++]);if(n<0)return -1;v=(v<<4)|n; }
    if(v>=0xd800 && v<=0xdbff) {
        unsigned low=0;
        if(end-*pos<6 || text[(*pos)++]!='\\' || text[(*pos)++]!='u')return -1;
        for(i=0;i<4;i++) { n=hex(text[(*pos)++]);if(n<0)return -1;low=(low<<4)|n; }
        if(low<0xdc00 || low>0xdfff)return -1;
        v=0x10000+((v-0xd800)<<10)+(low-0xdc00);
    } else if(v>=0xdc00 && v<=0xdfff)return -1;
    *code=v;return 0;
}
static int utf8(const char *text,size_t end,size_t *pos,unsigned *code)
{
    unsigned c=(unsigned char)text[(*pos)++],v,need,min,i,n;
    if(c<128) { *code=c;return 0; }
    if(c>=0xc2 && c<=0xdf) { need=1;v=c&31;min=128; }
    else if(c>=0xe0 && c<=0xef) { need=2;v=c&15;min=2048; }
    else if(c>=0xf0 && c<=0xf4) { need=3;v=c&7;min=65536; }
    else return -1;
    if(end-*pos<need)return -1;
    for(i=0;i<need;i++) { n=(unsigned char)text[(*pos)++];if((n&192)!=128)return -1;v=(v<<6)|(n&63); }
    if(v<min || v>0x10ffff || (v>=0xd800 && v<=0xdfff))return -1;
    *code=v;return 0;
}
static int string_code(const char *text,size_t end,size_t *pos,unsigned *code)
{
    unsigned c;
    if(*pos>=end)return -1;
    if(text[*pos]!='\\') {
        if((unsigned char)text[*pos]<32 || text[*pos]=='"')return -1;
        return utf8(text,end,pos,code);
    }
    (*pos)++;if(*pos>=end)return -1;c=(unsigned char)text[(*pos)++];
    if(c=='u')return unicode(text,end,pos,code);
    if(c=='"' || c=='\\' || c=='/')*code=c;
    else if(c=='b')*code=8;else if(c=='f')*code=12;
    else if(c=='n')*code=10;else if(c=='r')*code=13;else if(c=='t')*code=9;
    else return -1;
    return 0;
}
static int value(struct agent_json *j,unsigned depth);
static int string(struct agent_json *j)
{
    unsigned code;
    if(j->pos>=j->bytes || j->text[j->pos++]!='"')return -1;
    while(j->pos<j->bytes) {
        if(j->text[j->pos]=='"') { j->pos++;return 0; }
        if(string_code(j->text,j->bytes,&j->pos,&code))return -1;
    }
    return -1;
}
static int number(struct agent_json *j)
{
    size_t start;
    if(j->text[j->pos]=='-')j->pos++;
    if(j->pos>=j->bytes)return -1;
    if(j->text[j->pos]=='0')j->pos++;
    else {
        if(j->text[j->pos]<'1' || j->text[j->pos]>'9')return -1;
        while(j->pos<j->bytes && j->text[j->pos]>='0' && j->text[j->pos]<='9')j->pos++;
    }
    if(j->pos<j->bytes && j->text[j->pos]=='.') {
        start=++j->pos;
        while(j->pos<j->bytes && j->text[j->pos]>='0' && j->text[j->pos]<='9')j->pos++;
        if(start==j->pos)return -1;
    }
    if(j->pos<j->bytes && (j->text[j->pos]=='e' || j->text[j->pos]=='E')) {
        j->pos++;
        if(j->pos<j->bytes && (j->text[j->pos]=='+' || j->text[j->pos]=='-'))j->pos++;
        start=j->pos;
        while(j->pos<j->bytes && j->text[j->pos]>='0' && j->text[j->pos]<='9')j->pos++;
        if(start==j->pos)return -1;
    }
    return 0;
}
static int value(struct agent_json *j,unsigned depth)
{
    size_t token;char c,close;const char *literal=0;
    if(depth>32 || j->count>=j->capacity)return -1;
    space(j);if(j->pos>=j->bytes)return -1;
    token=j->count++;j->tokens[token].start=j->pos;c=j->text[j->pos];
    if(c=='{' || c=='[') {
        j->tokens[token].type=c=='{'?AJ_OBJECT:AJ_ARRAY;close=c=='{'?'}':']';j->pos++;space(j);
        if(j->pos<j->bytes && j->text[j->pos]==close)j->pos++;
        else for(;;) {
            if(c=='{') {
                space(j);if(j->pos>=j->bytes || j->text[j->pos]!='"' || value(j,depth+1))return -1;
                space(j);if(j->pos>=j->bytes || j->text[j->pos++]!=':')return -1;
            }
            if(value(j,depth+1))return -1;
            space(j);if(j->pos>=j->bytes)return -1;
            if(j->text[j->pos]==close) { j->pos++;break; }
            if(j->text[j->pos++]!=',')return -1;
        }
    } else if(c=='"') { j->tokens[token].type=AJ_STRING;if(string(j))return -1; }
    else if(c=='-' || (c>='0' && c<='9')) { j->tokens[token].type=AJ_NUMBER;if(number(j))return -1; }
    else {
        if(c=='t') { literal="true";j->tokens[token].type=AJ_TRUE; }
        else if(c=='f') { literal="false";j->tokens[token].type=AJ_FALSE; }
        else if(c=='n') { literal="null";j->tokens[token].type=AJ_NULL; }
        else return -1;
        if(j->bytes-j->pos<strlen(literal) || memcmp(j->text+j->pos,literal,strlen(literal)))return -1;
        j->pos+=strlen(literal);
    }
    j->tokens[token].end=j->pos;j->tokens[token].next=j->count;return 0;
}
int agent_json_parse(struct agent_json *j,const char *text,size_t bytes,
                     struct agent_json_token *tokens,size_t capacity)
{
    if(!j || !text || !tokens || !capacity)return -1;
    j->text=text;j->bytes=bytes;j->pos=j->count=0;j->capacity=capacity;j->tokens=tokens;
    if(value(j,0))return -1;
    space(j);return j->pos==bytes?0:-1;
}
int agent_json_string(const struct agent_json *j,size_t token,char *out,
                      size_t capacity,size_t *written)
{
    size_t p,end,n=0;unsigned code,bytes,i;unsigned char data[4];
    if(!written)return -1;
    *written=0;
    if(token>=j->count || j->tokens[token].type!=AJ_STRING || !out || !capacity)return -1;
    p=j->tokens[token].start+1;end=j->tokens[token].end-1;
    while(p<end) {
        if(string_code(j->text,end,&p,&code))return -1;
        if(code<128) { bytes=1;data[0]=code; }
        else if(code<2048) { bytes=2;data[0]=192|(code>>6);data[1]=128|(code&63); }
        else if(code<65536) { bytes=3;data[0]=224|(code>>12);data[1]=128|((code>>6)&63);data[2]=128|(code&63); }
        else { bytes=4;data[0]=240|(code>>18);data[1]=128|((code>>12)&63);data[2]=128|((code>>6)&63);data[3]=128|(code&63); }
        if(bytes>=capacity-n)return -1;
        for(i=0;i<bytes;i++)out[n++]=data[i];
    }
    out[n]=0;*written=n;return 0;
}
int agent_json_integer(const struct agent_json *j,size_t token,long long *out)
{
    size_t p,end;unsigned long long v=0,limit;unsigned digit;int negative=0;
    if(!out || token>=j->count || j->tokens[token].type!=AJ_NUMBER)return -1;
    p=j->tokens[token].start;end=j->tokens[token].end;
    if(j->text[p]=='-') { negative=1;p++; }
    limit=negative?9223372036854775808ULL:9223372036854775807ULL;
    while(p<end) {
        if(j->text[p]<'0' || j->text[p]>'9')return -1;
        digit=j->text[p++]-'0';if(v>(limit-digit)/10)return -1;v=v*10+digit;
    }
    if(!v)*out=0;
    else *out=negative?-(long long)(v-1)-1:(long long)v;
    return 0;
}
int agent_json_member(const struct agent_json *j,size_t object,const char *name,size_t *result)
{
    size_t i,bytes,found=0;char key[256];
    if(!name || !result || object>=j->count || j->tokens[object].type!=AJ_OBJECT)return -1;
    for(i=object+1;i<j->tokens[object].next;) {
        if(agent_json_string(j,i,key,sizeof(key),&bytes))return -1;
        if(strlen(key)!=bytes)return -1;
        if(!strcmp(key,name)) { if(found)return -1;*result=i+1;found=1; }
        i=j->tokens[i+1].next;
    }
    return (int)found;
}
