// What LiteX's liblitedram (sdram.c, accessors.c) needs from its surroundings, provided by the
// legend64 boot monitor: formatted output, the post-levelling memory test, and delays.
#include <stdint.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>

void mon_putch(int c);

int putchar(int c) { mon_putch(c); return c; }
int puts(const char *s) { while (*s) mon_putch(*s++); mon_putch('\n'); return 0; }

static void out_num(unsigned long v, unsigned base, int width, char pad, int neg) {
  char b[24]; int n = 0;
  do { b[n++] = "0123456789abcdef"[v % base]; v /= base; } while (v);
  if (neg && pad == '0') { mon_putch('-'); width--; }
  else if (neg) b[n++] = '-';
  while (width-- > n) mon_putch(pad);
  while (n) mon_putch(b[--n]);
}

// Supports %d %i %u %x %X %c %s %p %%, the flags '0' and '-' (ignored), a width, and l/ll/z.
int printf(const char *f, ...) {
  va_list ap;
  va_start(ap, f);
  for (; *f; f++) {
    if (*f != '%') { mon_putch(*f); continue; }
    char pad = ' '; int width = 0, lng = 0;
    f++;
    while (*f == '0' || *f == '-') { if (*f == '0') pad = '0'; f++; }
    while (*f >= '0' && *f <= '9') width = width * 10 + (*f++ - '0');
    while (*f == 'l' || *f == 'z') { lng = 1; f++; }
    switch (*f) {
      case 'd': case 'i': {
        long v = lng ? va_arg(ap, long) : va_arg(ap, int);
        out_num(v < 0 ? -(unsigned long)v : (unsigned long)v, 10, width, pad, v < 0);
        break;
      }
      case 'u': out_num(lng ? va_arg(ap, unsigned long) : va_arg(ap, unsigned), 10, width, pad, 0); break;
      case 'x': case 'X': out_num(lng ? va_arg(ap, unsigned long) : va_arg(ap, unsigned), 16, width, pad, 0); break;
      case 'p': out_num(va_arg(ap, unsigned long), 16, 16, '0', 0); break;
      case 'c': mon_putch(va_arg(ap, int)); break;
      case 's': {
        const char *s = va_arg(ap, const char *);
        int n = 0;
        while (s[n]) mon_putch(s[n++]);
        while (width-- > n) mon_putch(' ');
        break;
      }
      case '%': mon_putch('%'); break;
      default: if (!*f) { va_end(ap); return 0; }
    }
  }
  va_end(ap);
  return 0;
}

// The test liblitedram runs after levelling, before it reports the memory as ready: a
// pseudo-random pattern over `maxsize` bytes (2 MiB, many times the cache), then an address
// pattern at power-of-two offsets across the whole memory. Returns 1 when everything matches.
static uint32_t lfsr(uint32_t x) { x ^= x << 13; x ^= x >> 17; x ^= x << 5; return x; }

int memtest(unsigned int *addr, unsigned long maxsize) {
  volatile uint32_t *p = (volatile uint32_t *)addr;
  unsigned long n = maxsize / 4, errors = 0;
  uint32_t x = 0x1234abcd;
  for (unsigned long i = 0; i < n; i++) { x = lfsr(x); p[i] = x; }
  x = 0x1234abcd;
  for (unsigned long i = 0; i < n; i++) {
    x = lfsr(x);
    uint32_t got = p[i];
    if (got != x) {
      if (errors < 8) printf("  memtest: [0x%08lx] = 0x%08x, expected 0x%08x\n", (unsigned long)&p[i], got, x);
      errors++;
    }
  }
  volatile uint64_t *q = (volatile uint64_t *)addr;
  for (unsigned long off = 8; off < MAIN_RAM_SIZE; off <<= 1) q[off / 8] = ~off;
  q[0] = 0x5a5a5a5aa5a5a5a5UL;
  for (unsigned long off = 8; off < MAIN_RAM_SIZE; off <<= 1)
    if (q[off / 8] != ~off) {
      if (errors < 8) printf("  memtest: address line test failed at offset 0x%08lx\n", off);
      errors++;
    }
  printf("Memtest of %lu KiB and the address lines: %lu error%s\n", maxsize / 1024, errors, errors == 1 ? "" : "s");
  return errors == 0;
}

void memspeed(unsigned int *addr, unsigned long size, bool read_only, bool random) {
  (void)addr; (void)size; (void)read_only; (void)random;   // the monitor has its own timing
}
