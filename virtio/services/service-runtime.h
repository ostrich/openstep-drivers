/* MIT license. Shared native daemon lifecycle; control is separate from virtio. */
#ifndef OS42_SERVICE_RUNTIME_H
#define OS42_SERVICE_RUNTIME_H
struct service_runtime {
    int listener,ack,stop_fd;
    char socket_path[104];
};
void service_runtime_init(struct service_runtime *runtime);
/* Returns 1 to continue daemon initialization, 0 for a completed command,
 * 3 for stopped status, or -1 on failure. A --start parent waits for ready(). */
int service_runtime_command(struct service_runtime *runtime,const char *directory,
                            const char *name,const char *command);
/* Caller must already hold its exclusive transport lock before this call.
 * Removes only a stale root-owned control socket for that same service. */
int service_runtime_ready(struct service_runtime *runtime);
/* Poll without waiting for connections; returns 1 for a stop request, 0 idle,
 * -1 for an unexpected control error. Each accepted request is bounded. */
int service_runtime_poll(struct service_runtime *runtime);
/* Remove the control endpoint while the transport lock is still held. */
void service_runtime_quiesce(struct service_runtime *runtime);
void service_runtime_close(struct service_runtime *runtime);
/* Complete a stop request with failure if resource cleanup did not succeed. */
void service_runtime_close_result(struct service_runtime *runtime,int failed);
#endif
