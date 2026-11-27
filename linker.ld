OUTPUT_ARCH(aarch64)
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x40080000, LENGTH = 128M
}

PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    .text : ALIGN(4)
    {
        KEEP(*(.text.boot))
        *(.text .text.*)
    } > RAM :text

    .rodata : ALIGN(8)
    {
        *(.rodata .rodata.*)
    } > RAM :text

    .data : ALIGN(8)
    {
        *(.data .data.*)
    } > RAM :data

    .bss (NOLOAD) : ALIGN(16)
    {
        __bss_start = .;
        *(.bss .bss.*) *(COMMON)
        . = ALIGN(16);
        __bss_end = .;
    } > RAM :data

    .stack (NOLOAD) : ALIGN(16)
    {
        . += 0x4000;
        __stack_top = .;
    } > RAM :data

    /DISCARD/ :
    {
        *(.comment) *(.note*) *(.eh_frame*)
    }
}
