// SPDX-License-Identifier: Apache-2.0
// Reset entry of the VC707 boot monitor (boot memory at 0x0001_0000).
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
2:	call main
3:	j 3b

	.align 2
trap_entry:
	la sp, _stack_top
	csrr a0, mcause
	csrr a1, mepc
	csrr a2, mtval
	call trap_report
	j _start
