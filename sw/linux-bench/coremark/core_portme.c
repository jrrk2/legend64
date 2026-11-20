// SPDX-License-Identifier: Apache-2.0
// CoreMark port for Linux user space: see core_portme.h.
#include <time.h>
#include "coremark.h"

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415, seed2_volatile = 0x3415, seed3_volatile = 0x66;
#elif PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0, seed2_volatile = 0x0, seed3_volatile = 0x66;
#else
volatile ee_s32 seed1_volatile = 0x8, seed2_volatile = 0x8, seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;   // 0: core_main chooses, for a run of at least 10 s
volatile ee_s32 seed5_volatile = 0;
ee_u32 default_num_contexts = 1;

static CORE_TICKS now(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (CORE_TICKS)t.tv_sec * 1000000000ull + (CORE_TICKS)t.tv_nsec;
}
static CORE_TICKS t_start, t_stop;
void start_time(void) { t_start = now(); }
void stop_time(void) { t_stop = now(); }
CORE_TICKS get_time(void) { return t_stop - t_start; }
secs_ret time_in_secs(CORE_TICKS ticks) { return (secs_ret)ticks / 1e9; }

void portable_init(core_portable *p, int *argc, char *argv[]) {
  (void)argc; (void)argv;
  p->portable_id = 1;
}
void portable_fini(core_portable *p) { p->portable_id = 0; }
