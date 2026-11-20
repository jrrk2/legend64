// SPDX-License-Identifier: Apache-2.0
// Shared startup for all four cores (PicoRV32, Ibex and the two new cores).
// 0x00..0x7c: trap/interrupt vector slots (Ibex-style vectored mtvec at boot_addr)
// 0x80: reset entry (Ibex boot_addr + 0x80; PicoRV32 PROGADDR_RESET = 0x80)
	.option norvc
	.section .vectors, "ax"
	.global _vectors
_vectors:
	.rept 32
	j trap_entry
	.endr
	.global _start
_start:
	li x1, 0
	li x2, 0
	li x3, 0
	li x4, 0
	li x5, 0
	li x6, 0
	li x7, 0
	li x8, 0
	li x9, 0
	li x10, 0
	li x11, 0
	li x12, 0
	li x13, 0
	li x14, 0
	li x15, 0
	li x16, 0
	li x17, 0
	li x18, 0
	li x19, 0
	li x20, 0
	li x21, 0
	li x22, 0
	li x23, 0
	li x24, 0
	li x25, 0
	li x26, 0
	li x27, 0
	li x28, 0
	li x29, 0
	li x30, 0
	li x31, 0
	.option push
	.option norelax
	la gp, __global_pointer$
	.option pop
	la sp, _stack_top
	la a0, _bss_start
	la a1, _bss_end
1:	bgeu a0, a1, 2f
	sw zero, 0(a0)
	addi a0, a0, 4
	j 1b
2:	li a0, 0
	li a1, 0
	call main
	.global _exit
_exit:
	li t0, 0x20000000
	sw a0, 0(t0)
3:	j 3b

	.weak trap_entry
trap_entry:
	li a0, 0xdead
	j _exit
