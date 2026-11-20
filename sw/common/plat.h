// SPDX-License-Identifier: Apache-2.0
#ifndef PLAT_H
#define PLAT_H
// Testbench devices and counters. The console is at the same address on every platform.
#define PLAT_PUTC (*(volatile unsigned int *)0x10000000) // W: character out
#if __riscv_xlen == 64
// legend64: machine-mode counters
static inline unsigned long plat_cycles(void) { unsigned long v; __asm__ volatile("csrr %0, mcycle" : "=r"(v)); return v; }
static inline unsigned long plat_insns(void) { unsigned long v; __asm__ volatile("csrr %0, minstret" : "=r"(v)); return v; }
#else
// 32-bit testbenches: counters are testbench devices so that every core is timed the same way
#define PLAT_EXIT (*(volatile unsigned int *)0x20000000) // W: stop simulation, value = exit code
static inline unsigned long plat_cycles(void) { return *(volatile unsigned int *)0x30000000; }
static inline unsigned long plat_insns(void) { return *(volatile unsigned int *)0x30000004; }
#endif
#endif
