/* Diagnostic-only fixed-memory trace. MIT license, like the driver. */
#ifndef OPENSTEP_BLOCK_FLIGHT_TRACE_H
#define OPENSTEP_BLOCK_FLIGHT_TRACE_H
#define VB_FLIGHT_SLOTS 8192
struct vb_flight_record { unsigned sequence,event,a,b,c,d,e,f; };
struct vb_flight_ring {
    unsigned magic[2],version,slots;
    volatile unsigned next;
    unsigned record_words;
    volatile struct vb_flight_record records[VB_FLIGHT_SLOTS];
};
/* In-memory "VBFLT001" marker. Records contain metadata, not disk payloads. */
static struct vb_flight_ring blkFlight = {
    {0x4c464256,0x31303054},1,VB_FLIGHT_SLOTS,0,8,
    {{0,0,0,0,0,0,0,0}}
};
static void vbFlight(unsigned event,unsigned a,unsigned b,unsigned c,
                     unsigned d,unsigned e,unsigned f)
{
    unsigned sequence=1;
    volatile struct vb_flight_record *record;
    /* Reservation may be preempted by the threaded completion handler.
     * No allocation, Objective-C call, blocking or console output. */
    __asm__ volatile("lock; xaddl %0,%1" : "=r"(sequence),"=m"(blkFlight.next)
                     : "0"(sequence),"m"(blkFlight.next) : "memory","cc");
    record=&blkFlight.records[sequence&(VB_FLIGHT_SLOTS-1)];
    record->sequence=0;
    record->event=event;record->a=a;record->b=b;record->c=c;
    record->d=d;record->e=e;record->f=f;
    __asm__ volatile("" : : : "memory");
    record->sequence=sequence+1;
}
#endif
