// CoreMark port for the shared testbench platform: time is the testbench cycle counter.
#include "coremark.h"
#include "plat.h"

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

static CORE_TICKS start_cycles, stop_cycles, start_insns, stop_insns;

void start_time(void) {
  start_insns = plat_insns();
  start_cycles = plat_cycles();
}
void stop_time(void) {
  stop_cycles = plat_cycles();
  stop_insns = plat_insns();
}
CORE_TICKS get_time(void) { return stop_cycles - start_cycles; }
// One "second" is 1,000,000 cycles, i.e. the reported rate is per MHz.
secs_ret time_in_secs(CORE_TICKS ticks) { return ticks / 1000000; }

ee_u32 default_num_contexts = 1;

void portable_init(core_portable *p, int *argc, char *argv[]) { p->portable_id = 1; }

void portable_fini(core_portable *p) {
  CORE_TICKS cyc = get_time(), ins = stop_insns - start_insns;
  // CoreMark/MHz = iterations * 1e6 / cycles, printed with three decimals
  unsigned long long x1000 = 1000000000ULL * ITERATIONS / cyc;
  ee_printf("RESULT cycles=%u insns=%u iterations=%u\n", cyc, ins, ITERATIONS);
  ee_printf("RESULT coremark_per_mhz=%u.%03u\n", (unsigned)(x1000 / 1000), (unsigned)(x1000 % 1000));
  p->portable_id = 0;
}
