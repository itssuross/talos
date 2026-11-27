.section .text, "ax"

.global exceptions_init
.type exceptions_init, %function

// ABI: Clobbers x0.
exceptions_init:
    adrp x0, vectors
    add x0, x0, :lo12:vectors
    msr vbar_el1, x0
    isb
    ret
.size exceptions_init, . - exceptions_init

.global irq_enable
.type irq_enable, %function

// ABI: Preserves all general-purpose registers.
irq_enable:
    msr daifclr, #2
    isb
    ret
.size irq_enable, . - irq_enable

.global irq_disable
.type irq_disable, %function

// ABI: Preserves all general-purpose registers.
irq_disable:
    msr daifset, #2
    isb
    ret
.size irq_disable, . - irq_disable

.global irq_dispatch
.type irq_dispatch, %function

// ABI: Clobbers x0–x8 and NZCV. Preserves callee-saved registers.
irq_dispatch:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    bl gic_ack_irq
    mov w19, w0
    and w20, w0, #0x3ff
    cmp w20, #1020
    b.hs .Lirq_done
    cmp w20, #30
    b.ne .Lirq_eoi
    bl timer_irq_handler
.Lirq_eoi:
    mov w0, w19
    bl gic_eoi_irq
    cmp w20, #30
    b.ne .Lirq_done
    bl sched_on_tick
.Lirq_done:
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret
.size irq_dispatch, . - irq_dispatch

.global psci_system_off
.type psci_system_off, %function

// ABI: Takes no arguments and never returns.
psci_system_off:
    movz x0, #0x0008
    movk x0, #0x8400, lsl #16
    mov x1, xzr
    mov x2, xzr
    mov x3, xzr
    hvc #0

.Loff_wait:
    wfe
    b .Loff_wait
.size psci_system_off, . - psci_system_off

.global psci_system_reset
.type psci_system_reset, %function

// ABI: Takes no arguments and never returns.
psci_system_reset:
    movz x0, #0x0009
    movk x0, #0x8400, lsl #16
    mov x1, xzr
    mov x2, xzr
    mov x3, xzr
    hvc #0

.Lreset_wait:
    wfe
    b .Lreset_wait
.size psci_system_reset, . - psci_system_reset

.global panic_exception
.type panic_exception, %function

// ABI: Vector ID in x0, trap frame pointer in x1. Never returns.
panic_exception:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    cmp x0, #0
    csel x19, x0, xzr, ge
    mov x2, #15
    cmp x19, x2
    csel x19, x19, x2, le
    mov x20, x1

    adrp x0, .Lbanner
    add x0, x0, :lo12:.Lbanner
    bl uart_puts

    adrp x0, .Lvector_names
    add x0, x0, :lo12:.Lvector_names
    ldr x0, [x0, x19, lsl #3]
    bl uart_puts

    adrp x0, .Lesr
    add x0, x0, :lo12:.Lesr
    bl uart_puts
    mrs x0, esr_el1
    bl uart_puthex

    adrp x0, .Lelr
    add x0, x0, :lo12:.Lelr
    bl uart_puts
    ldr x0, [x20, #256]
    bl uart_puthex

    adrp x0, .Lfar
    add x0, x0, :lo12:.Lfar
    bl uart_puts
    mrs x0, far_el1
    bl uart_puthex

    adrp x0, .Lspsr
    add x0, x0, :lo12:.Lspsr
    bl uart_puts
    ldr x0, [x20, #264]
    bl uart_puthex

    adrp x0, .Lsp
    add x0, x0, :lo12:.Lsp
    bl uart_puts
    ldr x0, [x20, #248]
    bl uart_puthex
    mov w0, #'\n'
    bl uart_putc

    mov w21, #0
.Ldump_register:
    mov w0, #'x'
    bl uart_putc
    mov w1, #10
    udiv w22, w21, w1
    add w0, w22, #'0'
    bl uart_putc
    mov w1, #10
    msub w0, w22, w1, w21
    add w0, w0, #'0'
    bl uart_putc

    adrp x0, .Lregister_separator
    add x0, x0, :lo12:.Lregister_separator
    bl uart_puts
    ldr x0, [x20, x21, lsl #3]
    bl uart_puthex

    cmp w21, #30
    b.eq .Ldump_newline
    tbnz w21, #0, .Ldump_newline
    adrp x0, .Lregister_gap
    add x0, x0, :lo12:.Lregister_gap
    bl uart_puts
    b .Ldump_next

.Ldump_newline:
    mov w0, #'\n'
    bl uart_putc

.Ldump_next:
    add w21, w21, #1
    cmp w21, #31
    b.lo .Ldump_register

    adrp x0, .Lshutdown
    add x0, x0, :lo12:.Lshutdown
    bl uart_puts
    b psci_system_off
.size panic_exception, . - panic_exception

.section .rodata, "a"
.balign 8
.Lvector_names:
    .quad .Lel1t_sync, .Lel1t_irq, .Lel1t_fiq, .Lel1t_serror
    .quad .Lel1h_sync, .Lel1h_irq, .Lel1h_fiq, .Lel1h_serror
    .quad .Laarch64_sync, .Laarch64_irq, .Laarch64_fiq, .Laarch64_serror
    .quad .Laarch32_sync, .Laarch32_irq, .Laarch32_fiq, .Laarch32_serror

.Lel1t_sync:
    .asciz "EL1t Synchronous"
.Lel1t_irq:
    .asciz "EL1t IRQ"
.Lel1t_fiq:
    .asciz "EL1t FIQ"
.Lel1t_serror:
    .asciz "EL1t SError"
.Lel1h_sync:
    .asciz "EL1h Synchronous"
.Lel1h_irq:
    .asciz "EL1h IRQ"
.Lel1h_fiq:
    .asciz "EL1h FIQ"
.Lel1h_serror:
    .asciz "EL1h SError"
.Laarch64_sync:
    .asciz "Lower EL (AArch64) Synchronous"
.Laarch64_irq:
    .asciz "Lower EL (AArch64) IRQ"
.Laarch64_fiq:
    .asciz "Lower EL (AArch64) FIQ"
.Laarch64_serror:
    .asciz "Lower EL (AArch64) SError"
.Laarch32_sync:
    .asciz "Lower EL (AArch32) Synchronous"
.Laarch32_irq:
    .asciz "Lower EL (AArch32) IRQ"
.Laarch32_fiq:
    .asciz "Lower EL (AArch32) FIQ"
.Laarch32_serror:
    .asciz "Lower EL (AArch32) SError"

.Lbanner:
    .asciz "\n=== TALOS EXCEPTION ===\nVector: "
.Lesr:
    .asciz "\nESR_EL1 : "
.Lelr:
    .asciz "\nELR_EL1 : "
.Lfar:
    .asciz "\nFAR_EL1 : "
.Lspsr:
    .asciz "\nSPSR_EL1: "
.Lsp:
    .asciz "\nSP      : "
.Lregister_separator:
    .asciz ": "
.Lregister_gap:
    .asciz "  "
.Lshutdown:
    .asciz "Halting via PSCI SYSTEM_OFF...\n"
