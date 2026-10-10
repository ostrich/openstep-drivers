/* MIT license. Caller supplies guest wall-clock seconds and operation state. */
#include "pty-timeout.h"
#include <string.h>
void pty_timeout_clear(struct pty_timeout *t) { memset(t,0,sizeof(*t)); }
int pty_timeout_watch(struct pty_timeout *t,long now,int blocked)
{
    if(!blocked) { pty_timeout_clear(t);return 0; }
    if(!t->active) { t->active=1;t->began=now;t->polls=0; }
    return now<t->began || (unsigned long)now-(unsigned long)t->began>=30UL || ++t->polls>=30000;
}
