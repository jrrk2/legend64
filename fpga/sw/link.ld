/* SPDX-License-Identifier: Apache-2.0 */
OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { boot (rwx) : ORIGIN = 0x10000, LENGTH = 0x10000 }
SECTIONS {
  .text : { *(.text.init) *(.text .text.*) } > boot
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > boot
  .data : ALIGN(8) { *(.data .data.*) __global_pointer$ = . + 0x800; *(.sdata .sdata.*) } > boot
  .bss : ALIGN(8) { _bss_start = .; *(.sbss .sbss.* .bss .bss.* COMMON) . = ALIGN(8); _bss_end = .; } > boot
  _end = .;
  _stack_top = ORIGIN(boot) + LENGTH(boot);
}
