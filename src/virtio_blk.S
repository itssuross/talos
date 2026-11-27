.equ QUEUE_SIZE,       8
.equ VQ_AVAIL,         0x080
.equ VQ_USED,          0x1000
.equ DEVICE_FEATURES,  0x010
.equ DEVICE_FEAT_SEL,  0x014
.equ DRIVER_FEATURES,  0x020
.equ DRIVER_FEAT_SEL,  0x024
.equ GUEST_PAGE_SIZE,  0x028
.equ QUEUE_SEL,        0x030
.equ QUEUE_NUM_MAX,    0x034
.equ QUEUE_NUM,        0x038
.equ QUEUE_ALIGN,      0x03c
.equ QUEUE_PFN,        0x040
.equ QUEUE_READY,      0x044
.equ QUEUE_NOTIFY,     0x050
.equ INTERRUPT_STATUS, 0x060
.equ INTERRUPT_ACK,    0x064
.equ DEVICE_STATUS,    0x070
.equ QUEUE_DESC,       0x080
.equ QUEUE_DRIVER,     0x090
.equ QUEUE_DEVICE,     0x0a0
.equ CONFIG_GEN,       0x0fc

.section .bss, "aw", @nobits
.balign 4096
vq_mem:
    .skip 8192
.balign 4
blk_lock:
    .word 0
blk_present:
    .word 0
blk_version:
    .word 0
blk_readonly:
    .word 0
.balign 2
blk_avail_idx:
    .hword 0
blk_last_used_idx:
    .hword 0
.balign 8
blk_base:
    .quad 0
blk_capacity:
    .quad 0
.balign 16
blk_req_hdr:
    .skip 16
.balign 4
blk_status:
    .word 0
.balign 16
.Lstate_end:

.section .text, "ax"

.global blk_init
.type blk_init, %function

// ABI: Boot CPU only. Returns presence in w0. Clobbers x0–x12 and NZCV.
blk_init:
    adr x1, vq_mem
    adr x2, .Lstate_end
.Lclear:
    stp xzr, xzr, [x1], #16
    cmp x1, x2
    b.lo .Lclear

    mov x1, #0x0a000000
    add x2, x1, #0x4000
    ldr w3, =0x74726976
