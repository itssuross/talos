.section .text, "ax"

.equ UART0_BASE, 0x09000000
.equ UART_DR,    0x00
.equ UART_FR,    0x18
.equ UART_IBRD,  0x24
.equ UART_FBRD,  0x28
.equ UART_LCR_H, 0x2c
.equ UART_CR,    0x30
.equ UART_IMSC,  0x38
.equ UART_RXFE,  4
.equ UART_TXFF,  5

.global uart_init
.type uart_init, %function

// ABI: Clobbers x0 and x1.
uart_init:
    mov x0, #UART0_BASE
    str wzr, [x0, #UART_CR]
    str wzr, [x0, #UART_IMSC]
    mov w1, #13
    str w1, [x0, #UART_IBRD]
    mov w1, #1
    str w1, [x0, #UART_FBRD]
    mov w1, #0x70 // 8N1 with FIFOs enabled
    str w1, [x0, #UART_LCR_H]
    mov w1, #0x301 // UARTEN, TXE, RXE
    str w1, [x0, #UART_CR]
    ret
.size uart_init, . - uart_init

.global uart_putc
.type uart_putc, %function

// ABI: Byte in w0. Clobbers x0–x3 and NZCV.
uart_putc:
    mov x1, #UART0_BASE
    and w0, w0, #0xff
    cmp w0, #10
    mov w2, #13
    csel w2, w2, w0, eq

.Ltx_wait:
    ldr w3, [x1, #UART_FR]
    tbnz w3, #UART_TXFF, .Ltx_wait
    str w2, [x1, #UART_DR]
    cmp w2, w0
    mov w2, w0
    b.ne .Ltx_wait
    ret
.size uart_putc, . - uart_putc

.global uart_getc
.type uart_getc, %function

// ABI: Returns a byte in w0. Clobbers x0 and x1.
uart_getc:
    mov x1, #UART0_BASE
.Lrx_wait:
    ldr w0, [x1, #UART_FR]
    tbnz w0, #UART_RXFE, .Lrx_wait
    ldr w0, [x1, #UART_DR]
    and w0, w0, #0xff
    ret
.size uart_getc, . - uart_getc

.global uart_puts
.type uart_puts, %function

// ABI: NUL-terminated string in x0. Clobbers x0–x3 and NZCV.
uart_puts:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]
    mov x19, x0

.Lputs_next:
    ldrb w0, [x19], #1
    cbz w0, .Lputs_done
    bl uart_putc
    b .Lputs_next

.Lputs_done:
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret
.size uart_puts, . - uart_puts

.global uart_puthex
.type uart_puthex, %function

// ABI: 64-bit value in x0. Clobbers x0–x3 and NZCV.
uart_puthex:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    mov x19, x0
    mov w20, #16

    mov w0, #'0'
    bl uart_putc
    mov w0, #'x'
    bl uart_putc

.Lhex_next:
    lsr x0, x19, #60
    lsl x19, x19, #4
    add w1, w0, #('A' - 10)
    add w2, w0, #'0'
    cmp w0, #10
    csel w0, w2, w1, lo
    bl uart_putc
    subs w20, w20, #1
    b.ne .Lhex_next

    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret
.size uart_puthex, . - uart_puthex

.global uart_putdec
.type uart_putdec, %function

// ABI: Unsigned 64-bit value in x0. Clobbers x0–x4 and NZCV.
uart_putdec:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #32
    add x1, sp, #31
    strb wzr, [x1]
    mov x2, #10

.Ldec_digit:
    udiv x3, x0, x2
    msub x4, x3, x2, x0
    add w4, w4, #'0'
    strb w4, [x1, #-1]!
    mov x0, x3
    cbnz x0, .Ldec_digit

    mov x0, x1
    bl uart_puts
    add sp, sp, #32
    ldp x29, x30, [sp], #16
    ret
.size uart_putdec, . - uart_putdec
