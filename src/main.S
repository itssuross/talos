.section .bss, "aw", @nobits
.balign 8
.global worker_a_count
worker_a_count:
    .quad 0
.global worker_b_count
worker_b_count:
    .quad 0

.section .text, "ax"
.global kmain
.type kmain, %function

// ABI: Takes no arguments and never returns.
kmain:
    bl uart_init
    bl exceptions_init
    bl mmu_init
    bl gic_init
    bl timer_init
    bl sched_init
    adr x0, .Lworker_a_name
    adr x1, worker_a_entry
    adr x2, worker_a_count
    bl sched_spawn
    adr x0, .Lworker_b_name
    adr x1, worker_b_entry
    adr x2, worker_b_count
    bl sched_spawn
    adrp x0, .Lbanner
    add x0, x0, :lo12:.Lbanner
    bl uart_puts
    bl irq_enable
    bl shell_run
    b psci_system_off
.size kmain, . - kmain

.macro worker_entry name
.type \name, %function

// ABI: Counter pointer in x0. Clobbers x1 and never returns.
\name:
    ldr x1, [x0]
    add x1, x1, #1
    str x1, [x0]
    wfi
    b \name
.size \name, . - \name
.endm

worker_entry worker_a_entry
worker_entry worker_b_entry

.section .rodata, "a"
.Lbanner:
    .asciz "Talos v0.6.0 (aarch64-virt)\nType 'help' for available commands.\n"
.Lworker_a_name:
    .asciz "worker-a"
.Lworker_b_name:
    .asciz "worker-b"
