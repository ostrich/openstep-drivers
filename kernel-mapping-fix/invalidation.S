/* OPENSTEP 4.2 Intel kernel, exact image selected by patch.py.
 * The original segment layout and pmap structure offsets are unchanged.
 */
.code32
.global flush_removed_ptes
.global flush_retired_table

/* Replaces pmap_remove_range's call to pmap_deallocate_mappings.
 * EBP is still the caller's frame: pmap/start/end at +8/+12/+16.
 * Original cdecl arguments and return address remain on the stack.
 * Only caller-clobbered EAX/ECX/EDX and flags are changed.
 */
flush_removed_ptes:
 movl 8(%ebp),%eax
 cmpl 0x1f63f0,%eax              /* kernel_pmap */
 je ptes_active
 cmpl $0,0x18(%eax)             /* pmap->cpus_using */
 je ptes_done
ptes_active:
 movl 12(%ebp),%edx
 cmpl 16(%ebp),%edx
 jae ptes_done
 incl 0x1f7af0                  /* tlb_stat.total */
 movl 16(%ebp),%ecx
 subl %edx,%ecx
 cmpl 0x1e0d0c,%ecx             /* native PAGE_SIZE threshold */
 ja ptes_full_flush
 incl 0x1f7af4                  /* tlb_stat.single */
 cmpl 0x1f63f0,%eax
 jne ptes_user_loop
ptes_kernel_loop:
 invlpg (%edx)
 addl $4096,%edx
 jc ptes_done
 cmpl 16(%ebp),%edx
 jb ptes_kernel_loop
 jmp ptes_done
ptes_user_loop:
 invlpg %fs:(%edx)
 addl $4096,%edx
 jc ptes_done
 cmpl 16(%ebp),%edx
 jb ptes_user_loop
 jmp ptes_done
ptes_full_flush:
 movl %cr3,%eax
 movl %eax,%cr3
ptes_done:
 jmp 0x190f90                   /* original pmap_deallocate_mappings */

/* Runs after an empty table's PDEs are cleared, before the table is
 * unlinked from the active list or published on the free list.
 * This is a mid-function jump: preserve every register and EFLAGS.
 */
flush_retired_table:
 pushfl
 pushal
 movl 8(%ebp),%eax
 cmpl 0x1f63f0,%eax
 je table_active
 cmpl $0,0x18(%eax)
 je table_done
 table_active:
 incl 0x1f7af0
 movl %cr3,%eax
 movl %eax,%cr3
 table_done:
 popal
 popfl
 /* Replay the two displaced instructions verbatim. */
 movl (%ebx),%eax
 movl 4(%ebx),%ecx
 jmp 0x191052
