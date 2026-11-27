.equ USER_BASE,        0x40200000
.equ USER_END,         0x40400000
.equ USER_CODE_MAX,    0x00100000
.equ USER_STACK_TOP,   0x403ff000
.equ SYS_EXIT,         0
.equ SYS_WRITE,        1
.equ SYS_GETTICKS,     2
.equ SYS_YIELD,        3
.equ SYS_OPEN,         4
.equ SYS_READ,         5
.equ SYS_CLOSE,        6
.equ SYS_CPU_ID,       7
.equ SYS_SLEEP,        8
.equ SYS_BLK_READ,     9
.equ SYS_BLK_WRITE,    10
.equ SYS_WRITE_MAX,    256
.equ SYS_OPEN_MAX_LEN, 64
.equ SYS_READ_MAX,     4096
.equ FD_MAX,           4
.equ FD_ENTRY_SIZE,    24

.section .bss, "aw", @nobits
.balign 8
user_return_sp:
    .quad 0
user_exit_code:
    .quad 0
// 4 slots x 24 bytes: +0x00 in_use, +0x08 entry_ptr, +0x10 offset.
fd_table:
    .skip 96

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

    adrp x2, fd_table
    add x2, x2, :lo12:fd_table
    mov x3, #12
.Lzero_fds:
    str xzr, [x2], #8
    subs x3, x3, #1
    b.ne .Lzero_fds

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

// ABI: Trap frame pointer in x0. Clobbers caller-saved registers and NZCV.
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
    cmp x8, #SYS_OPEN
    b.eq .Lsys_open
    cmp x8, #SYS_READ
    b.eq .Lsys_read
    cmp x8, #SYS_CLOSE
    b.eq .Lsys_close
    cmp x8, #SYS_CPU_ID
    b.eq .Lsys_cpu_id
    cmp x8, #SYS_SLEEP
    b.eq .Lsys_sleep
    cmp x8, #SYS_BLK_READ
    b.eq .Lsys_blk
    cmp x8, #SYS_BLK_WRITE
    b.eq .Lsys_blk

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
    b .Lsys_done

.Lsys_cpu_id:
    mrs x1, mpidr_el1
    and x1, x1, #0xff
    str x1, [x19]
    b .Lsys_done

.Lsys_sleep:
    ldr x0, [x19]
    bl sched_sleep
    str xzr, [x19]
    b .Lsys_done

.Lsys_blk:
    ldp x0, x1, [x19]
    mov x2, #USER_BASE
    cmp x1, x2
    b.lo .Lsys_invalid
    mov x2, #USER_END
    sub x2, x2, #512
    cmp x1, x2
    b.hi .Lsys_invalid
    cmp x8, #SYS_BLK_READ
    b.ne .Lsys_blk_write
    bl blk_read_sector
    b .Lsys_blk_done
.Lsys_blk_write:
    bl blk_write_sector
.Lsys_blk_done:
    str x0, [x19]
    b .Lsys_done

