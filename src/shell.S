.equ SHELL_CAPACITY, 128

.section .bss, "aw", @nobits
.balign 8
shell_buf:
    .skip SHELL_CAPACITY

.section .text, "ax"

.macro puts_label label
    adr x0, \label
    bl uart_puts
.endm

.global shell_readline
.type shell_readline, %function

// ABI: Buffer in x0, capacity in x1, length in x0. Clobbers x0–x3 and NZCV.
shell_readline:
    cbnz x1, .Lread_start
    mov x0, #0
    ret
.Lread_start:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    str x21, [sp, #32]
    mov x19, x0
    sub x20, x1, #1
    mov x21, #0
.Lread_byte:
    bl uart_getc
    cmp w0, #13
    b.eq .Lread_enter
    cmp w0, #10
    b.eq .Lread_enter
    cmp w0, #8
    b.eq .Lread_erase
    cmp w0, #0x7f
    b.eq .Lread_erase
    cmp w0, #3
    b.eq .Lread_cancel
    cmp w0, #0x20
    b.lo .Lread_byte
    cmp w0, #0x7e
    b.hi .Lread_byte
    cmp x21, x20
    b.hs .Lread_byte
    strb w0, [x19, x21]
    add x21, x21, #1
    bl uart_putc
    b .Lread_byte
.Lread_erase:
    cbz x21, .Lread_byte
    sub x21, x21, #1
    puts_label .Lerase
    b .Lread_byte
.Lread_cancel:
    puts_label .Lcancel
    mov x21, #0
    b .Lread_done
.Lread_enter:
    mov w0, #10
    bl uart_putc
.Lread_done:
    strb wzr, [x19, x21]
    mov x0, x21
    ldr x21, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret
.size shell_readline, . - shell_readline

.macro match_command name
    mov x0, x19
    adr x1, .Lname_\name
    bl strcmp
    cbz w0, .Lcmd_\name
.endm

.global shell_run
.type shell_run, %function

// ABI: Takes no arguments and never returns.
shell_run:
.Lprompt:
    puts_label .Lprompt_text
    adr x0, shell_buf
    mov x1, #SHELL_CAPACITY
    bl shell_readline
    adr x0, shell_buf
    bl skip_spaces
    mov x19, x0
    ldrb w1, [x0]
    cbz w1, .Lprompt
.Lscan_token:
    cmp w1, #' '
    b.eq .Lsplit_token
    cmp w1, #9
    b.eq .Lsplit_token
    ldrb w1, [x0, #1]!
    cbnz w1, .Lscan_token
    b .Ldispatch
.Lsplit_token:
    strb wzr, [x0], #1
    bl skip_spaces
.Ldispatch:
    mov x20, x0
    match_command help
    match_command info
    match_command mmu
    match_command ticks
    match_command uptime
    match_command tasks
    match_command yield
    match_command ls
    match_command cat
    match_command exec
    match_command user
    match_command peek
    match_command brk
    match_command reboot
    match_command halt

    puts_label .Lunknown
    mov x0, x19
    bl uart_puts
    puts_label .Lhint
    b .Lprompt

.Lcmd_help:
    puts_label .Lhelp_text
    b .Lprompt

.Lcmd_info:
    puts_label .Linfo_el
    mrs x0, CurrentEL
    lsr x0, x0, #2
    bl uart_putdec
    puts_label .Lmpidr
    mrs x0, mpidr_el1
    bl uart_puthex
    puts_label .Lvbar
    mrs x0, vbar_el1
    bl uart_puthex
    puts_label .Lcntfrq
    mrs x0, cntfrq_el0
    bl uart_putdec
    puts_label .Lhz_daif
    mrs x0, daif
    bl uart_puthex
    b .Lnewline

.Lcmd_mmu:
    puts_label .Lsctlr
    mrs x19, sctlr_el1
    mov x0, x19
    bl uart_puthex
    puts_label .Lttbr0
    mrs x0, ttbr0_el1
    bl uart_puthex
    puts_label .Ltcr
    mrs x0, tcr_el1
    bl uart_puthex
    puts_label .Lmair
    mrs x0, mair_el1
    bl uart_puthex
    tst x19, #1
    adr x0, .Lmmu_enabled
    adr x1, .Lmmu_disabled
    csel x0, x0, x1, ne
    bl uart_puts
    b .Lprompt

.Lcmd_ticks:
    puts_label .Lticks_text
    bl timer_get_ticks
    bl uart_putdec
    b .Lnewline

.Lcmd_uptime:
    puts_label .Luptime_text
    bl timer_get_ticks
    mov x19, x0
    mov x1, #100
    udiv x0, x19, x1
    msub x20, x0, x1, x19
    bl uart_putdec
    mov w0, #'.'
    bl uart_putc
    cmp x20, #10
    b.hs .Lcentis
    mov w0, #'0'
    bl uart_putc
.Lcentis:
    mov x0, x20
    bl uart_putdec
    puts_label .Lseconds_suffix
    mov x0, x19
    bl uart_putdec
    puts_label .Lticks_suffix
    b .Lprompt

.Lcmd_yield:
    bl sched_yield
    puts_label .Lyield_text
    b .Lprompt

.Lcmd_ls:
    puts_label .Lls_header
    mov x19, #0
.Lls_row:
    mov x0, x19
    bl ramfs_get_entry
    cbz x0, .Lprompt
    mov x20, x0
    ldr x1, [x20, #24]
    cmp x1, #1
    adr x0, .Ltype_exec
    adr x2, .Ltype_file
    csel x0, x0, x2, eq
    bl uart_puts
    ldr x0, [x20, #16]
    bl .Lput_task_number
    ldr x0, [x20, #0]
    bl uart_puts
    mov w0, #10
    bl uart_putc
    add x19, x19, #1
    b .Lls_row

.Lcmd_cat:
    ldrb w0, [x20]
    cbz w0, .Lcat_usage
    mov x0, x20
    bl ramfs_lookup
    cbz x0, .Lcat_not_found
    ldp x19, x20, [x0, #8]
    mov w21, #10
.Lcat_loop:
    cbz x20, .Lcat_done
    ldrb w21, [x19], #1
    mov w0, w21
    bl uart_putc
    sub x20, x20, #1
    b .Lcat_loop
.Lcat_done:
    cmp w21, #10
    b.ne .Lnewline
    b .Lprompt
.Lcat_usage:
    puts_label .Lcat_usage_text
    b .Lprompt
.Lcat_not_found:
    puts_label .Lcat_not_found_text
    b .Lprompt

.Lcmd_exec:
    ldrb w0, [x20]
    cbz w0, .Lexec_usage
    mov x0, x20
    bl ramfs_lookup
    cbz x0, .Lexec_not_found
    ldr x1, [x0, #24]
    cmp x1, #1
    b.ne .Lexec_not_exec
    ldp x0, x1, [x0, #8]
    bl user_exec_blob
    mov x19, x0
    puts_label .Lexec_exited
    cmp x19, #0
    b.ge .Lexec_print_code
    mov w0, #'-'
    bl uart_putc
    neg x19, x19
.Lexec_print_code:
    mov x0, x19
    bl uart_putdec
    b .Lnewline
.Lexec_usage:
    puts_label .Lexec_usage_text
    b .Lprompt
.Lexec_not_found:
    puts_label .Lexec_not_found_text
    b .Lprompt
.Lexec_not_exec:
    puts_label .Lexec_not_exec_text
    b .Lprompt

.Lcmd_user:
    ldrb w0, [x20]
    cbnz w0, .Luser_check_fault
    mov x0, #0
    bl user_run_demo
    mov x19, x0
    puts_label .Luser_exited
    mov x0, x19
    bl uart_putdec
    b .Lnewline
.Luser_check_fault:
    mov x0, x20
    adr x1, .Larg_fault
    bl strcmp
    cbnz w0, .Luser_usage
    puts_label .Luser_fault_start
    mov x0, #1
    bl user_run_demo
    puts_label .Luser_fault_done
    b .Lprompt
.Luser_usage:
    puts_label .Luser_usage_text
    b .Lprompt

.Lcmd_tasks:
    puts_label .Ltasks_header
    mov x19, #0
.Ltask_row:
    mov x0, x19
    bl sched_get_tcb
    mov x20, x0
    ldr x1, [x20, #8]
    cbz x1, .Lnext_task
    cmp x1, #2
    adr x1, .Ltask_running
    adr x2, .Ltask_ready
    csel x21, x1, x2, eq
    ldp x22, x23, [x20, #24]
    ldr x0, [x20, #16]
    bl uart_putdec
    mov x0, x21
    bl uart_puts
    mov x0, x22
    bl .Lput_task_number
    mov x0, x23
    bl .Lput_task_number
    ldr x0, [x20, #40]
    bl uart_puts
    mov w0, #10
    bl uart_putc
.Lnext_task:
    add x19, x19, #1
    cmp x19, #4
    b.lo .Ltask_row
    puts_label .Lworker_a_iterations
    adrp x0, worker_a_count
    ldr x0, [x0, :lo12:worker_a_count]
    bl uart_putdec
    puts_label .Lworker_b_iterations
    adrp x0, worker_b_count
    ldr x0, [x0, :lo12:worker_b_count]
    bl uart_putdec
    b .Lnewline

.Lcmd_peek:
    mov x0, x20
    bl parse_hex64
    cbz x1, .Lpeek_usage
    tst x0, #7
    b.ne .Lpeek_usage
    ldr x1, [x0]
    mov x19, x1
    bl uart_puthex
    puts_label .Lseparator
    mov x0, x19
    bl uart_puthex
.Lnewline:
    mov w0, #10
    bl uart_putc
    b .Lprompt
.Lpeek_usage:
    puts_label .Lusage
    b .Lprompt

.Lcmd_brk:
    puts_label .Lbrk_text
    brk #0x42
    b .Lprompt
.Lcmd_reboot:
    puts_label .Lreboot_text
    b psci_system_reset
.Lcmd_halt:
    puts_label .Lhalt_text
    b psci_system_off
.size shell_run, . - shell_run

// ABI: Decimal value in x0. Clobbers x0–x4 and NZCV.
.Lput_task_number:
    stp x19, x30, [sp, #-16]!
    mov x19, #10
    mov x1, x0
    mov x2, #10
.Lcount_digits:
    sub x19, x19, #1
    udiv x1, x1, x2
    cbz x1, .Lprint_number
    cmp x19, #1
    b.hi .Lcount_digits
.Lprint_number:
    bl uart_putdec
.Lpad_number:
    mov w0, #' '
    bl uart_putc
    subs x19, x19, #1
    b.ne .Lpad_number
    ldp x19, x30, [sp], #16
    ret

.section .rodata, "a"
.Lprompt_text:    .asciz "talos> "
.Lerase:          .asciz "\b \b"
.Lcancel:         .asciz "^C\n"
.Lunknown:        .asciz "Unknown command: "
.Lhint:           .asciz " (type 'help')\n"
.Lname_help:      .asciz "help"
.Lname_info:      .asciz "info"
.Lname_mmu:       .asciz "mmu"
.Lname_ticks:     .asciz "ticks"
.Lname_uptime:    .asciz "uptime"
.Lname_tasks:     .asciz "tasks"
.Lname_yield:     .asciz "yield"
.Lname_ls:        .asciz "ls"
.Lname_cat:       .asciz "cat"
.Lname_exec:      .asciz "exec"
.Lname_user:      .asciz "user"
.Larg_fault:      .asciz "fault"
.Lname_peek:      .asciz "peek"
.Lname_brk:       .asciz "brk"
.Lname_reboot:    .asciz "reboot"
.Lname_halt:      .asciz "halt"
.Lhelp_text:      .asciz "Commands: help, info, mmu, ticks, uptime, tasks, yield, ls, cat <file>, exec <file>, user [fault], peek <hex_addr>, brk, reboot, halt\n"
.Linfo_el:        .asciz "Talos v0.8.0 (aarch64-virt)\nCurrentEL: "
.Lmpidr:          .asciz "\nMPIDR_EL1: "
.Lvbar:           .asciz "\nVBAR_EL1 : "
.Lcntfrq:         .asciz "\nCNTFRQ   : "
.Lhz_daif:        .asciz " Hz\nDAIF     : "
.Lsctlr:          .asciz "SCTLR_EL1: "
.Lttbr0:          .asciz "\nTTBR0_EL1: "
.Ltcr:            .asciz "\nTCR_EL1  : "
.Lmair:           .asciz "\nMAIR_EL1 : "
.Lmmu_enabled:    .asciz "\nMMU State: ENABLED (4KiB granule, 39-bit VA, 2MiB blocks)\n"
.Lmmu_disabled:   .asciz "\nMMU State: DISABLED\n"
.Lticks_text:     .asciz "Ticks: "
.Luptime_text:    .asciz "Uptime: "
.Lseconds_suffix: .asciz "s ("
.Lticks_suffix:   .asciz " ticks)\n"
.Lseparator:      .asciz ": "
.Ltasks_header:   .asciz "ID  STATE    SWITCHES  TICKS     NAME\n"
.Ltask_ready:     .asciz "   READY    "
.Ltask_running:   .asciz "   RUNNING  "
.Lyield_text:     .asciz "Yielded CPU to scheduler.\n"
.Lls_header:      .asciz "TYPE  SIZE      NAME\n"
.Ltype_file:      .asciz "FILE  "
.Ltype_exec:      .asciz "EXEC  "
.Lcat_usage_text:      .asciz "Usage: cat <filename>\n"
.Lcat_not_found_text:  .asciz "cat: file not found\n"
.Lexec_usage_text:     .asciz "Usage: exec <filename>\n"
.Lexec_not_found_text: .asciz "exec: file not found\n"
.Lexec_not_exec_text:  .asciz "exec: not an executable\n"
.Lexec_exited:         .asciz "Exited with code: "
.Luser_exited:    .asciz "EL0t user process exited with code: "
.Luser_fault_start: .asciz "Launching EL0t fault probe (reading kernel 0x40080000)...\n"
.Luser_fault_done:  .asciz "EL0t fault isolated; returned to shell.\n"
.Luser_usage_text:  .asciz "Usage: user [fault]\n"
.Lworker_a_iterations: .asciz "worker-a iterations: "
.Lworker_b_iterations: .asciz "\nworker-b iterations: "
.Lusage:          .asciz "Usage: peek <8-byte-aligned-hex-addr>\n"
.Lbrk_text:       .asciz "Triggering BRK #0x42...\n"
.Lreboot_text:    .asciz "Rebooting via PSCI SYSTEM_RESET...\n"
.Lhalt_text:      .asciz "Halting via PSCI SYSTEM_OFF...\n"
