.section .text, "ax"
.global kmain
.type kmain, %function

// ABI: Takes no arguments and never returns.
kmain:
    bl uart_init
    bl exceptions_init
    bl gic_init
    bl timer_init
    adrp x0, .Lbanner
    add x0, x0, :lo12:.Lbanner
    bl uart_puts
    bl irq_enable
    bl shell_run
    b psci_system_off
.size kmain, . - kmain

.section .rodata, "a"
.Lbanner:
    .asciz "Talos v0.4.0 (aarch64-virt)\nType 'help' for available commands.\n"
