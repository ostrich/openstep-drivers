# Entered at probePCIController:+0x3d5, after Bus Master option parsing.
# EBX=self, EBP=original frame, EAX=option string (or NULL).
.code32
.text
.globl bm_entry
bm_entry:
    test %eax,%eax
    jz resume
    cmpb $'Y',(%eax)
    je enable
    cmpb $'y',(%eax)
    jne resume
 enable:
    movb $0,0x5e8(%ebx)
    # getPCIConfigData:&word atRegister:4 withDeviceDescription:descriptor
    push 0x10(%ebp)
    push $4
    lea -8(%ebp),%eax
    push %eax
    pushl get_selector
    push -0x10(%ebp)
    call objc_msgSend
    add $20,%esp
    test %eax,%eax
    jnz resume
    testb $1,-8(%ebp)
    jz resume
    # Only write command bits; writing back PCI status could clear W1C bits.
    movzwl -8(%ebp),%eax
    or $4,%eax
    push 0x10(%ebp)
    push $4
    push %eax
    pushl set_selector
    push -0x10(%ebp)
    call objc_msgSend
    add $20,%esp
    test %eax,%eax
    jnz resume
    push 0x10(%ebp)
    push $4
    lea -8(%ebp),%eax
    push %eax
    pushl get_selector
    push -0x10(%ebp)
    call objc_msgSend
    add $20,%esp
    test %eax,%eax
    jnz resume
    mov -8(%ebp),%eax
    and $5,%eax
    cmp $5,%eax
    jne resume
    movb $1,0x5e8(%ebx)
 resume:
    cmpb $0,0x5e8(%ebx)
    jmp resume_target
