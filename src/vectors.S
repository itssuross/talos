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
    vector_slot 5
    vector_slot 6
    vector_slot 7
    vector_slot 8
    vector_slot 9
    vector_slot 10
    vector_slot 11
    vector_slot 12
    vector_slot 13
    vector_slot 14
    vector_slot 15
    .balign 128
.size vectors, . - vectors

// ABI: Vector ID in x0, x0 and x1 already saved on the trap frame. Never returns.
.Lexception_common:
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
