// Minimal libc pieces the compiler may call implicitly.
#include <stddef.h>
__attribute__((weak)) void *memcpy(void *d, const void *s, size_t n) { char *a = d; const char *b = s; while (n--) *a++ = *b++; return d; }
void *memset(void *d, int c, size_t n) { char *a = d; while (n--) *a++ = c; return d; }
void *memmove(void *d, const void *s, size_t n) {
  char *a = d; const char *b = s;
  if (a < b) while (n--) *a++ = *b++; else while (n--) a[n] = b[n];
  return d;
}
size_t strlen(const char *s) { size_t n = 0; while (s[n]) n++; return n; }
