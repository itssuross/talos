.equ SYS_EXIT,     0
.equ SYS_WRITE,    1
.equ SYS_GETTICKS, 2
.equ SYS_CPU_ID,   7

.section .text.entry, "ax"
.global _start
.type _start, %function

// ABI: EL0t entry. Exits via SYS_EXIT with 0 on success or 1 on failure.
_start:
    adr x0, bss_guard
    ldp x1, x2, [x0]
    ldp x3, x4, [x0, #16]
    orr x1, x1, x2
    orr x3, x3, x4
    orr x1, x1, x3
    cbnz x1, .Lfail

    mov x8, #SYS_CPU_ID
    svc #0
    mov x8, #SYS_GETTICKS
    svc #0
    cmn x0, #1
    b.eq .Lfail

    adr x0, .Lverified
    mov x1, #(.Lverified_end - .Lverified)
    mov x8, #SYS_WRITE
    svc #0
    mov x0, #0
    b .Lexit
.Lfail:
    mov x0, #1
.Lexit:
    mov x8, #SYS_EXIT
    svc #0
.size _start, . - _start

.section .rodata, "a"
.Lverified:
    .ascii "sysinfo.elf: ELF64 PT_LOAD + .bss zeroing verified!\n"
.Lverified_end:

.section .bss, "aw", @nobits
.balign 8
bss_guard:
    .skip 32
