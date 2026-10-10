#ifndef OS42_VIRTIO_LEGACY_PCI_H
#define OS42_VIRTIO_LEGACY_PCI_H
/* Standard legacy PCI offsets; no MSI-X enabled in this transport. */
#define VT_HOST_FEATURES 0
#define VT_GUEST_FEATURES 4
#define VT_QUEUE_PFN 8
#define VT_QUEUE_SIZE 12
#define VT_QUEUE_SELECT 14
#define VT_QUEUE_NOTIFY 16
#define VT_STATUS 18
#define VT_ISR 19
#define VT_ACK 1
#define VT_DRIVER 2
#define VT_READY 4
#define VT_FAILED 128
#endif
