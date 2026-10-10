/* MIT license. Connection-scoped, bounded standard guest-file operations. */
#ifndef OS42_AGENT_FILES_H
#define OS42_AGENT_FILES_H
#include "agent-json.h"
#define AGENT_FILE_LIMIT 16
#define AGENT_FILE_CHUNK 32768
struct agent_files {
    int descriptors[AGENT_FILE_LIMIT];unsigned handles[AGENT_FILE_LIMIT],next_handle;
    unsigned char bytes[AGENT_FILE_CHUNK];char encoded[43693],result[45000];
};
void agent_files_init(struct agent_files *files);
void agent_files_clear(struct agent_files *files);
/* 1 handled, 0 unknown. On handled error *error is a fixed ASCII description;
 * on success *result is JSON valid until the next operation. */
int agent_files_request(struct agent_files *files,const char *command,
                        const struct agent_json *json,size_t args,int has_args,
                        const char **result,const char **error);
#endif
