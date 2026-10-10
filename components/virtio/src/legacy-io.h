#ifndef OS42_VIRTIO_LEGACY_IO_H
#define OS42_VIRTIO_LEGACY_IO_H
/* Native i386 port I/O helpers for all legacy PCI device drivers. */
static unsigned char rd8(unsigned short p) { unsigned char x;__asm__ volatile("inb %%dx,%%al":"=a"(x):"d"(p));return x; }
static unsigned short rd16(unsigned short p) { unsigned short x;__asm__ volatile("inw %%dx,%%ax":"=a"(x):"d"(p));return x; }
static unsigned rd32(unsigned short p) { unsigned x;__asm__ volatile("inl %%dx,%%eax":"=a"(x):"d"(p));return x; }
static void wr8(unsigned short p,unsigned char x) { __asm__ volatile("outb %%al,%%dx" : : "a"(x),"d"(p):"memory"); }
static void wr16(unsigned short p,unsigned short x) { __asm__ volatile("outw %%ax,%%dx" : : "a"(x),"d"(p):"memory"); }
static void wr32(unsigned short p,unsigned x) { __asm__ volatile("outl %%eax,%%dx" : : "a"(x),"d"(p):"memory"); }
#endif
