/* MIT license. Bounded binary codec for the guest-agent file/exec protocol. */
#ifndef OS42_AGENT_BASE64_H
#define OS42_AGENT_BASE64_H
#include <stddef.h>
/* Output size excludes NUL: the encoder does not append a terminator.
 * Return 0 on success, -1 on malformed input or insufficient capacity.
 * On failure *written is zero; callers must discard the destination. */
int agent_base64_encode(const unsigned char *src,size_t bytes,char *dst,
                        size_t capacity,size_t *written);
int agent_base64_decode(const char *src,size_t bytes,unsigned char *dst,
                        size_t capacity,size_t *written);
#endif
