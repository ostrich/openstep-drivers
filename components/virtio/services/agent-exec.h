/* MIT license. Bounded asynchronous standard guest-exec operations. */
#ifndef OS42_AGENT_EXEC_H
#define OS42_AGENT_EXEC_H
#include "agent-json.h"
#define AGENT_EXEC_LIMIT 8
#define AGENT_EXEC_CAPTURE 16384
struct agent_job {
    int pid,exited,exitcode,signal_number,abandoned,fd[3];
    unsigned mode,size[2],truncated[2],input_count,input_cursor,ticks,exit_ticks;
    long deadline;
    unsigned char input[32768],output[2][AGENT_EXEC_CAPTURE];
};
struct agent_exec {
    struct agent_job jobs[AGENT_EXEC_LIMIT];
    char arguments[8192],environment[8192],path[1024],encoded[43693],result[45000];
    char *argv[34],*envp[65];
};
void agent_exec_init(struct agent_exec *exec);
void agent_exec_poll(struct agent_exec *exec);
/* TERM then KILL owned running groups, bounded reap; delayed kernel exits stay
 * tracked as abandoned until reaped. Returns number still awaiting kernel exit. */
unsigned agent_exec_clear(struct agent_exec *exec);
int agent_exec_request(struct agent_exec *exec,const char *command,
                       const struct agent_json *json,size_t args,int has_args,
                       const char **result,const char **error);
#endif
