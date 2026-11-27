.section .bss, "aw", @nobits
.balign 4
cpu_online:
    .word 0, 0, 0, 0

.section .text, "ax"
.global smp_init
.type smp_init, %function

// ABI: Clobbers caller-saved registers and NZCV.
smp_init:
    stp x19, x20, [sp, #-16]!
    adr x20, cpu_online
    mov w19, #1
    stlr w19, [x20]
    dsb ish

.Lcpu_on:
    movz x0, #3
    movk x0, #0xc400, lsl #16 // PSCI CPU_ON (SMC64)
    mov x1, x19
    adr x2, secondary_entry
    mov x3, x19
    hvc #0
    cbnz x0, .Lnext_cpu
    add x1, x20, x19, lsl #2
    mrs x2, cntpct_el0
    mrs x3, cntfrq_el0
    add x2, x2, x3
.Lwait_online:
    ldar w0, [x1]
    cbnz w0, .Lnext_cpu
    yield
    mrs x0, cntpct_el0
    cmp x0, x2
    b.lo .Lwait_online
.Lnext_cpu:
    add x19, x19, #1
    cmp x19, #4
    b.lo .Lcpu_on
    ldp x19, x20, [sp], #16
    ret
.size smp_init, . - smp_init

.global smp_secondary_main
.type smp_secondary_main, %function

// ABI: CPU ID in x0. Never returns.
smp_secondary_main:
    mov x19, x0
    bl exceptions_init
    bl mmu_init_secondary
    bl gic_init_cpu
    bl timer_init_cpu
    adr x1, cpu_online
    add x1, x1, x19, lsl #2
    mov w0, #1
    stlr w0, [x1]
    dsb ish
    sev
    bl irq_enable
.Lidle:
    wfi
    b .Lidle
.size smp_secondary_main, . - smp_secondary_main

.global smp_is_online
.type smp_is_online, %function

// ABI: CPU ID in x0. Returns 0 or 1 in x0. Clobbers x1 and NZCV.
smp_is_online:
    cmp x0, #4
    b.hs .Loffline
    adr x1, cpu_online
    add x1, x1, x0, lsl #2
    ldar w0, [x1]
    ret
.Loffline:
    mov w0, #0
    ret
.size smp_is_online, . - smp_is_online

.global smp_online_count
.type smp_online_count, %function

// ABI: Returns the online CPU count in x0. Clobbers x1–x3 and NZCV.
smp_online_count:
    mov w0, #0
    adr x1, cpu_online
    mov w2, #4
.Lcount_online:
    ldar w3, [x1]
    add w0, w0, w3
    add x1, x1, #4
    subs w2, w2, #1
    b.ne .Lcount_online
    ret
.size smp_online_count, . - smp_online_count
