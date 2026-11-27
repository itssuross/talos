.equ SYS_EXIT,      0
.equ SYS_WRITE,     1
.equ SYS_GETTICKS,  2
.equ SYS_OPEN,      4
.equ SYS_READ,      5
.equ SYS_CLOSE,     6
.equ SYS_CPU_ID,    7
.equ SYS_SLEEP,     8
.equ SYS_BLK_READ,  9
.equ SYS_BLK_WRITE, 10

.section .text.entry, "ax"
.global _start
.type _start, %function

// ABI: EL0t entry with 16-byte aligned SP_EL0. Exits via SYS_EXIT (0 on pass, check N on failure).
_start:
    sub sp, sp, #512

    mov x20, #1
    mov x8, #99
    svc #0
    cmn x0, #1
    b.ne .Lfail

    mov x20, #2
    mov x8, #-1
    svc #0
    cmn x0, #1
    b.ne .Lfail

    mov x20, #3
    movz x0, #0x4008, lsl #16
    mov x1, #16
    mov x8, #SYS_WRITE
    svc #0
    cmn x0, #1
    b.ne .Lfail

    mov x20, #4
    movz x0, #0xfff0
    movk x0, #0x403f, lsl #16
    mov x1, #32
    mov x8, #SYS_WRITE
    svc #0
    cmn x0, #1
    b.ne .Lfail

    mov x20, #5
    movz x0, #0x4020, lsl #16
    mov x1, #-16
    mov x8, #SYS_WRITE
    svc #0
    cmn x0, #1
    b.ne .Lfail

    mov x20, #6
    movz x0, #0x4008, lsl #16
    mov x8, #SYS_OPEN
    svc #0
    cmn x0, #1
    b.ne .Lfail

    mov x20, #7
    adr x0, .Lmissing
    mov x8, #SYS_OPEN
    svc #0
    cmn x0, #1
    b.ne .Lfail

    mov x20, #8
    mov x19, #0
.Lopen_loop:
    adr x0, .Lmotd
    mov x8, #SYS_OPEN
    svc #0
    cmp x0, x19
    b.ne .Lfail
    add x19, x19, #1
    cmp x19, #4
    b.lo .Lopen_loop
    adr x0, .Lmotd
    mov x8, #SYS_OPEN
    svc #0
    cmn x0, #1
    b.ne .Lfail

    mov x20, #9
    mov x0, #0
    movz x1, #0x4008, lsl #16
    mov x2, #16
    mov x8, #SYS_READ
    svc #0
    cmn x0, #1
    b.ne .Lfail

    mov x20, #10
    mov x0, #7
    mov x1, sp
    mov x2, #16
    mov x8, #SYS_READ
    svc #0
    cmn x0, #1
    b.ne .Lfail

    mov x20, #11
    mov x19, #0
.Lclose_loop:
    mov x0, x19
    mov x8, #SYS_CLOSE
    svc #0
    cbnz x0, .Lfail
    add x19, x19, #1
    cmp x19, #4
    b.lo .Lclose_loop
    mov x0, #0
    mov x8, #SYS_CLOSE
    svc #0
    cmn x0, #1
    b.ne .Lfail

    mov x20, #12
    mov x0, #0
    movz x1, #0x4008, lsl #16
    mov x8, #SYS_BLK_READ
    svc #0
    cmn x0, #1
    b.ne .Lfail

    mov x20, #13
    mov x0, #0
    movz x1, #0xff00
    movk x1, #0x403f, lsl #16
    mov x8, #SYS_BLK_WRITE
    svc #0
    cmn x0, #1
    b.ne .Lfail

    mov x20, #14
    movz x0, #0xffff
    movk x0, #0xffff, lsl #16
    mov x1, sp
    mov x8, #SYS_BLK_READ
    svc #0
    cmn x0, #1
    b.ne .Lfail

    mov x20, #15
    mov x8, #SYS_CPU_ID
    svc #0
    cmp x0, #4
    b.hs .Lfail

    mov x20, #16
    mov x8, #SYS_GETTICKS
    svc #0
    mov x19, x0
    mov x0, #2
    mov x8, #SYS_SLEEP
    svc #0
    cbnz x0, .Lfail
    mov x8, #SYS_GETTICKS
    svc #0
    sub x0, x0, x19
    cmp x0, #2
    b.lo .Lfail

    adr x0, .Lpass_msg
    mov x1, #(.Lpass_end - .Lpass_msg)
    mov x8, #SYS_WRITE
    svc #0
    add sp, sp, #512
    mov x0, #0
    mov x8, #SYS_EXIT
    svc #0

.Lfail:
    adr x0, .Lfail_msg
    mov x1, #(.Lfail_end - .Lfail_msg)
    mov x8, #SYS_WRITE
    svc #0
    add sp, sp, #512
    mov x0, x20
    mov x8, #SYS_EXIT
    svc #0
.size _start, . - _start

.section .rodata, "a"
.Lmotd:
    .asciz "motd.txt"
.Lmissing:
    .asciz "missing.txt"
.Lpass_msg:
    .ascii "selftest.elf: 14/14 adversarial ABI checks passed!\n"
.Lpass_end:
.Lfail_msg:
    .ascii "selftest.elf: FAILED check\n"
.Lfail_end:
