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
    bl gic_init
    bl timer_init
    adrp x0, .Lfrequency
    add x0, x0, :lo12:.Lfrequency
    bl uart_puts
    mrs x0, cntfrq_el0
    bl uart_puthex
    mov w0, #'\n'
    bl uart_putc

    mov x19, xzr
    bl irq_enable
.Lwait_tick:
    wfi
    bl timer_get_ticks
    mov x20, x0
    cmp x19, x20
    b.hs .Lwait_tick

.Lprint_tick:
    add x19, x19, #1
    adrp x0, .Ltick
    add x0, x0, :lo12:.Ltick
    bl uart_puts
    mov x0, x19
    bl uart_putdec
    mov w0, #'\n'
    bl uart_putc
    cmp x19, #10
    b.eq .Lverified
    cmp x19, x20
    b.lo .Lprint_tick
    b .Lwait_tick

.Lverified:
    bl irq_disable
    adrp x0, .Lshutdown
    add x0, x0, :lo12:.Lshutdown
    bl uart_puts
    b psci_system_off
.size kmain, . - kmain

.section .rodata, "a"
.Lbanner:
    .asciz "Talos v0.3.0 (aarch64-virt)\n"
.Lfrequency:
    .asciz "CNTFRQ_EL0: "
.Ltick:
    .asciz "Timer tick: "
.Lshutdown:
    .asciz "Verified 10 GICv2 timer IRQs.\nHalting via PSCI SYSTEM_OFF...\n"
