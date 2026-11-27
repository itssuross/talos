.section .text, "ax"
.global kmain
.type kmain, %function

// ABI: Takes no arguments and never returns.
kmain:
    bl uart_init

    adrp x0, .Lbanner
    add x0, x0, :lo12:.Lbanner
    bl uart_puts

    bl exceptions_init
    adrp x0, .Lvbar
    add x0, x0, :lo12:.Lvbar
    bl uart_puts
    mrs x0, vbar_el1
    bl uart_puthex
    mov w0, #'\n'
    bl uart_putc

    bl irq_enable
    adrp x0, .Ldaif
    add x0, x0, :lo12:.Ldaif
    bl uart_puts
    mrs x0, daif
    bl uart_puthex
    mov w0, #'\n'
    bl uart_putc
    bl irq_disable

    adrp x0, .Lself_test
    add x0, x0, :lo12:.Lself_test
    bl uart_puts
    brk #0x42

.Lhalt:
    wfe
    b .Lhalt

.size kmain, . - kmain

.section .rodata, "a"
.Lbanner:
    .asciz "Talos v0.2.0 (aarch64-virt)\n"
.Lvbar:
    .asciz "VBAR_EL1: "
.Ldaif:
    .asciz "DAIF (IRQ enabled): "
.Lself_test:
    .asciz "Triggering BRK #0x42 self-test...\n"
