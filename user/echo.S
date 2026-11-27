.equ SYS_EXIT,  0
.equ SYS_WRITE, 1
.equ SYS_GETC,  11

.section .text.entry, "ax"
.global _start
.type _start, %function

// ABI: EL0t entry with aligned SP_EL0. Exits via SYS_EXIT.
_start:
    adr x0, .Lready
    mov x1, #(.Lready_end - .Lready)
    mov x8, #SYS_WRITE
    svc #0

    sub sp, sp, #64
    mov x19, #0
.Lread:
    mov x8, #SYS_GETC
    svc #0
    mov w20, w0
    add x0, sp, x19
    strb w20, [x0]
    mov x1, #1
    mov x8, #SYS_WRITE
    svc #0
    cmp w20, #10
    b.eq .Ldone
    cmp w20, #13
    b.eq .Ldone
    add x19, x19, #1
    cmp x19, #62
    b.lo .Lread

.Ldone:
    adr x0, .Lexit_msg
    mov x1, #(.Lexit_end - .Lexit_msg)
    mov x8, #SYS_WRITE
    svc #0
    add sp, sp, #64
    mov x0, #0
    mov x8, #SYS_EXIT
    svc #0
.size _start, . - _start

.section .data, "aw"
.Lready:
    .ascii "echo.elf: ready for stdin\n"
.Lready_end:
.Lexit_msg:
    .ascii "\necho.elf: line echoed, exiting!\n"
.Lexit_end:
