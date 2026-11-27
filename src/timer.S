.section .bss, "aw", @nobits
.balign 8
timer_ticks:
    .quad 0
timer_reload:
    .quad 0

.section .text, "ax"
.global timer_init
.type timer_init, %function

// ABI: Clobbers x0–x6.
timer_init:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mrs x0, cntfrq_el0
    cbnz x0, .Lfrequency_ready
    ldr x0, =62500000
.Lfrequency_ready:
    mov x1, #100
    udiv x0, x0, x1
    adrp x1, timer_reload
    str x0, [x1, :lo12:timer_reload]
    adrp x1, timer_ticks
    str xzr, [x1, :lo12:timer_ticks]

    msr cntp_tval_el0, x0
    mov x0, #1 // CNTP_CTL_EL0.ENABLE
    msr cntp_ctl_el0, x0
    isb
    mov w0, #30
    bl gic_enable_irq
    ldp x29, x30, [sp], #16
    ret
.size timer_init, . - timer_init

.global timer_irq_handler
.type timer_irq_handler, %function

// ABI: Clobbers x0 and x1.
timer_irq_handler:
    adrp x1, timer_ticks
    ldr x0, [x1, :lo12:timer_ticks]
    add x0, x0, #1
    str x0, [x1, :lo12:timer_ticks]
    adrp x1, timer_reload
    ldr x0, [x1, :lo12:timer_reload]
    msr cntp_tval_el0, x0
    isb
    ret
.size timer_irq_handler, . - timer_irq_handler

.global timer_get_ticks
.type timer_get_ticks, %function

// ABI: Returns the tick count in x0. Clobbers x0.
timer_get_ticks:
    adrp x0, timer_ticks
    ldr x0, [x0, :lo12:timer_ticks]
    ret
.size timer_get_ticks, . - timer_get_ticks
