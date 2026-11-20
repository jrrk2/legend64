/* SPDX-License-Identifier: Apache-2.0 */
OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { ram (rwx) : ORIGIN = 0x80000000, LENGTH = 0x1000000 }
SECTIONS {
  .text : { *(.text.init) . = ALIGN(0x1000); *(.tohost) . = ALIGN(0x1000); *(.text .text.*) } > ram
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > ram
  .data : ALIGN(8) { *(.data .data.*) __global_pointer$ = . + 0x800; *(.sdata .sdata.*) } > ram
  .bss : ALIGN(8) { _bss_start = .; *(.sbss .sbss.* .bss .bss.* COMMON) . = ALIGN(8); _bss_end = .; } > ram
  _end = .;
  _stack_top = ORIGIN(ram) + LENGTH(ram);
}
