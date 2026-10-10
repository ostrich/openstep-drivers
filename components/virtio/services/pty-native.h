/* MIT license. Native shell and controlling terminal lifecycle. */
#ifndef OS42_PTY_NATIVE_H
#define OS42_PTY_NATIVE_H
struct native_pty { int master,pid,exited,exitcode,signal_number;char slave[64]; };
void native_pty_init(struct native_pty *pty);
int native_pty_start(struct native_pty *pty,const char *shell,unsigned rows,unsigned columns);
int native_pty_resize(struct native_pty *pty,unsigned rows,unsigned columns);
void native_pty_poll(struct native_pty *pty);
/* HUP/TERM/KILL all processes attached to the owned PTY; close and reap.
 * Returns -1 if the kernel has not released the child within the bound. */
int native_pty_close(struct native_pty *pty);
#endif
