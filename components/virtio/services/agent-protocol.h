/* MIT license. Standard QGA request dispatcher, independent of transport. */
#ifndef OS42_AGENT_PROTOCOL_H
#define OS42_AGENT_PROTOCOL_H
#include <stddef.h>
#include "agent-files.h"
#include "agent-exec.h"
struct agent_protocol { struct agent_files files;struct agent_exec exec;int (*shutdown)(const char *mode);unsigned shutdown_pending; };
void agent_protocol_poll(struct agent_protocol *context);
void agent_protocol_init(struct agent_protocol *context);
void agent_protocol_clear(struct agent_protocol *context);
int agent_protocol_request_context(struct agent_protocol *context,const char *input,size_t bytes,
                                   char *output,size_t capacity,size_t *written);
/* Sync, sync-delimited, ping, info and regular-file operations. Returns 0 or -1 if the
 * response cannot fit. JSON/protocol errors produce standard error replies.
 * The output includes newline and, for sync-delimited, the 0xff sentinel. */
int agent_protocol_request(const char *input,size_t bytes,char *output,
                           size_t capacity,size_t *written);
#endif
