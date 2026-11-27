OUTPUT_ARCH(aarch64)
ENTRY(_start)

PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    . = 0x40200000;
    .text : ALIGN(16) { KEEP(*(.text.entry)) *(.text .text.*) } :text
    .rodata : ALIGN(16) { *(.rodata .rodata.*) } :text
    .data : ALIGN(16) { *(.data .data.*) } :data
    .bss : ALIGN(16) { *(.bss .bss.*) *(COMMON) } :data
    /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
