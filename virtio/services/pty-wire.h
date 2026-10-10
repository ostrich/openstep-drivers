/* MIT license. Separate PTY protocol; not QEMU guest-agent extensions. */
#ifndef OS42_PTY_WIRE_H
#define OS42_PTY_WIRE_H
#define PTY_PAYLOAD_MAX 4096U
#define PTY_HEADER_BYTES 16U
#define PTY_HELLO 1U
#define PTY_READY 2U
#define PTY_INPUT 3U
#define PTY_OUTPUT 4U
#define PTY_RESIZE 5U
#define PTY_CLOSE 6U
#define PTY_EXIT 7U
#define PTY_ERROR 8U
#define PTY_PING 9U
#define PTY_PONG 10U
struct pty_frame {
    unsigned char header[PTY_HEADER_BYTES],payload[PTY_PAYLOAD_MAX];
    unsigned header_bytes,payload_bytes,type,length;
};
void pty_frame_clear(struct pty_frame *frame);
/* Streaming magic reacquisition. Returns 1 frame, 0 incomplete, -1 malformed
 * header; caller stops the old session on error. Reacquisition never dispatches
 * bytes until the entire bounded frame is present. */
int pty_frame_byte(struct pty_frame *frame,unsigned char byte);
unsigned pty_frame_encode(unsigned char *out,unsigned capacity,unsigned type,
                          const unsigned char *payload,unsigned length);
unsigned pty_get32(const unsigned char *p);
void pty_put32(unsigned char *p,unsigned value);
#endif
