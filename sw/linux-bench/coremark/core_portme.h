// SPDX-License-Identifier: Apache-2.0
// CoreMark port for Linux user space (64-bit): time from CLOCK_MONOTONIC, output through printf.
#ifndef CORE_PORTME_H
#define CORE_PORTME_H
#include <stddef.h>
#include <stdio.h>
#define HAS_FLOAT 1
#define HAS_TIME_H 1
#define USE_CLOCK 0
#define HAS_STDIO 1
#define HAS_PRINTF 1
#define COMPILER_VERSION "GCC" __VERSION__
#ifndef COMPILER_FLAGS
#define COMPILER_FLAGS FLAGS_STR
#endif
#define MEM_LOCATION "STACK"
typedef signed short ee_s16;
typedef unsigned short ee_u16;
typedef signed int ee_s32;
typedef double ee_f32;
typedef unsigned char ee_u8;
typedef unsigned int ee_u32;
typedef unsigned long ee_ptr_int;
typedef size_t ee_size_t;
#define align_mem(x) (void *)(4 + (((ee_ptr_int)(x)-1) & ~3))
#define CORETIMETYPE unsigned long long
typedef unsigned long long CORE_TICKS;      // nanoseconds
#define SEED_METHOD SEED_VOLATILE
#define MEM_METHOD MEM_STACK
#define MULTITHREAD 1
#define USE_PTHREAD 0
#define USE_FORK 0
#define USE_SOCKET 0
#define MAIN_HAS_NOARGC 0
#define MAIN_HAS_NORETURN 0
extern ee_u32 default_num_contexts;
typedef struct CORE_PORTABLE_S { ee_u8 portable_id; } core_portable;
void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);
#define ee_printf printf
#if !defined(PROFILE_RUN) && !defined(PERFORMANCE_RUN) && !defined(VALIDATION_RUN)
#define PERFORMANCE_RUN 1
#endif
#endif
