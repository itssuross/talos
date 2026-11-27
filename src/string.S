.section .text, "ax"

.global strcmp
.type strcmp, %function

// ABI: Strings in x0 and x1, unsigned byte difference in w0. Clobbers x0–x3 and NZCV.
strcmp:
    ldrb w2, [x0], #1
    ldrb w3, [x1], #1
    cmp w2, w3
    b.ne .Lcmp_done
    cbnz w2, strcmp
.Lcmp_done:
    sub w0, w2, w3
    ret
.size strcmp, . - strcmp

.global skip_spaces
.type skip_spaces, %function

// ABI: String in x0, first non-space/tab pointer in x0. Clobbers x0–x1 and NZCV.
skip_spaces:
    ldrb w1, [x0]
    cmp w1, #' '
    b.eq .Lskip_byte
    cmp w1, #9
    b.ne .Lskip_done
.Lskip_byte:
    add x0, x0, #1
    b skip_spaces
.Lskip_done:
    ret
.size skip_spaces, . - skip_spaces

.global parse_hex64
.type parse_hex64, %function

// ABI: String in x0, value in x0 and success flag in x1. Clobbers x0–x5 and NZCV.
parse_hex64:
    mov x2, x0
    mov x0, #0
    mov w3, #0
    ldrb w4, [x2]
    cmp w4, #'0'
    b.ne .Lhex_digit
    ldrb w4, [x2, #1]
    orr w4, w4, #0x20
    cmp w4, #'x'
    b.ne .Lhex_digit
    add x2, x2, #2
.Lhex_digit:
    ldrb w4, [x2], #1
    cbz w4, .Lhex_done
    cmp w4, #' '
    b.eq .Lhex_done
    cmp w4, #9
    b.eq .Lhex_done
    cmp w3, #16
    b.eq .Lhex_invalid
    sub w5, w4, #'0'
    cmp w5, #9
    b.ls .Lhex_append
    orr w4, w4, #0x20
    sub w5, w4, #'a'
    cmp w5, #5
    b.hi .Lhex_invalid
    add w5, w5, #10
.Lhex_append:
    orr x0, x5, x0, lsl #4
    add w3, w3, #1
    b .Lhex_digit
.Lhex_done:
    cmp w3, #0
    cset x1, ne
    ret
.Lhex_invalid:
    mov x0, #0
    mov x1, #0
    ret
.size parse_hex64, . - parse_hex64

.global parse_u64
.type parse_u64, %function

// ABI: String in x0, value in x0 and success flag in x1. Clobbers x0–x7 and NZCV.
parse_u64:
    ldrb w1, [x0]
    cmp w1, #'0'
    b.ne .Ldec_start
    ldrb w1, [x0, #1]
    orr w1, w1, #0x20
    cmp w1, #'x'
    b.eq parse_hex64
.Ldec_start:
    mov x2, x0
    mov x0, #0
    mov w3, #0
    mov x4, #10
    mov x5, #-1
    udiv x5, x5, x4
.Ldec_next:
    ldrb w6, [x2], #1
    sub w7, w6, #'0'
    cmp w7, #9
    b.hi .Ldec_end
    cmp w3, #20
    b.hs .Ldec_invalid
    cmp x0, x5
    b.hi .Ldec_invalid
    b.ne .Ldec_append
    cmp w7, #5
    b.hi .Ldec_invalid
.Ldec_append:
    madd x0, x0, x4, x7
    add w3, w3, #1
    b .Ldec_next
.Ldec_end:
    cbz w6, .Ldec_done
    cmp w6, #' '
    b.eq .Ldec_done
    cmp w6, #9
    b.ne .Ldec_invalid
.Ldec_done:
    cmp w3, #0
    cset x1, ne
    ret
.Ldec_invalid:
    mov x0, #0
    mov x1, #0
    ret
.size parse_u64, . - parse_u64
