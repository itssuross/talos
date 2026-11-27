.equ USER_BASE,      0x40200000
.equ USER_END,       0x40400000
.equ USER_STACK_TOP, 0x403ff000
.equ SYS_EXIT,       0
.equ SYS_WRITE,      1
.equ SYS_GETTICKS,   2
.equ SYS_YIELD,      3
.equ SYS_WRITE_MAX,  256

.section .bss, "aw", @nobits
.balign 8
user_return_sp:
    .quad 0
user_exit_code:
    .quad 0

.section .text, "ax"
.global user_exec
.type user_exec, %function

// ABI: Entry PC in x0, user SP in x1; returns exit code in x0. Preserves x19–x30 and DAIF.
user_exec:
    sub sp, sp, #112
    stp x19, x20, [sp, #0]
    stp x21, x22, [sp, #16]
    stp x23, x24, [sp, #32]
    stp x25, x26, [sp, #48]
    stp x27, x28, [sp, #64]
    stp x29, x30, [sp, #80]
    mrs x2, daif
    str x2, [sp, #96]
    msr daifset, #2
    isb

    mov x2, sp
    adrp x3, user_return_sp
    str x2, [x3, :lo12:user_return_sp]
    adrp x3, user_exit_code
    str xzr, [x3, :lo12:user_exit_code]

    msr sp_el0, x1
    msr elr_el1, x0
    msr spsr_el1, xzr // EL0t, DAIF unmasked

    mov x0, xzr
    mov x1, xzr
    mov x2, xzr
    mov x3, xzr
    mov x4, xzr
    mov x5, xzr
    mov x6, xzr
    mov x7, xzr
    mov x8, xzr
    mov x9, xzr
    mov x10, xzr
    mov x11, xzr
    mov x12, xzr
    mov x13, xzr
    mov x14, xzr
    mov x15, xzr
    mov x16, xzr
    mov x17, xzr
    mov x18, xzr
    mov x19, xzr
    mov x20, xzr
    mov x21, xzr
    mov x22, xzr
    mov x23, xzr
    mov x24, xzr
    mov x25, xzr
    mov x26, xzr
    mov x27, xzr
    mov x28, xzr
    mov x29, xzr
    mov x30, xzr
    eret
.size user_exec, . - user_exec

.global user_exit_to_kernel
.type user_exit_to_kernel, %function

// ABI: Exit code in x0. Restores user_exec frame and returns to user_exec caller.
user_exit_to_kernel:
    adrp x1, user_exit_code
    str x0, [x1, :lo12:user_exit_code]
    adrp x1, user_return_sp
    ldr x1, [x1, :lo12:user_return_sp]
    mov sp, x1
    ldr x2, [sp, #96]
    ldp x19, x20, [sp, #0]
    ldp x21, x22, [sp, #16]
    ldp x23, x24, [sp, #32]
    ldp x25, x26, [sp, #48]
    ldp x27, x28, [sp, #64]
    ldp x29, x30, [sp, #80]
    add sp, sp, #112
    msr daif, x2
    isb
    ret
.size user_exit_to_kernel, . - user_exit_to_kernel

.global syscall_dispatch
.type syscall_dispatch, %function

// ABI: Trap frame pointer in x0. Clobbers x0–x8 and NZCV; preserves callee-saved registers.
syscall_dispatch:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    mov x19, x0

    ldr x8, [x19, #64]
    cmp x8, #SYS_EXIT
    b.eq .Lsys_exit
    cmp x8, #SYS_WRITE
    b.eq .Lsys_write
    cmp x8, #SYS_GETTICKS
    b.eq .Lsys_getticks
    cmp x8, #SYS_YIELD
    b.eq .Lsys_yield

.Lsys_invalid:
    mov x0, #-1
    str x0, [x19, #0]
    b .Lsys_done

.Lsys_exit:
    ldr x0, [x19, #0]
    b user_exit_to_kernel

.Lsys_write:
    ldp x20, x21, [x19, #0]
    cmp x21, #SYS_WRITE_MAX
    b.hi .Lsys_invalid
    movz x2, #0x4020, lsl #16 // USER_BASE
    cmp x20, x2
    b.lo .Lsys_invalid
    adds x3, x20, x21
    b.cs .Lsys_invalid
    movz x2, #0x4040, lsl #16 // USER_END
    cmp x3, x2
    b.hi .Lsys_invalid

    mov x22, x21
.Lwrite_loop:
    cbz x22, .Lwrite_done
    ldrb w0, [x20], #1
    bl uart_putc
    sub x22, x22, #1
    b .Lwrite_loop
.Lwrite_done:
    str x21, [x19, #0]
    b .Lsys_done

.Lsys_getticks:
    bl timer_get_ticks
    str x0, [x19, #0]
    b .Lsys_done

.Lsys_yield:
    bl sched_yield
    str xzr, [x19, #0]

.Lsys_done:
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret
.size syscall_dispatch, . - syscall_dispatch

.global user_run_demo
.type user_run_demo, %function

// ABI: Mode in x0 (0 = demo, 1 = fault); returns exit code in x0. Clobbers x0–x4 and NZCV.
user_run_demo:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    cbnz x0, .Lselect_fault
    adrp x0, user_demo_blob
    add x0, x0, :lo12:user_demo_blob
    adrp x1, user_demo_blob_end
    add x1, x1, :lo12:user_demo_blob_end
    b .Lcopy_setup
.Lselect_fault:
    adrp x0, user_fault_blob
    add x0, x0, :lo12:user_fault_blob
    adrp x1, user_fault_blob_end
    add x1, x1, :lo12:user_fault_blob_end

.Lcopy_setup:
    movz x2, #0x4020, lsl #16 // USER_BASE
    mov x3, x2
.Lcopy_blob:
    cmp x0, x1
    b.hs .Lcache_sync
    ldrb w4, [x0], #1
    strb w4, [x3], #1
    b .Lcopy_blob

.Lcache_sync:
    mov x4, x2
.Ldc_clean:
    dc cvau, x4
    add x4, x4, #16
    cmp x4, x3
    b.lo .Ldc_clean
    dsb ish
    mov x4, x2
.Lic_inval:
    ic ivau, x4
    add x4, x4, #16
    cmp x4, x3
    b.lo .Lic_inval
    dsb ish
    isb

    mov x0, x2
    movz x1, #0xf000
    movk x1, #0x403f, lsl #16 // USER_STACK_TOP
    bl user_exec
    ldp x29, x30, [sp], #16
    ret
.size user_run_demo, . - user_run_demo

.section .rodata, "a"
.balign 4
user_demo_blob:
    adr x0, .Ldemo_msg1
    mov x1, #(.Ldemo_msg1_end - .Ldemo_msg1)
    mov x8, #SYS_WRITE
    svc #0
    mov x8, #SYS_GETTICKS
    svc #0
    cbz x0, .Ldemo_yield
    adr x0, .Ldemo_msg2
    mov x1, #(.Ldemo_msg2_end - .Ldemo_msg2)
    mov x8, #SYS_WRITE
    svc #0
.Ldemo_yield:
    mov x8, #SYS_YIELD
    svc #0
    mov x0, #0
    mov x8, #SYS_EXIT
    svc #0
.Ldemo_msg1:
    .ascii "Hello from EL0t user space!\n"
.Ldemo_msg1_end:
.Ldemo_msg2:
    .ascii "EL0t observed tick IRQ active\n"
.Ldemo_msg2_end:
user_demo_blob_end:

.balign 4
user_fault_blob:
    movz x1, #0x4008, lsl #16
    ldr x0, [x1]
    mov x0, #1
    mov x8, #SYS_EXIT
    svc #0
user_fault_blob_end:
