# SPDX-License-Identifier: Apache-2.0
# Builds the benchmark and ISA-test images. ARCH=rv32im for the PicoRV32-class cores,
# ARCH=rv32imc for the Ibex-class cores.
ARCH ?= rv32im
ROOT := $(abspath ..)
P    := $(ROOT)/tools/root/usr/bin/riscv64-unknown-elf-
OUT  := $(ROOT)/build/sw/$(ARCH)
RT   := $(ROOT)/ref/ibex/vendor/riscv-tests/isa
BASE := -march=$(ARCH)_zicsr_zifencei -mabi=ilp32 -static -mcmodel=medlow -nostdlib -nostartfiles -ffreestanding -Icommon
LINK := -T common/link.ld -Wl,--no-warn-rwx-segments -lgcc
COMMON := common/crt0.S common/libmin.c
CM_ITER ?= 10
CM_FLAGS := -O3 -mtune=sifive-3-series -falign-functions=16 -funroll-all-loops -finline-functions -falign-jumps=4 -mstrict-align
DH_FLAGS := -std=gnu89 -O3 -DTIME -DRISCV -DUSE_MYSTDLIB -w -fno-builtin

ISA_UI := $(filter-out fence_i,$(basename $(notdir $(wildcard $(RT)/rv32ui/*.S)))) fence_i
ISA_UM := $(basename $(notdir $(wildcard $(RT)/rv32um/*.S)))
ISA := $(addprefix ui-,$(ISA_UI)) $(addprefix um-,$(ISA_UM))
ifeq ($(ARCH),rv32imc)
ISA += uc-rvc
endif

all: $(OUT)/dhrystone.hex $(OUT)/coremark.hex $(addprefix $(OUT)/isa/,$(addsuffix .hex,$(ISA)))

$(OUT)/dhrystone.elf: $(wildcard dhrystone/*.c) $(COMMON)
	@mkdir -p $(@D)
	$(P)gcc $(BASE) $(DH_FLAGS) -o $@ $(COMMON) dhrystone/dhry_1.c dhrystone/dhry_2.c dhrystone/stdlib.c $(LINK)

$(OUT)/coremark.elf: $(wildcard coremark/*.c) $(COMMON)
	@mkdir -p $(@D)
	$(P)gcc $(BASE) $(CM_FLAGS) -Icoremark -DTOTAL_DATA_SIZE=2000 -DPERFORMANCE_RUN=1 -DITERATIONS=$(CM_ITER) \
	  -DFLAGS_STR='"$(CM_FLAGS)"' -o $@ $(COMMON) $(wildcard coremark/*.c) $(LINK)

$(OUT)/isa/ui-%.elf: $(RT)/rv32ui/%.S isa/riscv_test.h
	@mkdir -p $(@D)
	$(P)gcc $(BASE) -Iisa -I$(RT)/macros/scalar -o $@ $< $(LINK)
$(OUT)/isa/um-%.elf: $(RT)/rv32um/%.S isa/riscv_test.h
	@mkdir -p $(@D)
	$(P)gcc $(BASE) -Iisa -I$(RT)/macros/scalar -o $@ $< $(LINK)
$(OUT)/isa/uc-%.elf: $(RT)/rv32uc/%.S isa/riscv_test.h
	@mkdir -p $(@D)
	$(P)gcc $(BASE) -Iisa -I$(RT)/macros/scalar -o $@ $< $(LINK)

%.hex: %.elf
	$(P)objcopy -O binary $< $*.bin
	python3 common/bin2hex.py $*.bin $@
	$(P)objdump -d -M no-aliases $< > $*.dis

.PRECIOUS: %.elf
