/* RV32I reset entry. The image is loaded directly at BRAM address zero. */
    .section .text.start,"ax",@progbits
    .global _start
    .type _start, @function
_start:
    .option push
    .option norelax
    la sp, _stack_top
    la gp, __global_pointer$
    .option pop
    la t0, _bss_start
    la t1, _bss_end
1:
    bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b
2:
    call main
3:
    j 3b
    .size _start, .-_start
