.equ USER_BASE,  0x40200000
.equ LOAD_LIMIT, 0x403f0000
.equ PT_LOAD,    1

.equ E_TYPE,      16
.equ E_MACHINE,   18
.equ E_VERSION,   20
.equ E_ENTRY,     24
.equ E_PHOFF,     32
.equ E_EHSIZE,    52
.equ E_PHENTSIZE, 54
.equ E_PHNUM,     56

.equ P_OFFSET, 8
.equ P_VADDR,  16
.equ P_FILESZ, 32
.equ P_MEMSZ,  40

.section .text, "ax"
.global elf64_load
.type elf64_load, %function

// ABI: File at x0 of size x1. Returns entry VA or 0 in x0. Clobbers x0–x15 and NZCV.
elf64_load:
    cbz x0, .Linvalid
    cmp x1, #64
    b.lo .Linvalid
    adds x2, x0, x1
    b.cs .Linvalid
    ldr w2, [x0]
    movz w3, #0x457f
    movk w3, #0x464c, lsl #16
    cmp w2, w3
    b.ne .Linvalid
    ldrb w2, [x0, #4]
    cmp w2, #2
    b.ne .Linvalid
    ldrb w2, [x0, #5]
    cmp w2, #1
    b.ne .Linvalid
    ldrb w2, [x0, #6]
    cmp w2, #1
    b.ne .Linvalid
    ldrh w2, [x0, #E_TYPE]
    cmp w2, #2
    b.ne .Linvalid
    ldrh w2, [x0, #E_MACHINE]
    cmp w2, #183
    b.ne .Linvalid
    ldr w2, [x0, #E_VERSION]
    cmp w2, #1
    b.ne .Linvalid
    ldrh w2, [x0, #E_EHSIZE]
    cmp w2, #64
    b.ne .Linvalid

    mov x6, #USER_BASE
    mov x7, #LOAD_LIMIT
    ldr x2, [x0, #E_ENTRY]
    tst x2, #3
    b.ne .Linvalid
    cmp x2, x6
    b.lo .Linvalid
    cmp x2, x7
    b.hs .Linvalid

    ldrh w3, [x0, #E_PHENTSIZE]
    cmp w3, #56
    b.lo .Linvalid
    ldrh w4, [x0, #E_PHNUM]
    cbz w4, .Linvalid
    cmp w4, #16
    b.hi .Linvalid
    ldr x5, [x0, #E_PHOFF]
    cmp x5, #64
    b.lo .Linvalid
    subs x8, x1, x5
    b.lo .Linvalid
    mul x9, x3, x4
    cmp x9, x8
    b.hi .Linvalid
    add x5, x0, x5
    add x4, x5, x9

    mov x8, x5
    mov w9, #0
.Lvalidate:
    ldr w10, [x8]
    cmp w10, #PT_LOAD
    b.ne .Lvalidate_next
    ldp x10, x11, [x8, #P_FILESZ]
    cmp x11, x10
    b.lo .Linvalid
    cbz x11, .Lvalidate_next
    ldr x12, [x8, #P_OFFSET]
    subs x12, x1, x12
    b.lo .Linvalid
    cmp x10, x12
    b.hi .Linvalid
    ldr x12, [x8, #P_VADDR]
    cmp x12, x6
    b.lo .Linvalid
    cmp x12, x7
    b.hs .Linvalid
    sub x12, x7, x12
    cmp x11, x12
    b.hi .Linvalid
    mov w9, #1
.Lvalidate_next:
    add x8, x8, x3
    cmp x8, x4
    b.lo .Lvalidate
    cbz w9, .Linvalid

    mrs x8, ctr_el0
    ubfx x9, x8, #16, #4 // DminLine
    and x8, x8, #15      // IminLine
    mov x10, #4
    lsl x13, x10, x9
    lsl x14, x10, x8
.Lload:
    ldr w8, [x5]
    cmp w8, #PT_LOAD
    b.ne .Lload_next
    ldp x8, x9, [x5, #P_OFFSET]
    ldp x10, x11, [x5, #P_FILESZ]
    cbz x11, .Lload_next
    add x8, x0, x8
    add x11, x9, x11
    mov x12, x9
    cbz x10, .Lzero
.Lcopy:
    ldrb w15, [x8], #1
    strb w15, [x12], #1
    subs x10, x10, #1
    b.ne .Lcopy
.Lzero:
    cmp x12, x11
    b.hs .Lsync
    strb wzr, [x12], #1
    b .Lzero

.Lsync:
    sub x10, x13, #1
    bic x12, x9, x10
.Lclean:
    dc cvau, x12
    add x12, x12, x13
    cmp x12, x11
    b.lo .Lclean
    dsb ish
    sub x10, x14, #1
    bic x12, x9, x10
.Linvalidate:
    ic ivau, x12
    add x12, x12, x14
    cmp x12, x11
    b.lo .Linvalidate
    dsb ish
    isb
.Lload_next:
    add x5, x5, x3
    cmp x5, x4
    b.lo .Lload
    mov x0, x2
    ret
.Linvalid:
    mov x0, #0
    ret
.size elf64_load, . - elf64_load
