# RV64G images for fable64: the upstream riscv-tests ISA suite (standard "p" environment)
# and the benchmarks. Outputs go to build/sw/rv64/.
ROOT := $(abspath ../..)
P    := $(ROOT)/tools/root/usr/bin/riscv64-unknown-elf-
OUT  := $(ROOT)/build/sw/rv64
RT   := $(ROOT)/ref/riscv-tests
ARCH := -march=rv64gc -mabi=lp64d
ISA_FLAGS := $(ARCH) -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles \
             -I$(RT)/env/p -I$(RT)/isa/macros/scalar -T$(RT)/env/p/link.ld -Wl,--no-warn-rwx-segments

SUITES := rv64ui rv64um rv64ua rv64uf rv64ud rv64uc rv64mi rv64si
ISA := $(foreach s,$(SUITES),$(addprefix $(s)-,$(basename $(notdir $(wildcard $(RT)/isa/$(s)/*.S)))))

BM_FLAGS := $(ARCH) -static -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -I../common \
            -T link.ld -Wl,--no-warn-rwx-segments
COMMON := crt0.S ../common/libmin.c
CM_ITER ?= 10
CM_FLAGS := -O3 -falign-functions=16 -funroll-all-loops -finline-functions -falign-jumps=4
DH_FLAGS := -std=gnu89 -O3 -DTIME -DRISCV -DUSE_MYSTDLIB -w -fno-builtin

# the same tests in the "v" environment: user mode under Sv39 with demand paging
VSUITES := rv64ui rv64um rv64ua rv64uf rv64ud rv64uc
VISA := $(foreach s,$(VSUITES),$(addprefix $(s)-v-,$(basename $(notdir $(wildcard $(RT)/isa/$(s)/*.S)))))
VENV := $(RT)/env/v
VFLAGS := $(ARCH) -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -ffreestanding -O2 -std=gnu99 \
          -DENTROPY=0x1234567 -Ivinc -I$(VENV) -I$(RT)/isa/macros/scalar -T$(VENV)/link.ld -Wl,--no-warn-rwx-segments
visa: $(addprefix $(OUT)/isa/,$(addsuffix .hex,$(VISA)))
define VSUITE_RULE
$(OUT)/isa/$(1)-v-%.elf: $(RT)/isa/$(1)/%.S
	@mkdir -p $$(@D)
	$(P)gcc $(VFLAGS) -o $$@ $(VENV)/entry.S $(VENV)/vm.c $(VENV)/string.c $$<
endef
$(foreach s,$(VSUITES),$(eval $(call VSUITE_RULE,$(s))))

all: isa bench
bench: $(OUT)/dhrystone.hex $(OUT)/coremark.hex

$(OUT)/dhrystone.elf: $(wildcard ../dhrystone/*.c) $(COMMON)
	@mkdir -p $(@D)
	$(P)gcc $(BM_FLAGS) $(DH_FLAGS) -o $@ $(COMMON) ../dhrystone/dhry_1.c ../dhrystone/dhry_2.c ../dhrystone/stdlib.c

$(OUT)/coremark.elf: $(wildcard ../coremark/*.c) $(COMMON)
	@mkdir -p $(@D)
	$(P)gcc $(BM_FLAGS) $(CM_FLAGS) -I../coremark -DTOTAL_DATA_SIZE=2000 -DPERFORMANCE_RUN=1 -DITERATIONS=$(CM_ITER) \
	  -DFLAGS_STR='"$(CM_FLAGS)"' -o $@ $(COMMON) $(wildcard ../coremark/*.c)

isa: $(addprefix $(OUT)/isa/,$(addsuffix .hex,$(ISA)))

define SUITE_RULE
$(OUT)/isa/$(1)-%.elf: $(RT)/isa/$(1)/%.S
	@mkdir -p $$(@D)
	$(P)gcc $(ISA_FLAGS) -o $$@ $$<
endef
$(foreach s,$(SUITES),$(eval $(call SUITE_RULE,$(s))))

%.hex: %.elf
	$(P)objcopy -O binary $< $*.bin
	python3 ../common/bin2hex.py $*.bin $@ 8
	$(P)objdump -d -M no-aliases $< > $*.dis
	$(P)nm $< | awk '$$3=="tohost"{print $$1}' > $*.tohost

.PRECIOUS: %.elf $(OUT)/isa/%.elf
.SECONDARY:
