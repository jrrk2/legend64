# SPDX-License-Identifier: Apache-2.0
# Boot monitor image for the VC707 build: build/fpga/boot.hex (64-bit words for $readmemh).
ROOT := $(abspath ../..)
P    := $(ROOT)/tools/root/usr/bin/riscv64-unknown-elf-
OUT  := $(ROOT)/build/fpga
# The DDR3 initialisation and levelling for LiteDRAM builds is LiteX's own liblitedram, compiled
# from the LiteX submodule against the headers generated with the core (fpga/litedram).
LXSW   := $(ROOT)/third_party/litex/litex/soc/software
GCCINC := $(shell $(P)gcc -print-file-name=include)
DDR_CFLAGS := -march=rv64gc -mabi=lp64d -mcmodel=medany -Os -ffreestanding -fno-builtin -nostdinc -isystem $(GCCINC) \
	-ffunction-sections -fdata-sections -Iddr/shim -I$(ROOT)/fpga/litedram/build/software/include -I$(LXSW)/include \
	-Iddr/cpu -I$(LXSW) -DCONFIG_CPU_NOP='"nop"' -DCSR_BASE=0x40000000L \
	-DMAIN_RAM_BASE=0x80000000UL -DMAIN_RAM_BASE_VA=0x80000000UL -DMAIN_RAM_SIZE=0x40000000UL
DDR_OBJS := $(OUT)/ddr/sdram.o $(OUT)/ddr/accessors.o $(OUT)/ddr/glue.o
$(OUT)/ddr/sdram.o: $(LXSW)/liblitedram/sdram.c $(ROOT)/fpga/litedram/build/software/include/generated/sdram_phy.h
	@mkdir -p $(OUT)/ddr
	$(P)gcc $(DDR_CFLAGS) -c $< -o $@
$(OUT)/ddr/accessors.o: $(LXSW)/liblitedram/accessors.c
	@mkdir -p $(OUT)/ddr
	$(P)gcc $(DDR_CFLAGS) -c $< -o $@
$(OUT)/ddr/glue.o: ddr/glue.c
	@mkdir -p $(OUT)/ddr
	$(P)gcc $(DDR_CFLAGS) -c $< -o $@

CFLAGS := -march=rv64gc -mabi=lp64d -mcmodel=medany -O2 -static -nostdlib -nostartfiles -ffreestanding -fno-builtin-memcpy -fno-math-errno -Wall
$(OUT)/boot.hex: crt0.S monitor.c ../../sw/common/libmin.c link.ld $(DDR_OBJS)
	@mkdir -p $(OUT)
	$(P)gcc $(CFLAGS) -T link.ld -Wl,--no-warn-rwx-segments -Wl,--gc-sections -o $(OUT)/boot.elf crt0.S monitor.c ../../sw/common/libmin.c $(DDR_OBJS)
	$(P)objcopy -O binary $(OUT)/boot.elf $(OUT)/boot.bin
	python3 ../../sw/common/bin2hex.py $(OUT)/boot.bin $@ 8
	$(P)objdump -d $(OUT)/boot.elf > $(OUT)/boot.dis
	@$(P)size $(OUT)/boot.elf

# the same monitor without the power-on self-test, for simulation
$(OUT)/boot_quick.hex: crt0.S monitor.c ../../sw/common/libmin.c link.ld
	$(P)gcc $(CFLAGS) -DQUICK -T link.ld -Wl,--no-warn-rwx-segments -o $(OUT)/boot_quick.elf crt0.S monitor.c ../../sw/common/libmin.c
	$(P)objcopy -O binary $(OUT)/boot_quick.elf $(OUT)/boot_quick.bin
	python3 ../../sw/common/bin2hex.py $(OUT)/boot_quick.bin $@ 8
.DEFAULT_GOAL := all
all: $(OUT)/boot.hex $(OUT)/boot_quick.hex

# reset stub for the Linux boot simulation (fpga/tb/tb_linux.sv)
DTB_ADDR ?= 0x86000000
$(OUT)/boot_linuxsim.hex: simboot.S
	$(P)gcc -march=rv64gc -mabi=lp64d -nostdlib -nostartfiles -DDTB_ADDR=$(DTB_ADDR) -Ttext=0x10000 -Wl,--no-warn-rwx-segments -o $(OUT)/boot_linuxsim.elf simboot.S
	$(P)objcopy -O binary $(OUT)/boot_linuxsim.elf $(OUT)/boot_linuxsim.bin
	python3 ../../sw/common/bin2hex.py $(OUT)/boot_linuxsim.bin $@ 8