.Lsys_open:
    ldr x20, [x19, #0]
    movz x2, #0x4020, lsl #16 // USER_BASE
    cmp x20, x2
    b.lo .Lsys_invalid
    movz x3, #0x4040, lsl #16 // USER_END
    cmp x20, x3
    b.hs .Lsys_invalid

    mov x0, x20
    mov x1, #0
.Lopen_scan:
    cmp x0, x3
    b.hs .Lsys_invalid
    ldrb w2, [x0], #1
    cbz w2, .Lopen_nul_ok
    add x1, x1, #1
    cmp x1, #SYS_OPEN_MAX_LEN
    b.lo .Lopen_scan
    b .Lsys_invalid

.Lopen_nul_ok:
    mov x0, x20
    bl ramfs_lookup
    cbz x0, .Lsys_invalid
    mov x21, x0

    adrp x1, fd_table
    add x1, x1, :lo12:fd_table
    mov x0, #0
.Lopen_find_fd:
    ldr x2, [x1, #0]
    cbz x2, .Lopen_alloc_fd
    add x1, x1, #FD_ENTRY_SIZE
    add x0, x0, #1
    cmp x0, #FD_MAX
    b.lo .Lopen_find_fd
    b .Lsys_invalid

.Lopen_alloc_fd:
    mov x2, #1
    str x2, [x1, #0]
    str x21, [x1, #8]
    str xzr, [x1, #16]
    str x0, [x19, #0]
    b .Lsys_done

.Lsys_read:
    ldp x0, x1, [x19, #0]
    ldr x2, [x19, #16]
    cmp x0, #FD_MAX
    b.hs .Lsys_invalid
    add x3, x0, x0, lsl #1
    lsl x3, x3, #3 // fd * 24
    adrp x4, fd_table
    add x4, x4, :lo12:fd_table
    add x4, x4, x3
    ldr x5, [x4, #0]
    cmp x5, #1
    b.ne .Lsys_invalid

    movz x5, #0x4020, lsl #16 // USER_BASE
    cmp x1, x5
    b.lo .Lsys_invalid
    cmp x2, #SYS_READ_MAX
    b.hi .Lsys_invalid
    adds x5, x1, x2
    b.cs .Lsys_invalid
    movz x6, #0x4040, lsl #16 // USER_END
    cmp x5, x6
    b.hi .Lsys_invalid

    ldr x5, [x4, #8]  // entry_ptr
    ldr x6, [x4, #16] // offset
    ldr x7, [x5, #16] // entry->size
    cmp x6, x7
    b.hs .Lread_eof
    sub x7, x7, x6
    cmp x2, x7
    csel x0, x2, x7, lo
    ldr x5, [x5, #8]  // entry->data_ptr
    add x5, x5, x6
    mov x7, x0
.Lread_copy:
    cbz x7, .Lread_done
    ldrb w3, [x5], #1
    strb w3, [x1], #1
    sub x7, x7, #1
    b .Lread_copy
.Lread_done:
    add x6, x6, x0
    str x6, [x4, #16]
    str x0, [x19, #0]
    b .Lsys_done
.Lread_eof:
    str xzr, [x19, #0]
    b .Lsys_done

.Lsys_close:
    ldr x0, [x19, #0]
    cmp x0, #FD_MAX
    b.hs .Lsys_invalid
    add x1, x0, x0, lsl #1
    lsl x1, x1, #3 // fd * 24
    adrp x2, fd_table
    add x2, x2, :lo12:fd_table
    add x2, x2, x1
    ldr x3, [x2, #0]
    cmp x3, #1
    b.ne .Lsys_invalid
    str xzr, [x2, #0]
    str xzr, [x19, #0]

.Lsys_done:
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret
.size syscall_dispatch, . - syscall_dispatch

.global user_exec_blob
.type user_exec_blob, %function

// ABI: Code pointer in x0, size in x1; returns exit code in x0 or -1. Clobbers x0–x5 and NZCV.
user_exec_blob:
    cbz x0, .Lblob_invalid
    cbz x1, .Lblob_invalid
    movz x2, #0x10, lsl #16 // USER_CODE_MAX (1 MiB)
    cmp x1, x2
    b.hi .Lblob_invalid

    stp x29, x30, [sp, #-16]!
    mov x29, sp

    movz x2, #0x4020, lsl #16 // USER_BASE
    mov x3, x2
    add x5, x2, x1
.Lcopy_blob:
    ldrb w4, [x0], #1
    strb w4, [x3], #1
    cmp x3, x5
    b.lo .Lcopy_blob

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
.Lblob_invalid:
    mov x0, #-1
    ret
.size user_exec_blob, . - user_exec_blob

.global user_run_demo
.type user_run_demo, %function

// ABI: Mode in x0 (0 = hello.bin, 1 = fault.bin); returns exit code in x0. Clobbers x0–x5 and NZCV.
user_run_demo:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    cbnz x0, .Lselect_fault
    adrp x0, .Ldemo_hello_name
    add x0, x0, :lo12:.Ldemo_hello_name
    b .Ldemo_lookup
.Lselect_fault:
    adrp x0, .Ldemo_fault_name
    add x0, x0, :lo12:.Ldemo_fault_name
.Ldemo_lookup:
    bl ramfs_lookup
    cbz x0, .Ldemo_missing
    ldp x0, x1, [x0, #8]
    bl user_exec_blob
    ldp x29, x30, [sp], #16
    ret
.Ldemo_missing:
    mov x0, #-1
    ldp x29, x30, [sp], #16
    ret
.size user_run_demo, . - user_run_demo

.section .rodata, "a"
.Ldemo_hello_name:
    .asciz "hello.bin"
.Ldemo_fault_name:
    .asciz "fault.bin"
