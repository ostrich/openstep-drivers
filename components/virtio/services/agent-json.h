/* MIT license. Allocation-free JSON parser for bounded agent requests. */
#ifndef OS42_AGENT_JSON_H
#define OS42_AGENT_JSON_H
#include <stddef.h>
enum agent_json_type { AJ_OBJECT,AJ_ARRAY,AJ_STRING,AJ_NUMBER,AJ_TRUE,AJ_FALSE,AJ_NULL };
struct agent_json_token { enum agent_json_type type;size_t start,end,next; };
struct agent_json {
    const char *text;size_t bytes,pos,count,capacity;
    struct agent_json_token *tokens;
};
/* Returns 0 or -1. Entire input must be one valid JSON value, depth <=32.
 * Token offsets refer to the caller's unchanged input. No floating point
 * conversion: signed 64-bit guest-sync IDs retain their exact value. */
int agent_json_parse(struct agent_json *j,const char *text,size_t bytes,
                     struct agent_json_token *tokens,size_t capacity);
/* Decode a string to UTF-8, including surrogate pairs, then append NUL.
 * Embedded NUL is preserved in *written; path/command users must reject it. */
int agent_json_string(const struct agent_json *j,size_t token,char *out,
                      size_t capacity,size_t *written);
int agent_json_integer(const struct agent_json *j,size_t token,long long *out);
/* Find an ASCII member name; reject duplicate occurrences of that name.
 * 1 found, 0 absent, -1 invalid or ambiguous. */
int agent_json_member(const struct agent_json *j,size_t object,const char *name,
                      size_t *value);
#endif
