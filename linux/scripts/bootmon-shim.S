/* Stand-in for the board's boot monitor, used only for the QEMU rehearsal of
 * the board boot flow: enter OpenSBI fw_jump at 0x80000000 in M-mode with
 * a0 = 0 (hart id) and a1 = address of the DTB the monitor loaded. */
	.globl _start
_start:
	li	a0, 0
	li	a1, DTB_ADDR
	li	t0, 0x80000000
	jr	t0
