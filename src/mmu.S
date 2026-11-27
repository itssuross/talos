.section .bss, "aw", @nobits
.balign 4096
mmu_l1:
    .skip 4096
mmu_l2_dev:
    .skip 4096
mmu_l2_ram:
    .skip 4096

.section .text, "ax"
.global mmu_init
.type mmu_init, %function

// ABI: Requires zeroed .bss and MMU off. Clobbers x0–x5 and NZCV.
mmu_init:
    adrp x0, mmu_l1
    adrp x1, mmu_l2_dev
    adrp x2, mmu_l2_ram

    ldr x3, =0x0060000000000401 // PXN, UXN, AF, Attr0, block
    mov x4, #0
.Ldevice_block:
    orr x5, x3, x4, lsl #21
    str x5, [x1, x4, lsl #3]
    add x4, x4, #1
    cmp x4, #512
    b.lo .Ldevice_block

    ldr x3, =0x40000705 // DRAM base, AF, inner shareable, Attr1, block
    mov x4, #0
.Lram_block:
    orr x5, x3, x4, lsl #21
    str x5, [x2, x4, lsl #3]
    add x4, x4, #1
    cmp x4, #64
    b.lo .Lram_block

    orr x1, x1, #3
    orr x2, x2, #3
    stp x1, x2, [x0]

    mov x1, #0xff00 // Attr0: Device-nGnRnE, Attr1: Normal WBWA
    msr mair_el1, x1
    mrs x1, id_aa64mmfr0_el1
    and x1, x1, #0xf
    mov x2, #5
    cmp x1, x2
    csel x1, x1, x2, ls
    ldr x2, =0x00803519 // EPD1, TG0=4KiB, SH0=inner, ORGN0/IRGN0=WBWA, T0SZ=25
    orr x2, x2, x1, lsl #32
    msr tcr_el1, x2
    msr ttbr0_el1, x0

    dsb ish
    tlbi vmalle1
    dsb ish
    isb
    mrs x0, sctlr_el1
    orr x0, x0, #1 // M
    orr x0, x0, #4 // C
    orr x0, x0, #0x1000 // I
    msr sctlr_el1, x0
    isb
    ret
.size mmu_init, . - mmu_init
