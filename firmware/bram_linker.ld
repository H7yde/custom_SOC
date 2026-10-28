OUTPUT_ARCH(riscv)
ENTRY(_start)

/* Only the first 1 KiB contains code/data; the rest is explicitly reserved. */
MEMORY
{
    CODE (rwx) : ORIGIN = 0x00000000, LENGTH = 1K
}

SECTIONS
{
    .text : ALIGN(4) {
        KEEP(*(.text.start))
        *(.text .text.*)
        *(.rodata .rodata.* .srodata .srodata.*)
    } > CODE
    .data : ALIGN(4) {
        *(.data .data.* .sdata .sdata.*)
    } > CODE
    .bss (NOLOAD) : ALIGN(4) {
        _bss_start = .;
        *(.bss .bss.* .sbss .sbss.* COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > CODE
    __global_pointer$ = _bss_start + 0x800;
    _stack_top = 0x00000ff0;
    _stack_bottom = _stack_top - 512;
    bram_report = 0x00000800;
    ASSERT(_bss_end <= 0x400, "BRAM-only firmware overlaps its test memory")
    /DISCARD/ : { *(.comment .eh_frame .riscv.attributes) }
}
