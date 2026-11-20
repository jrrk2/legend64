// SPDX-License-Identifier: Apache-2.0
// Minimal <ctype.h> for the riscv-tests "v" environment.
static inline int isspace(int c) { return c == 32 || (c >= 9 && c <= 13); }
static inline int isdigit(int c) { return c >= 48 && c <= 57; }
