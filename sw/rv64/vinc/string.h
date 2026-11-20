// SPDX-License-Identifier: Apache-2.0
// Minimal <string.h> for building the riscv-tests "v" environment without a C library.
#ifndef LEGEND_STRING_H
#define LEGEND_STRING_H
#include <stddef.h>
void *memcpy(void *, const void *, size_t);
void *memset(void *, int, size_t);
size_t strlen(const char *);
size_t strnlen(const char *, size_t);
int strcmp(const char *, const char *);
char *strcpy(char *, const char *);
long atol(const char *);
int memcmp(const void *, const void *, size_t);
#endif
