.equ MAX_TASKS, 4
.equ TCB_SHIFT, 6
.equ TCB_STATE, 8
.equ TCB_ID, 16
.equ TCB_SWITCHES, 24
.equ TCB_TICKS, 32
.equ TCB_NAME, 40
.equ READY, 1
.equ RUNNING, 2

.section .bss, "aw", @nobits
.balign 16
tcb_table:
    .skip MAX_TASKS << TCB_SHIFT
.balign 8
current_task_id:
    .quad 0
.balign 8
sched_ready:
    .quad 0
.balign 16
task_stacks:
    .skip 12288

.section .rodata, "a"
.Lshell_name:
    .asciz "shell"

.section .text, "ax"
.global context_switch
.type context_switch, %function

// ABI: Previous SP field in x0, incoming SP in x1. Clobbers x2.
context_switch:
    sub sp, sp, #96
    stp x19, x20, [sp, #0]
    stp x21, x22, [sp, #16]
    stp x23, x24, [sp, #32]
    stp x25, x26, [sp, #48]
    stp x27, x28, [sp, #64]
    stp x29, x30, [sp, #80]
    mov x2, sp
    str x2, [x0]
    mov sp, x1
    ldp x19, x20, [sp, #0]
    ldp x21, x22, [sp, #16]
    ldp x23, x24, [sp, #32]
    ldp x25, x26, [sp, #48]
    ldp x27, x28, [sp, #64]
    ldp x29, x30, [sp, #80]
    add sp, sp, #96
    ret
.size context_switch, . - context_switch

.global sched_init
.type sched_init, %function

// ABI: Called at boot with IRQs masked. Clobbers x0–x3 and NZCV.
sched_init:
    adr x0, tcb_table
    mov x1, x0
    mov x2, #(MAX_TASKS << TCB_SHIFT)
.Lclear_table:
    stp xzr, xzr, [x1], #16
    subs x2, x2, #16
    b.ne .Lclear_table

    mov x1, #RUNNING
    str x1, [x0, #TCB_STATE]
    mov x1, #1
    str x1, [x0, #TCB_SWITCHES]
    adr x2, .Lshell_name
    str x2, [x0, #TCB_NAME]
    adr x3, current_task_id
    str xzr, [x3]
    adr x3, sched_ready
    str x1, [x3]
    ret
.size sched_init, . - sched_init

.global sched_spawn
.type sched_spawn, %function

// ABI: Name, entry and argument in x0–x2. Returns ID or -1 in x0. Clobbers x3–x9 and NZCV.
sched_spawn:
    mrs x3, daif
    msr daifset, #2
    isb
    adr x4, tcb_table
    mov x5, #1
.Lfind_slot:
    add x6, x4, x5, lsl #TCB_SHIFT
    ldr x7, [x6, #TCB_STATE]
    cbz x7, .Lspawn_slot
    add x5, x5, #1
    cmp x5, #MAX_TASKS
    b.lo .Lfind_slot
    mov x0, #-1
    b .Lspawn_done

.Lspawn_slot:
    adr x7, task_stacks
    add x7, x7, x5, lsl #12
    sub x7, x7, #96
    stp x2, x1, [x7, #0]
    stp xzr, xzr, [x7, #16]
    stp xzr, xzr, [x7, #32]
    stp xzr, xzr, [x7, #48]
    stp xzr, xzr, [x7, #64]
    adr x8, task_trampoline
    stp xzr, x8, [x7, #80]

    mov x9, #READY
    stp x7, x9, [x6]
    stp x5, xzr, [x6, #TCB_ID]
    stp xzr, x0, [x6, #TCB_TICKS]
    mov x0, x5
.Lspawn_done:
    msr daif, x3
    isb
    ret
.size sched_spawn, . - sched_spawn

.global sched_yield
.type sched_yield, %function

// ABI: Preserves DAIF and callee-saved registers. Clobbers x0–x8 and NZCV.
sched_yield:
    mrs x0, daif
    msr daifset, #2
    isb
    stp x0, x30, [sp, #-16]!
    bl .Lround_robin
    ldp x0, x30, [sp], #16
    msr daif, x0
    isb
    ret
.size sched_yield, . - sched_yield

.global sched_on_tick
.type sched_on_tick, %function

// ABI: Called with IRQs masked. Clobbers x0–x8 and NZCV.
sched_on_tick:
    adr x0, sched_ready
    ldr x0, [x0]
    cbz x0, .Ltick_done
    adr x0, current_task_id
    ldr x1, [x0]
    adr x0, tcb_table
    add x0, x0, x1, lsl #TCB_SHIFT
    ldr x1, [x0, #TCB_TICKS]
    add x1, x1, #1
    str x1, [x0, #TCB_TICKS]
    b .Lround_robin
.Ltick_done:
    ret
.size sched_on_tick, . - sched_on_tick

// ABI: Called with IRQs masked. Clobbers x0–x8 and NZCV.
.Lround_robin:
    adr x2, tcb_table
    adr x3, current_task_id
    ldr x4, [x3]
    mov x5, x4
.Lfind_ready:
    add x5, x5, #1
    and x5, x5, #(MAX_TASKS - 1)
    cmp x5, x4
    b.eq .Lround_done
    add x6, x2, x5, lsl #TCB_SHIFT
    ldr x7, [x6, #TCB_STATE]
    cmp x7, #READY
    b.ne .Lfind_ready

    add x0, x2, x4, lsl #TCB_SHIFT
    ldr x8, [x0, #TCB_STATE]
    cbz x8, .Lswitch_in
    str x7, [x0, #TCB_STATE]
.Lswitch_in:
    mov x7, #RUNNING
    str x7, [x6, #TCB_STATE]
    ldr x8, [x6, #TCB_SWITCHES]
    add x8, x8, #1
    str x8, [x6, #TCB_SWITCHES]
    str x5, [x3]
    ldr x1, [x6]
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl context_switch
    ldp x29, x30, [sp], #16
.Lround_done:
    ret

.global sched_get_tcb
.type sched_get_tcb, %function

// ABI: ID in x0, TCB pointer or zero in x0. Clobbers x1 and NZCV.
sched_get_tcb:
    adr x1, tcb_table
    cmp x0, #MAX_TASKS
    add x0, x1, x0, lsl #TCB_SHIFT
    csel x0, x0, xzr, lo
    ret
.size sched_get_tcb, . - sched_get_tcb

.type task_trampoline, %function

// ABI: Argument in x19, entry in x20. Never returns.
task_trampoline:
    msr daifclr, #2
    isb
    mov x0, x19
    blr x20
    msr daifset, #2
    isb
    adr x0, current_task_id
    ldr x0, [x0]
    bl sched_get_tcb
    str xzr, [x0, #TCB_STATE]
    bl sched_yield
.Lexited:
    wfe
    b .Lexited
.size task_trampoline, . - task_trampoline
