OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    BRAM (rwx) : ORIGIN = 0x00000000, LENGTH = 4K
}

SECTIONS
{
    .text : ALIGN(4) {
        KEEP(*(.text.start))
        *(.text .text.*)
        *(.rodata .rodata.* .srodata .srodata.*)
    } > BRAM

    .data : ALIGN(4) {
        *(.data .data.* .sdata .sdata.*)
    } > BRAM

    .bss (NOLOAD) : ALIGN(4) {
        _bss_start = .;
        *(.bss .bss.* .sbss .sbss.* COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > BRAM

    __global_pointer$ = _bss_start + 0x800;
    _stack_top = ORIGIN(BRAM) + LENGTH(BRAM) - 16;
    _stack_bottom = _stack_top - 512;
    ASSERT(_bss_end <= _stack_bottom,
           "Firmware exceeds 4 KiB BRAM with 512-byte stack reserve")
    /DISCARD/ : { *(.comment .eh_frame .riscv.attributes) }
}
