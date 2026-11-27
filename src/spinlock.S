.section .text, "ax"

.global spin_lock
.type spin_lock, %function

// ABI: 32-bit lock pointer in x0. Clobbers x1–x3.
spin_lock:
    mrs x1, sctlr_el1
    tbz x1, #0, 3f
    mov w2, #1
    sevl
1:  wfe
2:  ldaxr w1, [x0]
    cbnz w1, 1b
    stxr w3, w2, [x0]
    cbnz w3, 2b
3:  ret
.size spin_lock, . - spin_lock

.global spin_unlock
.type spin_unlock, %function

// ABI: 32-bit lock pointer in x0. Clobbers x1.
spin_unlock:
    mrs x1, sctlr_el1
    tbz x1, #0, 1f
    stlr wzr, [x0]
1:  ret
.size spin_unlock, . - spin_unlock
