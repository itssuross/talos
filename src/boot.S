.section .text.boot, "ax"
.global _start
.type _start, %function

// ABI: Initializes sp, clears x29 and x30 before kmain, and never returns.
_start:
    msr daifset, #0xf

    mrs x0, mpidr_el1
    mov x1, #0xffffff
    movk x1, #0xff, lsl #32
    and x0, x0, x1
    cbnz x0, .Lpark

    mrs x0, CurrentEL
    cmp x0, #0x8
    b.ne .Lel1_entry

    mov x0, #(1 << 31) // HCR_EL2.RW
    msr hcr_el2, x0
    mov x0, #0x3c5 // EL1h with DAIF masked
    msr spsr_el2, x0
    adr x0, .Lel1_entry
    msr elr_el2, x0
    eret

.Lel1_entry:
    mrs x0, cpacr_el1
    orr x0, x0, #(3 << 20) // CPACR_EL1.FPEN
    msr cpacr_el1, x0
    isb

    msr spsel, #1
    isb
    adrp x0, __stack_top
    add x0, x0, :lo12:__stack_top
    mov sp, x0

    adrp x0, __bss_start
    add x0, x0, :lo12:__bss_start
    adrp x1, __bss_end
    add x1, x1, :lo12:__bss_end

.Lzero_bss:
    cmp x0, x1
    b.hs .Lcall_main
    stp xzr, xzr, [x0], #16
    b .Lzero_bss

.Lcall_main:
    mov x29, xzr
    mov x30, xzr
    bl kmain

.Lpark:
    wfe
    b .Lpark

.size _start, . - _start

.global secondary_entry
.type secondary_entry, %function

// ABI: PSCI context ID in x0. Initializes sp and never returns.
secondary_entry:
    msr daifset, #0xf
    mrs x1, CurrentEL
    cmp x1, #0x8
    b.ne .Lsec_el1

    mov x1, #(1 << 31) // HCR_EL2.RW
    msr hcr_el2, x1
    mrs x1, cnthctl_el2
    orr x1, x1, #3 // EL1PCTEN, EL1PCEN
    msr cnthctl_el2, x1
    mov x1, #0x3c5 // EL1h with DAIF masked
    msr spsr_el2, x1
    adr x1, .Lsec_el1
    msr elr_el2, x1
    eret

.Lsec_el1:
    msr spsel, #1
    isb
    mrs x1, cpacr_el1
    orr x1, x1, #(3 << 20) // CPACR_EL1.FPEN
    msr cpacr_el1, x1
    isb
    mrs x0, mpidr_el1
    and x0, x0, #0xff
    cbz x0, .Lpark
    cmp x0, #3
    b.hi .Lpark
    adr x1, secondary_stacks
    add x1, x1, x0, lsl #12
    mov sp, x1
    mov x29, xzr
    mov x30, xzr
    bl smp_secondary_main
    b .Lpark
.size secondary_entry, . - secondary_entry

.section .bss, "aw", @nobits
.balign 16
secondary_stacks:
    .skip 12288
