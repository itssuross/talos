.section .text, "ax"
.global kmain
.type kmain, %function

// ABI: Takes no arguments and never returns.
kmain:
    bl uart_init

    adrp x0, .Lbanner
    add x0, x0, :lo12:.Lbanner
    bl uart_puts

    mrs x0, mpidr_el1
    bl uart_puthex

    adrp x0, .Lshutdown
    add x0, x0, :lo12:.Lshutdown
    bl uart_puts

    movz x0, #0x0008
    movk x0, #0x8400, lsl #16
    mov x1, xzr
    mov x2, xzr
    mov x3, xzr
    hvc #0

.Lhalt:
    wfe
    b .Lhalt

.size kmain, . - kmain

.section .rodata, "a"
.Lbanner:
    .asciz "Talos v0.1.0 (aarch64-virt)\nBoot CPU MPIDR_EL1: "
.Lshutdown:
    .asciz "\nHalting via PSCI SYSTEM_OFF...\n"
