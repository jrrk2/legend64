# SPDX-License-Identifier: Apache-2.0
# Trap entry under interrupts. User code (Sv39) makes system calls and touches pages that are
# not there; the supervisor's handler starts as Linux's does (csrrw tp, sscratch, tp; bnez tp;
# sd sp, 24(tp)) and checks what it finds. The machine's handler re-arms the timer at a varying
# distance and raises the supervisor's timer; the test bench's external interrupt for the
# supervisor arrives at a varying distance too, so interrupts land on every part of a page walk
# and of the handler's entry. Run by scripts/trapstress_legend64.sh.
# Exit codes: 0 passed; 2..6 the supervisor's handler found something wrong (4: a trap taken
# inside the handler); 7 the user's tp changed; 9 the machine's handler was entered for
# something else.
#define USER_TP  0x10000100          /* not mapped: a store through it faults */
#define UALIAS   0x40000000          /* user view of the RAM at 0x80000000 */
#define CLINT_CMP 0x02004000
#define CLINT_TIME 0x0200bff8
#ifndef ENTRIES
#define ENTRIES 40000          /* the test ends after this many entries of the supervisor's handler */
#endif
        .section .text.init
        .globl _start
_start: la   t0, mtrap
        csrw mtvec, t0
        la   t0, mscr
        csrw mscratch, t0
        la   t0, pt                     # root table: [2] supervisor identity, [1] user alias
        li   t1, (0x80000 << 10) | 0xcf
        sd   t1, 16(t0)
        li   t1, (0x80000 << 10) | 0xdf
        sd   t1, 8(t0)
        li   t1, 0xcf                   # [0]: the devices, for the supervisor
        sd   t1, 0(t0)
        la   t1, pt1                    # [3]: two more levels, and nothing at the end of them
        srli t1, t1, 2
        ori  t1, t1, 1
        sd   t1, 24(t0)
        la   t2, pt0
        srli t2, t2, 2
        ori  t2, t2, 1
        la   t1, pt1
        sd   t2, 0(t1)
        srli t0, t0, 12
        li   t1, 8 << 60
        or   t0, t0, t1
        csrw satp, t0
        li   t0, (1 << 8) | (1 << 12) | (1 << 13) | (1 << 15)
        csrw medeleg, t0
        li   t0, (1 << 5) | (1 << 9)
        csrw mideleg, t0
        li   t0, (1 << 7) | (1 << 5) | (1 << 9)
        csrw mie, t0
        la   t0, strap
        csrw stvec, t0
        la   t0, ktask
        csrw sscratch, t0
        la   t1, kstack_top
        sd   t1, 16(t0)
        li   t0, 0x1800                 # MPP = user
        csrc mstatus, t0
        li   t0, 0x80
        csrs mstatus, t0
        la   t0, user
        li   t1, 0x80000000 - UALIAS
        sub  t0, t0, t1
        csrw mepc, t0
        li   t0, CLINT_TIME
        ld   t0, 0(t0)
        addi t0, t0, 200
        li   t1, CLINT_CMP
        sd   t0, 0(t1)
        li   t0, 0x02000008
        li   t1, 300
        sd   t1, 0(t0)
        li   tp, USER_TP
        la   sp, ustack_top
        li   t1, 0x80000000 - UALIAS
        sub  sp, sp, t1
        mret

        # ------------------------------------------------ machine: timer, and the supervisor's call
        .align 2
mtrap:  csrrw tp, mscratch, tp
        sd   t0, 0(tp)
        sd   t1, 8(tp)
        csrr t0, mcause
        bgez t0, 2f
        ld   t0, 16(tp)                 # timer: a distance that walks through 0..126
        addi t0, t0, 37
        andi t0, t0, 127
        sd   t0, 16(tp)
        li   t1, CLINT_TIME
        ld   t1, 0(t1)
        add  t0, t0, t1
        addi t0, t0, 350
        li   t1, CLINT_CMP
        sd   t0, 0(t1)
        li   t0, 1 << 5
        csrs mip, t0
1:      ld   t0, 0(tp)
        ld   t1, 8(tp)
        csrrw tp, mscratch, tp
        mret
