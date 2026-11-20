OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { ram (rwx) : ORIGIN = 0x00000000, LENGTH = 0x80000 }
SECTIONS {
  .text : { KEEP(*(.vectors)) *(.text.init) *(.text .text.*) } > ram
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > ram
  .data : ALIGN(4) { *(.data .data.*) __global_pointer$ = . + 0x800; *(.sdata .sdata.*) } > ram
  .bss : ALIGN(4) { _bss_start = .; *(.sbss .sbss.* .bss .bss.* COMMON) . = ALIGN(4); _bss_end = .; } > ram
  _end = .;
  _stack_top = ORIGIN(ram) + LENGTH(ram);
}
