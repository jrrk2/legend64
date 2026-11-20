# legend64 task list

Roughly in priority order within each section. Measurements are from the VC707 at 50 MHz.

## In progress

- **A kernel oops seen once on the board:** the trap handler entered a second time while still on
  user registers (`handle_exception+0x8c`, in `systemd-sysctl`). Looks like a rare fault in the
  core's trap or interrupt entry. Not reproduced, not investigated.
- **CoreMark, Dhrystone and Whetstone** on the board, and the same on Rocket.
- **synthgui's open flow** (`synthgui/`): the design synthesises, places and routes at 12.5 MHz
  with every clock passing, but the bitstream is silent on the board: the core never runs the
  monitor. The same mapper netlist placed and routed by Vivado is silent too. A Vivado-synthesised
  12.5 MHz build is the control that tells a mapper fault from a 12.5 MHz fault in the design;
  built, not yet run. LVS proves the logic and cannot check the PLL and the MMCME2_BASE.
- **Timing margin:** the 1 MiB cache build with the corrected MAC closes at +0.003 ns.

## Done recently

- TCP transmit loss with segmentation: the MAC's transmit side counted its inter-frame gap only
  once after reset (see `fpga/third_party/verilog-ethernet/`). Sending is now 68 Mbit/s with no
  retransmits.
- Rocket comparison on the same NFS root: see the measurements in the commit that added this.

## Memory system

- Second-level TLB consulted on a miss, and ASIDs so that a context switch does not flush the
  TLBs. (32-entry first-level TLBs meet timing at +0.003 ns; decide whether to keep them.)
- Split or set-associative caches; today one direct-mapped cache serves instructions, data and
  the Ethernet DMA. Design it with multi-core coherence in mind.
- Cheaper misses: skip the read when a whole line is about to be overwritten (receive DMA,
  sequential fills), next-line prefetch.
- Timing margin: the 1 MiB cache build closes at +0.11 ns.

## Ethernet

- Receive FIFO still overflows now and then under iperf3 (drain into memory is slower than the
  wire when lines miss).
- Jumbo frames (hardware limit is 1518 bytes; needs host and switch MTU changes too).
- Consider moving to verilog-ethernet's current MAC; the copy in use is a 2019 fork of it.
- Second stage of offloading: the full flow engine from vc707_romlinux_toe, kernel-driven.
- Hardware receive coalescing, if measurements justify it once transmit is fixed.

## Core

- A real `wfi` (today it is a no-op, so the idle loop spins).
- Faster divider (66 cycles, fixed).
- Higher clock: the pipeline's long paths limit it to 50 MHz.
- SMP: needs per-core caches with coherence, atomics that hold a line exclusively, per-hart
  interrupt plumbing, and a multi-core stress test.
- Performance counters, debug module.

## Low priority

- **PMP (physical memory protection).** Not implemented: the firmware cannot fence its memory
  off from the kernel, and the `rv64mi-pmpaddr` ISA test fails. Process and kernel/user
  protection through Sv39 is complete and unaffected. The comparisons would sit on the address
  path that limits the clock, so do it after the memory-system work.
- Misaligned loads and stores trap (`ma_data` tests fail); firmware emulation or hardware support.
- UART transmit FIFO (the device tree says `ns16550`, not `ns16550a`, because there is none).
- Why the Xilinx memory interface never calibrates in this design (LiteDRAM is used instead).
- Reset / power-off device for clean reboots.

## Housekeeping

- Move the NFS export to `/srv/nfs/legend64` and set the hostname inside the tree (needs root on
  the host), then update `nfsroot=` in `linux/dts/legend64-vc707.dts`.
- Serial password login times out; probably the 6.7 s yescrypt hash plus slow start-up, unconfirmed.
- Decide whether `third_party/synthgui` stays a submodule or its five source files are copied in.
- Rename the working directory `~/riscv` when nothing is running in it.
