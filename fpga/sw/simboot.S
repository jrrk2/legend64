// Stand-in for the boot monitor when simulating a Linux boot: the testbench has already put
// the firmware, kernel and device tree in memory, so just enter the firmware the way the
// monitor's loader would (a0 = hart 0, a1 = device tree).
	.section .text.init, "ax"
	.global _start
_start:
	li a0, 0
	li a1, DTB_ADDR
	li t0, 0x80000000
	jr t0
