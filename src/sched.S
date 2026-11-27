.equ MAX_TASKS, 8
.equ FIRST_DYNAMIC, 4
.equ TCB_SHIFT, 6
.equ TCB_STATE, 8
.equ TCB_ID, 16
.equ TCB_SWITCHES, 24
.equ TCB_TICKS, 32
.equ TCB_NAME, 40
.equ TCB_AFFINITY, 48
.equ TCB_LAST_CPU, 52
.equ TCB_WAKE_TICK, 56
.equ READY, 1
.equ RUNNING, 2
.equ SLEEPING, 3
.equ MAX_SLEEP_TICKS, 0x7fffffffffffffff

.section .bss, "aw", @nobits
.balign 4
.global sched_lock
sched_lock:
    .word 0
.balign 8
sched_ready:
    .quad 0
current_task:
    .quad 0, 0, 0, 0
.balign 16
tcb_table:
    .skip 512
.balign 16
task_stacks:
    .skip 16384

.section .rodata, "a"
.balign 8
.Lpinned_names:
    .quad .Lshell_name, .Lidle1, .Lidle2, .Lidle3
.Lshell_name: .asciz "shell"
.Lidle1:      .asciz "idle-1"
.Lidle2:      .asciz "idle-2"
.Lidle3:      .asciz "idle-3"

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