.Lscan:
    ldr w4, [x1]
    cmp w4, w3
    b.ne .Lnext
    ldr w4, [x1, #8]           // DeviceID
    cmp w4, #2
    b.ne .Lnext
    ldr w5, [x1, #4]           // Version
    cmp w5, #1
    b.eq .Lfound
    cmp w5, #2
    b.eq .Lfound
.Lnext:
    add x1, x1, #0x200
    cmp x1, x2
    b.lo .Lscan
.Labsent:
    mov w0, #0
    ret

.Lfound:
    str wzr, [x1, #DEVICE_STATUS]
.Lreset_wait:
    ldr w4, [x1, #DEVICE_STATUS]
    cbnz w4, .Lreset_wait
    mov w4, #1                 // ACKNOWLEDGE
    str w4, [x1, #DEVICE_STATUS]
    mov w4, #3                 // ACKNOWLEDGE | DRIVER
    str w4, [x1, #DEVICE_STATUS]
    str wzr, [x1, #DEVICE_FEAT_SEL]
    ldr w6, [x1, #DEVICE_FEATURES]
    ubfx w6, w6, #5, #1        // VIRTIO_BLK_F_RO
    str wzr, [x1, #DRIVER_FEAT_SEL]
    str wzr, [x1, #DRIVER_FEATURES]
    mov w7, #1
    cmp w5, #1
    b.ne .Lmodern_features
    mov w8, #4096
    str w8, [x1, #GUEST_PAGE_SIZE]
    b .Lqueue
.Lmodern_features:
    str w7, [x1, #DEVICE_FEAT_SEL]
    ldr w8, [x1, #DEVICE_FEATURES]
    tbz w8, #0, .Lfailed       // VIRTIO_F_VERSION_1 (bit 32)
    str w7, [x1, #DRIVER_FEAT_SEL]
    str w7, [x1, #DRIVER_FEATURES]
    orr w4, w4, #8             // FEATURES_OK
    str w4, [x1, #DEVICE_STATUS]
    ldr w4, [x1, #DEVICE_STATUS]
    tbz w4, #3, .Lfailed
.Lqueue:
    str wzr, [x1, #QUEUE_SEL]
    ldr w8, [x1, #QUEUE_NUM_MAX]
    cmp w8, #QUEUE_SIZE
    b.lo .Lfailed
    mov w8, #QUEUE_SIZE
    str w8, [x1, #QUEUE_NUM]
    adr x9, vq_mem
    add x10, x9, #VQ_AVAIL
    strh w7, [x10]             // VRING_AVAIL_F_NO_INTERRUPT
    dsb sy
    cmp w5, #1
    b.ne .Lmodern_queue
    mov w8, #4096
    str w8, [x1, #QUEUE_ALIGN]
    lsr x8, x9, #12
    str w8, [x1, #QUEUE_PFN]
    b .Lstart
.Lmodern_queue:
    str w9, [x1, #QUEUE_DESC]
    lsr x8, x9, #32
    str w8, [x1, #(QUEUE_DESC + 4)]
    str w10, [x1, #QUEUE_DRIVER]
    lsr x8, x10, #32
    str w8, [x1, #(QUEUE_DRIVER + 4)]
    add x10, x9, #VQ_USED
    str w10, [x1, #QUEUE_DEVICE]
    lsr x8, x10, #32
    str w8, [x1, #(QUEUE_DEVICE + 4)]
    str w7, [x1, #QUEUE_READY]
.Lstart:
    orr w4, w4, #4             // DRIVER_OK
    str w4, [x1, #DEVICE_STATUS]
.Lcapacity:
    cmp w5, #2
    b.ne .Lcapacity_words
    ldr w12, [x1, #CONFIG_GEN]
.Lcapacity_words:
    ldr w8, [x1, #0x100]       // capacity in 512-byte sectors
    ldr w9, [x1, #0x104]
    orr x8, x8, x9, lsl #32
    cmp w5, #2
    b.ne .Lonline
    ldr w10, [x1, #CONFIG_GEN]
    cmp w10, w12
    b.ne .Lcapacity
.Lonline:
    adr x9, blk_base
    stp x1, x8, [x9]
    adr x9, blk_version
    stp w5, w6, [x9]
    adr x9, blk_present
    stlr w7, [x9]
    mov w0, #1
    ret
.Lfailed:
    orr w4, w4, #128           // FAILED
    str w4, [x1, #DEVICE_STATUS]
    b .Labsent
.size blk_init, . - blk_init

.global blk_read_sector
.type blk_read_sector, %function

// ABI: Sector in x0, 512-byte destination in x1. Returns 0 or -1 in x0. Clobbers caller-saved registers and NZCV.
blk_read_sector:
    mov w2, #0
    b .Lblk_rw
.size blk_read_sector, . - blk_read_sector

.global blk_write_sector
.type blk_write_sector, %function

// ABI: Sector in x0, 512-byte source in x1. Returns 0 or -1 in x0. Clobbers caller-saved registers and NZCV.
blk_write_sector:
    mov w2, #1
    b .Lblk_rw
.size blk_write_sector, . - blk_write_sector

// ABI: Sector in x0, buffer in x1, request type in w2. Returns 0 or -1 in x0. Clobbers caller-saved registers and NZCV.
.Lblk_rw:
    stp x19, x20, [sp, #-32]!
    stp x21, x30, [sp, #16]
    mov x19, x0
    mov x20, x1
    mov w21, w2
    adr x0, blk_lock
    bl spin_lock
    adr x3, blk_present
    ldar w4, [x3]
    cbz w4, .Lio_error
    adr x4, blk_base
    ldp x5, x6, [x4]
    cmp x19, x6
    b.hs .Lio_error
    cbz w21, .Lrequest
    adr x4, blk_readonly
    ldr w4, [x4]
    cbnz w4, .Lio_error
.Lrequest:
    adr x4, blk_req_hdr
    stp w21, wzr, [x4]
    str x19, [x4, #8]
    adr x6, blk_status
    mov w7, #0xff
    strb w7, [x6]

    adr x7, vq_mem
    str x4, [x7]
    mov w8, #16
    mov w9, #0x10001           // NEXT, next = 1
    stp w8, w9, [x7, #8]
    str x20, [x7, #16]
    mov w8, #512
    mov w9, #0x20000
    orr w9, w9, #1             // NEXT, next = 2
    cbnz w21, .Ldata_flags
    orr w9, w9, #2             // device writes read data
.Ldata_flags:
    stp w8, w9, [x7, #24]
    str x6, [x7, #32]
    mov w8, #1
    mov w9, #2                 // WRITE
    stp w8, w9, [x7, #40]
    adr x8, blk_avail_idx
    ldrh w9, [x8]
    and w10, w9, #(QUEUE_SIZE - 1)
    add x11, x7, #(VQ_AVAIL + 4)
    strh wzr, [x11, x10, lsl #1]
    dmb ishst
    add w9, w9, #1
    uxth w9, w9
    strh w9, [x8]
    strh w9, [x7, #(VQ_AVAIL + 2)]
    dsb sy
    str wzr, [x5, #QUEUE_NOTIFY]

    add x10, x7, #VQ_USED
    add x10, x10, #2           // used.idx
    ldr w11, =10000000
.Lpoll:
    ldarh w12, [x10]
    cmp w12, w9
    b.eq .Lcomplete
    subs w11, w11, #1
    b.ne .Lpoll
    stlr wzr, [x3]
    str wzr, [x5, #DEVICE_STATUS]
.Lstop_dma:
    ldr w10, [x5, #DEVICE_STATUS]
    cbnz w10, .Lstop_dma
    dsb sy
    b .Lio_error
.Lcomplete:
    dmb ishld
    adr x10, blk_last_used_idx
    strh w12, [x10]
    ldr w10, [x5, #INTERRUPT_STATUS]
    str w10, [x5, #INTERRUPT_ACK]
    ldrb w10, [x6]
    cmp w10, #0
    csetm x19, ne
    b .Lunlock
.Lio_error:
    mov x19, #-1
.Lunlock:
    adr x0, blk_lock
    bl spin_unlock
    mov x0, x19
    ldp x21, x30, [sp, #16]
    ldp x19, x20, [sp], #32
    ret

.global blk_get_info
.type blk_get_info, %function

// ABI: 24-byte output in x0 (base, sectors, version, readonly). Returns presence in w0. Clobbers x0–x5.
blk_get_info:
    adr x1, blk_present
    ldar w5, [x1]
    adr x1, blk_base
    ldp x2, x3, [x1]
    stp x2, x3, [x0]
    adr x1, blk_version
    ldp w2, w3, [x1]
    stp w2, w3, [x0, #16]
    mov w0, w5
    ret
.size blk_get_info, . - blk_get_info