2:      li   t1, 9                      # call from supervisor: clear its timer interrupt
        bne  t0, t1, mfail
        li   t0, 1 << 5
        csrc mip, t0
        csrr t0, mepc
        addi t0, t0, 4
        csrw mepc, t0
        j    1b
mfail:  li   a0, 9
        j    fail

        # ------------------------------------------------ supervisor
        .align 2
strap:  csrrw tp, sscratch, tp
        bnez tp, 1f
        li   a0, 2                      # entered from the supervisor: never happens here
        j    fail
1:      sd   sp, 24(tp)
        ld   sp, 16(tp)
        addi sp, sp, -32
        sd   t0, 0(sp)
        sd   t1, 8(sp)
        la   t0, ktask
        beq  tp, t0, 2f
        li   a0, 3                      # the swap did not give the supervisor's pointer
        j    fail
2:      csrr t0, sstatus
        andi t0, t0, 0x100
        beqz t0, 3f
        li   a0, 4                      # a trap taken inside the handler
        j    fail
3:      csrr t0, sscratch
        li   t1, USER_TP
        beq  t0, t1, 4f
        li   a0, 5                      # the user's tp was not what the swap left
        j    fail
4:      csrw sscratch, zero
        ld   t0, 48(tp)                 # count the entries; enough of them end the test
        addi t0, t0, 1
        sd   t0, 48(tp)
        li   t1, ENTRIES
        bltu t0, t1, 41f
        li   a0, 1
        j    7f
41:     csrr t0, scause
        bltz t0, 6f
        li   t1, 8
        beq  t0, t1, 51f
        li   t1, 13
        beq  t0, t1, 52f
        li   t1, 15
        beq  t0, t1, 52f
        j    5f
51:     bnez a0, 7f                     # the user reports a failure
        csrr t0, sepc
        addi t0, t0, 4
        csrw sepc, t0
        j    8f
52:     csrr t0, sepc                   # a page that is not there: step over the access
        addi t0, t0, 4
        csrw sepc, t0
        j    8f
5:      li   a0, 6                      # an exception that is not the user's call
        j    fail
6:      slli t0, t0, 1
        srli t0, t0, 1
        li   t1, 9
        bne  t0, t1, 61f
        ld   t0, 40(tp)                 # external: again after a distance that walks through 0..126
        addi t0, t0, 41
        andi t0, t0, 127
        sd   t0, 40(tp)
        addi t0, t0, 120
        li   t1, 0x02000008
        sd   t0, 0(t1)
        j    8f
61:     ecall                           # timer: ask the machine to clear it
        ld   t0, 32(tp)
        addi t0, t0, 1
        sd   t0, 32(tp)
        andi t0, t0, 15                 # now and then, flush the translations as a kernel would
        bnez t0, 8f
        sfence.vma
8:      ld   t0, 0(sp)
        ld   t1, 8(sp)
        csrw sscratch, tp
        ld   sp, 24(tp)
        li   tp, USER_TP
        sret
7:      li   t0, 1
        bne  a0, t0, fail
        li   a0, 0
fail:   slli a0, a0, 1
        ori  a0, a0, 1
        la   t0, tohost
        sd   a0, 0(t0)
9:      j    9b

        # ------------------------------------------------ user
        .align 2
user:   li   s1, USER_TP
        li   s2, 0
        li   s3, 0xc0000000
1:      li   a0, 0
        addi s2, s2, 1
        andi t2, s2, 7                  # a varying run of work before each call
2:      beqz t2, 3f
        sd   s2, -8(sp)
        ld   t3, -8(sp)
        mul  t3, t3, s2
        addi t2, t2, -1
        j    2b
3:      .option push
        .option norvc
        sd   s2, 8(s3)                  # a store and a load with no page behind them
        ld   t3, 16(s3)
        .option pop
        ecall
        beq  tp, s1, 1b
4:      li   a0, 7                      # the user's tp changed
        ecall

        .section .tohost, "aw"
        .globl tohost
tohost: .dword 0
        .data
        .align 12
pt:     .fill 512, 8, 0
pt1:    .fill 512, 8, 0
pt0:    .fill 512, 8, 0
mscr:   .fill 8, 8, 0
ktask:  .fill 8, 8, 0
        .fill 512, 8, 0
kstack_top:
        .fill 64, 8, 0
ustack_top:
