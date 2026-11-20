// SPDX-License-Identifier: Apache-2.0
// Bare-metal environment for the upstream riscv-tests ISA suite on the shared testbench:
// pass = write 0 to the exit device, fail = write the failing test number.
#ifndef RISCV_TEST_H
#define RISCV_TEST_H
#define RVTEST_RV32U
#define RVTEST_RV64U
#define RVTEST_RV32M
#define TESTNUM gp
#define RVTEST_CODE_BEGIN \
	.section .vectors, "ax"; .option push; .option norvc; \
	.rept 32; j _unexpected_trap; .endr; .option pop; \
	.globl _start; _start: li gp, 0;
#define RVTEST_CODE_END \
	_unexpected_trap: li gp, 0xbad; RVTEST_FAIL
#define RVTEST_PASS li t0, 0x20000000; sw x0, 0(t0); 1: j 1b;
#define RVTEST_FAIL li t0, 0x20000000; sw gp, 0(t0); 1: j 1b;
#define RVTEST_DATA_BEGIN .data; .align 4;
#define RVTEST_DATA_END
#endif
