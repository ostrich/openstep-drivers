typedef unsigned long vm_address_t;
#define IO_R_SUCCESS 0
int IOPhysicalFromVirtual(void *,vm_address_t,unsigned *);
void *IOVmTaskSelf(void);
