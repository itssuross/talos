.section .text, "ax"

.equ GICD_BASE,       0x08000000
.equ GICC_BASE,       0x08010000
.equ GICD_CTLR,       0x000
.equ GICD_ISENABLER,  0x100
.equ GICD_IPRIORITYR, 0x400
.equ GICC_CTLR,       0x000
.equ GICC_PMR,        0x004
.equ GICC_IAR,        0x00c
.equ GICC_EOIR,       0x010

.global gic_init
.type gic_init, %function

// ABI: Clobbers x0–x2.
gic_init:
    mov x0, #GICD_BASE
    mov w1, #1
    str w1, [x0, #GICD_CTLR]
    b gic_init_cpu
.size gic_init, . - gic_init

.global gic_init_cpu
.type gic_init_cpu, %function

// ABI: Clobbers x0–x2.
gic_init_cpu:
    mov x0, #GICC_BASE
    mov w2, #0xff
    str w2, [x0, #GICC_PMR]
    mov w1, #1
    str w1, [x0, #GICC_CTLR]
    dsb sy
    isb
    ret
.size gic_init_cpu, . - gic_init_cpu

.global gic_enable_irq
.type gic_enable_irq, %function

// ABI: INTID in w0. Clobbers x1–x6.
gic_enable_irq:
    mov x1, #GICD_BASE
    add x2, x1, #GICD_ISENABLER
    lsr w3, w0, #5
    mov w4, #1
    lsl w4, w4, w0
    str w4, [x2, w3, uxtw #2]

    add x2, x1, #GICD_IPRIORITYR
    and w3, w0, #0xfffffffc
    add x2, x2, w3, uxtw
    and w3, w0, #3
    lsl w3, w3, #3
    mov w4, #0xff
    lsl w4, w4, w3
    mov w5, #0x80
    lsl w5, w5, w3
    ldr w6, [x2]
    bic w6, w6, w4
    orr w6, w6, w5
    str w6, [x2]
    dsb sy
    ret
.size gic_enable_irq, . - gic_enable_irq

.global gic_ack_irq
.type gic_ack_irq, %function

// ABI: Returns raw IAR in w0. Clobbers x0.
gic_ack_irq:
    mov x0, #GICC_BASE
    ldr w0, [x0, #GICC_IAR]
    ret
.size gic_ack_irq, . - gic_ack_irq

.global gic_eoi_irq
.type gic_eoi_irq, %function

// ABI: Raw IAR in w0. Clobbers x1.
gic_eoi_irq:
    mov x1, #GICC_BASE
    str w0, [x1, #GICC_EOIR]
    dsb sy
    ret
.size gic_eoi_irq, . - gic_eoi_irq
