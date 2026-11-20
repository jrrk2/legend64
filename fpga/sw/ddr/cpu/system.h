// CPU hooks LiteX software expects. fable64's cache needs no maintenance: the memory tests
// used here are larger than the cache or go through the controller's command registers.
#pragma once
static inline void flush_cpu_icache(void) {}
static inline void flush_cpu_dcache(void) {}
static inline void flush_l2_cache(void) {}
void busy_wait(unsigned int ms);
void busy_wait_us(unsigned int us);
