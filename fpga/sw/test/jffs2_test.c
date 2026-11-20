// SPDX-License-Identifier: Apache-2.0
// Host test of jffs2.c: jffs2_test <image> <directory> <file>...  reads each file out of the
// image and compares it with the one in the directory. A name that begins with '!' must be absent.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../jffs2.h"

static uint8_t *slurp(const char *path, long *n) {
  FILE *f = fopen(path, "rb");
  if (!f) { perror(path); exit(2); }
  fseek(f, 0, SEEK_END); *n = ftell(f); rewind(f);
  uint8_t *p = malloc(*n + 1);
  if (fread(p, 1, *n, f) != (size_t)*n) exit(2);
  fclose(f);
  return p;
}

int main(int argc, char **argv) {
  long isize, fsize;
  uint8_t *img = slurp(argv[1], &isize);
  static uint32_t work[1 << 16];
  uint8_t *out = malloc(64 << 20);
  int bad = 0;
  for (int i = 3; i < argc; i++) {
    if (argv[i][0] == '!') {
      if (jffs2_find(img, isize, argv[i] + 1)) { printf("%s: found, should be absent\n", argv[i] + 1); bad = 1; }
      continue;
    }
    char path[4096];
    snprintf(path, sizeof path, "%s/%s", argv[2], argv[i]);
    uint8_t *want = slurp(path, &fsize);
    uint32_t ino = jffs2_find(img, isize, argv[i]);
    long got = ino ? jffs2_read(img, isize, ino, out, 64 << 20, work, 1 << 16) : -2;
    int ok = got == fsize && !memcmp(out, want, fsize);
    printf("%-24s inode %u, %ld bytes: %s\n", argv[i], ino, got, ok ? "ok" : "WRONG");
    bad |= !ok;
    free(want);
  }
  free(out); free(img);
  puts(bad ? "FAIL" : "PASS");
  return bad;
}
