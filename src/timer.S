.section .bss, "aw", @nobits
.balign 8
core_ticks:
    .quad 0, 0, 0, 0
timer_reload:
    .quad 0

.section .text, "ax"
.global timer_init
.type timer_init, %function

// ABI: Clobbers x0–x6.
timer_init:
    mrs x0, cntfrq_el0
    cbnz x0, .Lfrequency_ready
    ldr x0, =62500000
.Lfrequency_ready:
    mov x1, #100
    udiv x0, x0, x1
    adrp x1, timer_reload
    str x0, [x1, :lo12:timer_reload]
    adr x1, core_ticks
    stp xzr, xzr, [x1]
    stp xzr, xzr, [x1, #16]
    b timer_init_cpu
.size timer_init, . - timer_init

.global timer_init_cpu
.type timer_init_cpu, %function

// ABI: Clobbers x0–x6.
timer_init_cpu:
    adrp x1, timer_reload
    ldr x0, [x1, :lo12:timer_reload]

    msr cntp_tval_el0, x0
    mov x0, #1 // CNTP_CTL_EL0.ENABLE
    msr cntp_ctl_el0, x0
    isb
    mov w0, #30
    b gic_enable_irq
.size timer_init_cpu, . - timer_init_cpu

.global timer_irq_handler
.type timer_irq_handler, %function

// ABI: Clobbers x0–x2 and NZCV.
timer_irq_handler:
    mrs x2, mpidr_el1
    and x2, x2, #0xff
    cmp x2, #4
    b.hs .Lreload
    adr x1, core_ticks
    ldr x0, [x1, x2, lsl #3]
    add x0, x0, #1
    str x0, [x1, x2, lsl #3]
.Lreload:
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
    adrp x0, core_ticks
    ldr x0, [x0, :lo12:core_ticks]
    ret
.size timer_get_ticks, . - timer_get_ticks

.global timer_get_core_ticks
.type timer_get_core_ticks, %function

// ABI: CPU ID in x0. Returns ticks or zero in x0. Clobbers x1 and NZCV.
timer_get_core_ticks:
    cmp x0, #4
    b.hs .Linvalid_cpu
    adr x1, core_ticks
    ldr x0, [x1, x0, lsl #3]
    ret
.Linvalid_cpu:
    mov x0, #0
    ret
.size timer_get_core_ticks, . - timer_get_core_ticks
