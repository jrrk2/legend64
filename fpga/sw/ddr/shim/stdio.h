// Minimal <stdio.h> for building LiteX's liblitedram into the legend64 boot monitor.
#pragma once
#include <stddef.h>
#include <stdarg.h>
int printf(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
int putchar(int c);
int puts(const char *s);
