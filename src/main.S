.section .bss, "aw", @nobits
.balign 8
.global worker_a_cpu_hits
worker_a_cpu_hits:
    .quad 0, 0, 0, 0
.global worker_b_cpu_hits
worker_b_cpu_hits:
    .quad 0, 0, 0, 0

.section .text, "ax"
.global kmain
.type kmain, %function

// ABI: Takes no arguments and never returns.
kmain:
    bl uart_init
    bl exceptions_init
    bl mmu_init
    bl blk_init
    bl gic_init
    bl timer_init
    bl sched_init
    bl smp_init
    adr x0, .Lworker_a_name
    adr x1, worker_a_entry
    adr x2, worker_a_cpu_hits
    bl sched_spawn
    adr x0, .Lworker_b_name
    adr x1, worker_b_entry
    adr x2, worker_b_cpu_hits
    bl sched_spawn
    bl smp_online_count
    cmp x0, #1
    b.ls .Lboot_banner
    mrs x1, cntpct_el0
    mrs x2, cntfrq_el0
    add x1, x1, x2, lsr #3
    adr x0, worker_a_cpu_hits
    bl .Lawait_secondary_hit
    adr x0, worker_b_cpu_hits
    bl .Lawait_secondary_hit
.Lboot_banner:
    adrp x0, .Lbanner
    add x0, x0, :lo12:.Lbanner
    bl uart_puts
    bl irq_enable
    bl shell_run
    b psci_system_off
.size kmain, . - kmain

// ABI: Counter array in x0, physical counter deadline in x1. Clobbers x2–x4 and NZCV.
.Lawait_secondary_hit:
    ldp x2, x3, [x0, #8]
    ldr x4, [x0, #24]
    orr x2, x2, x3
    orr x2, x2, x4
    cbnz x2, .Lhit_done
    yield
    mrs x2, cntpct_el0
    cmp x2, x1
    b.lo .Lawait_secondary_hit
.Lhit_done:
    ret

.macro worker_entry name
.type \name, %function

// ABI: Per-CPU counter array in x0. Never returns.
\name:
    mov x19, x0
1:
    msr daifset, #2
    isb
    mrs x1, mpidr_el1
    and x1, x1, #0xff
    ldr x2, [x19, x1, lsl #3]
    add x2, x2, #1
    str x2, [x19, x1, lsl #3]
    msr daifclr, #2
    isb
    mov x0, #1
    bl sched_sleep
    b 1b
.size \name, . - \name
.endm

worker_entry worker_a_entry
worker_entry worker_b_entry

.section .rodata, "a"
.Lbanner:
    .asciz "Talos v0.11.0 (aarch64-virt)\nType 'help' for available commands.\n"
.Lworker_a_name:
    .asciz "worker-a"
.Lworker_b_name:
    .asciz "worker-b"
