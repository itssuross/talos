.section .text, "ax"
.global vectors
.type vectors, %object

.macro vector_slot id
    .balign 128
    sub sp, sp, #272
    stp x0, x1, [sp, #0]
    mov x0, #\id
    b .Lexception_common
.endm

.balign 2048
vectors:
    vector_slot 0
    vector_slot 1
    vector_slot 2
    vector_slot 3
    vector_slot 4
    .balign 128
    sub sp, sp, #272
    stp x0, x1, [sp, #0]
    b .Lirq_common
    vector_slot 6
    vector_slot 7
    .balign 128
    sub sp, sp, #272
    stp x0, x1, [sp, #0]
    b .Lel0_sync
    .balign 128
    sub sp, sp, #272
    stp x0, x1, [sp, #0]
    b .Lirq_common
    vector_slot 10
    vector_slot 11
    vector_slot 12
    vector_slot 13
    vector_slot 14
    vector_slot 15
    .balign 128
.size vectors, . - vectors

.macro save_x2_to_x29
    stp x2,  x3,  [sp, #16]
    stp x4,  x5,  [sp, #32]
    stp x6,  x7,  [sp, #48]
    stp x8,  x9,  [sp, #64]
    stp x10, x11, [sp, #80]
    stp x12, x13, [sp, #96]
    stp x14, x15, [sp, #112]
    stp x16, x17, [sp, #128]
    stp x18, x19, [sp, #144]
    stp x20, x21, [sp, #160]
    stp x22, x23, [sp, #176]
    stp x24, x25, [sp, #192]
    stp x26, x27, [sp, #208]
    stp x28, x29, [sp, #224]
.endm

.macro restore_x2_to_x29
    ldp x2,  x3,  [sp, #16]
    ldp x4,  x5,  [sp, #32]
    ldp x6,  x7,  [sp, #48]
    ldp x8,  x9,  [sp, #64]
    ldp x10, x11, [sp, #80]
    ldp x12, x13, [sp, #96]
    ldp x14, x15, [sp, #112]
    ldp x16, x17, [sp, #128]
    ldp x18, x19, [sp, #144]
    ldp x20, x21, [sp, #160]
    ldp x22, x23, [sp, #176]
    ldp x24, x25, [sp, #192]
    ldp x26, x27, [sp, #208]
    ldp x28, x29, [sp, #224]
.endm

// ABI: Vector ID in x0, x0 and x1 already saved on the trap frame. Never returns.
.Lexception_common:
    save_x2_to_x29

    add x2, sp, #272
    stp x30, x2, [sp, #240]
    mrs x2, elr_el1
    mrs x3, spsr_el1
    stp x2, x3, [sp, #256]

    mov x29, xzr
    mov x1, sp
    bl panic_exception

.Lexception_halt:
    wfe
    b .Lexception_halt

// ABI: x0 and x1 already saved on the trap frame. Restores interrupted context.
.Lirq_common:
    save_x2_to_x29
    str x30, [sp, #240]
    mrs x2, elr_el1
    mrs x3, spsr_el1
    stp x2, x3, [sp, #256]

    mov x29, xzr
    bl irq_dispatch

    ldp x2, x3, [sp, #256]
    msr elr_el1, x2
    msr spsr_el1, x3
    ldr x30, [sp, #240]
    restore_x2_to_x29
    ldp x0, x1, [sp, #0]
    add sp, sp, #272
    eret

// ABI: x0 and x1 already saved on the trap frame. Restores EL0t context on return.
.Lel0_sync:
    save_x2_to_x29
    mrs x2, sp_el0
    stp x30, x2, [sp, #240]
    mrs x2, elr_el1
    mrs x3, spsr_el1
    stp x2, x3, [sp, #256]

    mov x29, xzr
    mov x0, sp
    bl el0_sync_dispatch

    ldp x2, x3, [sp, #256]
    msr elr_el1, x2
    msr spsr_el1, x3
    ldp x30, x2, [sp, #240]
    msr sp_el0, x2
    restore_x2_to_x29
    ldp x0, x1, [sp, #0]
    add sp, sp, #272
    eret