// ABI: Boot CPU, IRQs masked. Clobbers caller-saved registers and NZCV.
sched_init:
    stp x29, x30, [sp, #-16]!
    adr x0, sched_lock
    str wzr, [x0]
    bl spin_lock
    adr x1, tcb_table
    mov x2, #(MAX_TASKS << TCB_SHIFT)
.Lclear_table:
    stp xzr, xzr, [x1], #16
    subs x2, x2, #16
    b.ne .Lclear_table

    adr x1, current_task
    mov x2, #1
    mov x3, #2
    mov x4, #3
    stp xzr, x2, [x1]
    stp x3, x4, [x1, #16]
    mov x0, #0
    bl .Linit_pinned
    adr x1, sched_ready
    mov x2, #1
    stlr x2, [x1]
    adr x0, sched_lock
    bl spin_unlock
    ldp x29, x30, [sp], #16
    ret
.size sched_init, . - sched_init

.global sched_register_idle
.type sched_register_idle, %function

// ABI: Secondary CPU ID in x0, IRQs masked. Clobbers caller-saved registers and NZCV.
sched_register_idle:
    stp x19, x30, [sp, #-16]!
    mov x19, x0
    adr x0, sched_lock
    bl spin_lock
    mov x0, x19
    bl .Linit_pinned
    adr x0, sched_lock
    bl spin_unlock
    ldp x19, x30, [sp], #16
    ret
.size sched_register_idle, . - sched_register_idle

// ABI: CPU ID in x0, sched_lock held. Clobbers x1–x4.
.Linit_pinned:
    adr x1, current_task
    str x0, [x1, x0, lsl #3]
    adr x1, tcb_table
    add x1, x1, x0, lsl #TCB_SHIFT
    mov x2, #RUNNING
    stp x2, x0, [x1, #TCB_STATE]
    mov x3, #1
    stp x3, xzr, [x1, #TCB_SWITCHES]
    adr x4, .Lpinned_names
    ldr x4, [x4, x0, lsl #3]
    str x4, [x1, #TCB_NAME]
    stp w0, w0, [x1, #TCB_AFFINITY]
    ret

.global sched_spawn
.type sched_spawn, %function

// ABI: Name, entry and argument in x0–x2. Returns ID or -1 in x0. Preserves DAIF and callee-saved registers.
sched_spawn:
    stp x19, x20, [sp, #-48]!
    stp x21, x22, [sp, #16]
    stp x23, x30, [sp, #32]
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mrs x22, daif
    msr daifset, #2
    isb
    adr x0, sched_lock
    bl spin_lock
    adr x4, tcb_table
    mov x23, #FIRST_DYNAMIC
.Lfind_slot:
    add x6, x4, x23, lsl #TCB_SHIFT
    ldr x7, [x6, #TCB_STATE]
    cbz x7, .Lspawn_slot
    add x23, x23, #1
    cmp x23, #MAX_TASKS
    b.lo .Lfind_slot
    mov x23, #-1
    b .Lspawn_unlock
.Lspawn_slot:
    sub x5, x23, #(FIRST_DYNAMIC - 1)
    adr x7, task_stacks
    add x7, x7, x5, lsl #12
    sub x7, x7, #96
    stp x21, x20, [x7]
    stp xzr, xzr, [x7, #16]
    stp xzr, xzr, [x7, #32]
    stp xzr, xzr, [x7, #48]
    stp xzr, xzr, [x7, #64]
    adr x8, task_trampoline
    stp xzr, x8, [x7, #80]

    mov x9, #READY
    stp x7, x9, [x6]
    stp x23, xzr, [x6, #TCB_ID]
    stp xzr, x19, [x6, #TCB_TICKS]
    mov w9, #-1
    stp w9, wzr, [x6, #TCB_AFFINITY]
    str xzr, [x6, #TCB_WAKE_TICK]
.Lspawn_unlock:
    adr x0, sched_lock
    bl spin_unlock
    tbnz x23, #63, .Lspawn_done
    mov w0, #0
    mov w1, #0x0e
    bl gic_send_sgi
.Lspawn_done:
    msr daif, x22
    isb
    mov x0, x23
    ldp x23, x30, [sp, #32]
    ldp x21, x22, [sp, #16]
    ldp x19, x20, [sp], #48
    ret
.size sched_spawn, . - sched_spawn

// ABI: CPU in w0, current TCB in x1, sched_lock held. Returns eligible TCB or zero in x0. Clobbers x2–x7 and NZCV.
.Lpick_next:
    adr x2, tcb_table
    ldr x3, [x1, #TCB_ID]
    mov w4, #MAX_TASKS
.Lscan_ready:
    add x3, x3, #1
    and x3, x3, #(MAX_TASKS - 1)
    add x5, x2, x3, lsl #TCB_SHIFT
    ldr x6, [x5, #TCB_STATE]
    cmp x6, #READY
    b.ne .Lskip_slot
    ldr w7, [x5, #TCB_AFFINITY]
    cmn w7, #1
    ccmp w7, w0, #4, ne
    b.eq .Lfound_ready
.Lskip_slot:
    subs w4, w4, #1
    b.ne .Lscan_ready
    mov x0, #0
    ret
.Lfound_ready:
    mov x0, x5
    ret

.macro sched_enter
    stp x19, x20, [sp, #-48]!
    stp x21, x22, [sp, #16]
    stp x29, x30, [sp, #32]
    mrs x21, daif
    msr daifset, #2
    isb
.endm

.macro lock_current
    mrs x19, mpidr_el1
    and x19, x19, #0xff
    adr x0, sched_lock
    bl spin_lock
    adr x1, current_task
    ldr x1, [x1, x19, lsl #3]
    adr x20, tcb_table
    add x20, x20, x1, lsl #TCB_SHIFT
.endm

.global sched_yield
.type sched_yield, %function

// ABI: Preserves DAIF and callee-saved registers. Clobbers caller-saved registers and NZCV.
sched_yield:
    sched_enter
    lock_current
    bl .Lreschedule
    b .Lsched_return
.size sched_yield, . - sched_yield

.global sched_sleep
.type sched_sleep, %function

// ABI: Duration in x0. Preserves DAIF and callee-saved registers. Clobbers caller-saved registers and NZCV.
sched_sleep:
    cbz x0, sched_yield
    sched_enter
    mov x22, #MAX_SLEEP_TICKS
    cmp x0, x22
    csel x22, x0, x22, ls
    bl timer_get_ticks
    add x22, x22, x0
    lock_current
    str x22, [x20, #TCB_WAKE_TICK]
    mov x0, #SLEEPING
    str x0, [x20, #TCB_STATE]
    bl .Lreschedule
    ldr w0, [x20, #TCB_AFFINITY]
    tbnz w0, #31, .Lsched_return
.Lfallback_wait:
    bl timer_get_ticks
    sub x0, x0, x22
    cmp x0, #0
    b.ge .Lsched_return
    wfi
    msr daifclr, #2
    isb
    msr daifset, #2
    isb
    b .Lfallback_wait
.size sched_sleep, . - sched_sleep

.global sched_on_tick
.type sched_on_tick, %function

// ABI: Called with IRQs masked. Clobbers caller-saved registers and NZCV.
sched_on_tick:
    adr x0, sched_ready
    ldar x0, [x0]
    cbnz x0, .Ltick_ready
    ret
.Ltick_ready:
    sched_enter
    lock_current
    cbnz x19, .Lcharge_tick
    bl timer_get_ticks
    adr x1, tcb_table
    mov x5, #MAX_TASKS
.Lwake_sleepers:
    ldr x3, [x1, #TCB_STATE]
    cmp x3, #SLEEPING
    b.ne .Lnext_sleeper
    ldr x2, [x1, #TCB_WAKE_TICK]
    sub x3, x0, x2
    cmp x3, #0
    b.lt .Lnext_sleeper
    mov x4, #READY
    str x4, [x1, #TCB_STATE]
.Lnext_sleeper:
    add x1, x1, #(1 << TCB_SHIFT)
    subs x5, x5, #1
    b.ne .Lwake_sleepers
.Lcharge_tick:
    ldr x0, [x20, #TCB_TICKS]
    add x0, x0, #1
    str x0, [x20, #TCB_TICKS]
    str w19, [x20, #TCB_LAST_CPU]
    bl .Lreschedule
.Lsched_return:
    msr daif, x21
    isb
    ldp x29, x30, [sp, #32]
    ldp x21, x22, [sp, #16]
    ldp x19, x20, [sp], #48
    ret
.size sched_on_tick, . - sched_on_tick

// ABI: CPU in x19, current TCB in x20, IRQs masked and sched_lock held. Releases lock on the incoming stack.
.Lreschedule:
    stp x29, x30, [sp, #-16]!
    mov w0, w19
    mov x1, x20
    bl .Lpick_next
    ldr x2, [x20, #TCB_STATE]
    cmp x2, #RUNNING
    b.ne .Lblocked
    cbz x0, .Lunlock
    mov x2, #READY
    str x2, [x20, #TCB_STATE]
    b .Lswitch_in
.Lblocked:
    cbnz x0, .Lswitch_in
    adr x0, tcb_table
    add x0, x0, x19, lsl #TCB_SHIFT
.Lswitch_in:
    mov x2, #RUNNING
    str x2, [x0, #TCB_STATE]
    cmp x0, x20
    b.eq .Lunlock
    str w19, [x0, #TCB_LAST_CPU]
    ldr x2, [x0, #TCB_SWITCHES]
    add x2, x2, #1
    str x2, [x0, #TCB_SWITCHES]
    ldr x2, [x0, #TCB_ID]
    adr x3, current_task
    str x2, [x3, x19, lsl #3]
    ldr x1, [x0]
    mov x0, x20
    bl context_switch
.Lunlock:
    adr x0, sched_lock
    bl spin_unlock
    ldp x29, x30, [sp], #16
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

// ABI: Argument in x19, entry in x20, sched_lock held. Never returns.
task_trampoline:
    adr x0, sched_lock
    bl spin_unlock
    msr daifclr, #2
    isb
    mov x0, x19
    blr x20
    msr daifset, #2
    isb
    lock_current
    str xzr, [x20, #TCB_STATE]
    bl .Lreschedule
.Lexited:
    wfe
    b .Lexited
.size task_trampoline, . - task_trampoline
