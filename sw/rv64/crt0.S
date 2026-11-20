// Startup for legend64: reset entry at 0x8000_0000, exit through the HTIF-style tohost word.
	.section .text.init, "ax"
	.global _start
_start:
	la t0, trap_entry
	csrw mtvec, t0
	li t0, 0x2000            // mstatus.FS = Initial: enable the FPU
	csrs mstatus, t0
	fscsr x0
	.option push
	.option norelax
	la gp, __global_pointer$
	.option pop
	la sp, _stack_top
	la a0, _bss_start
	la a1, _bss_end
1:	bgeu a0, a1, 2f
	sd zero, 0(a0)
	addi a0, a0, 8
	j 1b
2:	li a0, 0
	li a1, 0
	call main
	.global _exit
_exit:
	slli a0, a0, 1
	ori a0, a0, 1
	la t0, tohost
	sd a0, 0(t0)
3:	j 3b

	.weak trap_entry
	.align 2
trap_entry:
	li a0, 0xdead
	j _exit

	.section .tohost, "aw", @progbits
	.align 6
	.global tohost
tohost: .dword 0
	.global fromhost
fromhost: .dword 0
