/* MIT license. Bounded partial-frame and terminal-I/O waits. */
#ifndef OS42_PTY_TIMEOUT_H
#define OS42_PTY_TIMEOUT_H
struct pty_timeout { long began;unsigned polls,active; };
void pty_timeout_clear(struct pty_timeout *timeout);
/* A blocked operation has 30 seconds to finish, not 30 seconds per byte.
 * Idle sessions do not expire. Backward clock changes fail the wait; a finite
 * poll bound also prevents a frozen guest clock from retaining it forever. */
int pty_timeout_watch(struct pty_timeout *timeout,long now,int blocked);
#endif
