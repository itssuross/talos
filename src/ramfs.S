.equ SYS_EXIT,     0
.equ SYS_WRITE,    1
.equ SYS_GETTICKS, 2
.equ SYS_YIELD,    3
.equ SYS_OPEN,     4
.equ SYS_READ,     5
.equ SYS_CLOSE,    6
.equ SYS_BLK_READ, 9
.equ SYS_BLK_WRITE, 10

.section .text, "ax"

.global ramfs_lookup
.type ramfs_lookup, %function

// ABI: NUL-terminated filename in x0; returns entry pointer in x0 or 0. Clobbers x0–x3 and NZCV.
ramfs_lookup:
    cbz x0, .Llookup_null
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    mov x19, x0
    adrp x20, ramfs_table
    add x20, x20, :lo12:ramfs_table
.Llookup_loop:
    ldr x1, [x20, #0]
    cbz x1, .Llookup_miss
    mov x0, x19
    bl strcmp
    cbz w0, .Llookup_hit
    add x20, x20, #32
    b .Llookup_loop
.Llookup_hit:
    mov x0, x20
    b .Llookup_done
.Llookup_miss:
    mov x0, #0
.Llookup_done:
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret
.Llookup_null:
    mov x0, #0
    ret
.size ramfs_lookup, . - ramfs_lookup

.global ramfs_get_entry
.type ramfs_get_entry, %function

// ABI: Entry index in x0; returns entry pointer in x0 or 0 at sentinel. Clobbers x0–x2 and NZCV.
ramfs_get_entry:
    adrp x1, ramfs_table
    add x1, x1, :lo12:ramfs_table
.Lget_loop:
    ldr x2, [x1, #0]
    cbz x2, .Lget_none
    cbz x0, .Lget_found
    sub x0, x0, #1
    add x1, x1, #32
    b .Lget_loop
.Lget_found:
    mov x0, x1
    ret
.Lget_none:
    mov x0, #0
    ret
.size ramfs_get_entry, . - ramfs_get_entry

.section .rodata, "a"
.balign 8
.global ramfs_table
// Entry layout (32 bytes): +0x00 name_ptr, +0x08 data_ptr, +0x10 size, +0x18 flags (0=file, 1=exec).
ramfs_table:
    .quad .Lname_motd,   .Lfile_motd_start,   .Lfile_motd_end - .Lfile_motd_start,     0
    .quad .Lname_about,  .Lfile_about_start,  .Lfile_about_end - .Lfile_about_start,   0
    .quad .Lname_hello,  .Lfile_hello_start,  .Lfile_hello_end - .Lfile_hello_start,   1
    .quad .Lname_reader, .Lfile_reader_start, .Lfile_reader_end - .Lfile_reader_start, 1
    .quad .Lname_fault,  .Lfile_fault_start,  .Lfile_fault_end - .Lfile_fault_start,   1
    .quad .Lname_blktest, .Lfile_blktest_start, .Lfile_blktest_end - .Lfile_blktest_start, 1
    .quad 0, 0, 0, 0

.Lname_motd:
    .asciz "motd.txt"
.Lname_about:
    .asciz "about.txt"
.Lname_hello:
    .asciz "hello.bin"
.Lname_reader:
    .asciz "reader.bin"
.Lname_fault:
    .asciz "fault.bin"

.Lname_blktest:
    .asciz "blktest.bin"

.Lfile_motd_start:
    .ascii "Welcome to TalosFS (100% pure AArch64 RAMFS)!\n"
.Lfile_motd_end:

.Lfile_about_start:
    .ascii "Talos v0.8.0: EL1 MMU, GICv2, Preemptive Scheduler, EL0t Syscalls, RAMFS\n"
.Lfile_about_end:

.balign 4
.Lfile_hello_start:
    adr x0, .Lhello_msg
    mov x1, #(.Lhello_msg_end - .Lhello_msg)
    mov x8, #SYS_WRITE
    svc #0
    mov x8, #SYS_GETTICKS
    svc #0
    mov x8, #SYS_YIELD
    svc #0
    mov x0, #0
    mov x8, #SYS_EXIT
    svc #0
.Lhello_msg:
    .ascii "hello.bin: running in EL0t via exec!\n"
.Lhello_msg_end:
.Lfile_hello_end:

.balign 4
.Lfile_reader_start:
    sub sp, sp, #128
    adr x0, .Lreader_path
    mov x8, #SYS_OPEN
    svc #0
    cmp x0, #0
    b.lt .Lreader_fail
    mov x19, x0
    mov x1, sp
    mov x2, #128
    mov x8, #SYS_READ
    svc #0
    cmp x0, #0
    b.le .Lreader_close
    mov x1, x0
    mov x0, sp
    mov x8, #SYS_WRITE
    svc #0
.Lreader_close:
    mov x0, x19
    mov x8, #SYS_CLOSE
    svc #0
    add sp, sp, #128
    mov x0, #0
    mov x8, #SYS_EXIT
    svc #0
.Lreader_fail:
    add sp, sp, #128
    mov x0, #1
    mov x8, #SYS_EXIT
    svc #0
.Lreader_path:
    .asciz "motd.txt"
.Lfile_reader_end:

.balign 4
.Lfile_fault_start:
    movz x1, #0x4008, lsl #16
    ldr x0, [x1]
    mov x0, #1
    mov x8, #SYS_EXIT
    svc #0
.Lfile_fault_end:

.balign 8
.Lfile_blktest_start:
    sub sp, sp, #512
    bl .Lblktest_clear
    adr x19, .Lblktest_pattern
    ldp x20, x21, [x19]
    stp x20, x21, [sp]
    mov x0, #1
    mov x1, sp
    mov x8, #SYS_BLK_WRITE
    svc #0
    cbnz x0, .Lblktest_error

    bl .Lblktest_clear
    mov x0, #1
    mov x1, sp
    mov x8, #SYS_BLK_READ
    svc #0
    cbnz x0, .Lblktest_error
    ldp x2, x3, [sp]
    cmp x2, x20
    ccmp x3, x21, #0, eq
    b.ne .Lblktest_error
    adr x0, .Lblktest_msg
    mov x1, #(.Lfile_blktest_end - .Lblktest_msg)
    mov x8, #SYS_WRITE
    svc #0
    mov x0, #0
    b .Lblktest_exit
.Lblktest_error:
    mov x0, #1
.Lblktest_exit:
    add sp, sp, #512
    mov x8, #SYS_EXIT
    svc #0

// ABI: Clears the 512-byte sector at SP. Clobbers x2–x3 and NZCV.
.Lblktest_clear:
    mov x2, sp
    add x3, x2, #512
.Lblktest_clear_next:
    stp xzr, xzr, [x2], #16
    cmp x2, x3
    b.lo .Lblktest_clear_next
    ret

.balign 8
.Lblktest_pattern:
    .ascii "TALOS-EL0-BLK-OK"
.Lblktest_msg:
    .ascii "blktest.bin: VirtIO-Blk EL0 read/write verified!\n"
.Lfile_blktest_end:
