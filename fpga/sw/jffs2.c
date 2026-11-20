// SPDX-License-Identifier: Apache-2.0
// A read-only JFFS2 reader for the boot monitor: find a file in the root directory of a
// filesystem image held in memory and unpack it. Little-endian images; data nodes that are
// stored, zero, rtime or zlib (the kernel is configured for zlib only; mkfs.jffs2 also uses
// rtime unless told not to). No allocation: the caller lends a work area for the node list.
//
// It stands alone so that it can be tested on the host against mkfs.jffs2
// (scripts/test_jffs2.sh).
#include <stdint.h>
#include <stddef.h>
#include "jffs2.h"

static uint16_t le16(const uint8_t *p) { return p[0] | p[1] << 8; }
static uint32_t le32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }

// JFFS2's checksum: the reflected CRC-32 with no inversion at either end
static uint32_t crc32_raw(const uint8_t *p, uint32_t n) {
  static uint32_t table[256];
  if (!table[1])
    for (uint32_t i = 0; i < 256; i++) {
      uint32_t c = i;
      for (int k = 0; k < 8; k++) c = c & 1 ? 0xedb88320u ^ (c >> 1) : c >> 1;
      table[i] = c;
    }
  uint32_t c = 0;
  while (n--) c = table[(c ^ *p++) & 0xff] ^ (c >> 8);
  return c;
}

// ---------------------------------------------------------------- inflate (RFC 1951)
struct inflate {
  const uint8_t *in; uint32_t inlen, inpos;
  uint8_t *out; uint32_t outlen, outpos;
  uint32_t bitbuf; int bitcnt;
  int err;
};
struct huff { uint16_t count[16], symbol[288]; };

static uint32_t bits(struct inflate *s, int need) {
  uint32_t v = s->bitbuf;
  while (s->bitcnt < need) {
    if (s->inpos == s->inlen) { s->err = 1; return 0; }
    v |= (uint32_t)s->in[s->inpos++] << s->bitcnt;
    s->bitcnt += 8;
  }
  s->bitbuf = need == 32 ? 0 : v >> need;
  s->bitcnt -= need;
  return need == 32 ? v : v & ((1u << need) - 1);
}

static int decode(struct inflate *s, const struct huff *h) {
  int code = 0, first = 0, index = 0;
  for (int len = 1; len <= 15; len++) {
    code |= bits(s, 1);
    if (s->err) return -1;
    int count = h->count[len];
    if (code - count < first) return h->symbol[index + (code - first)];
    index += count; first += count;
    first <<= 1; code <<= 1;
  }
  s->err = 1;
  return -1;
}

// build the decoding tables for n code lengths; 0 for a complete code
static int construct(struct huff *h, const uint8_t *length, int n) {
  uint16_t offs[16];
  for (int len = 0; len <= 15; len++) h->count[len] = 0;
  for (int i = 0; i < n; i++) h->count[length[i]]++;
  if (h->count[0] == n) return 0;
  int left = 1;
  for (int len = 1; len <= 15; len++) {
    left <<= 1;
    left -= h->count[len];
    if (left < 0) return left;
  }
  offs[1] = 0;
  for (int len = 1; len < 15; len++) offs[len + 1] = offs[len] + h->count[len];
  for (int i = 0; i < n; i++) if (length[i]) h->symbol[offs[length[i]]++] = i;
  return left;
}

static void codes(struct inflate *s, const struct huff *lencode, const struct huff *distcode) {
  static const uint16_t lens[29] = {3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258};
  static const uint8_t lext[29] = {0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0};
  static const uint16_t dists[30] = {1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577};
  static const uint8_t dext[30] = {0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13};
  for (;;) {
    int sym = decode(s, lencode);
    if (s->err) return;
    if (sym < 256) {
      if (s->outpos == s->outlen) { s->err = 1; return; }
      s->out[s->outpos++] = sym;
    } else if (sym == 256) {
      return;
    } else {
      sym -= 257;
      if (sym >= 29) { s->err = 1; return; }
      uint32_t len = lens[sym] + bits(s, lext[sym]);
      sym = decode(s, distcode);
      if (s->err || sym >= 30) { s->err = 1; return; }
      uint32_t dist = dists[sym] + bits(s, dext[sym]);
      if (s->err || dist > s->outpos || len > s->outlen - s->outpos) { s->err = 1; return; }
      for (; len; len--, s->outpos++) s->out[s->outpos] = s->out[s->outpos - dist];
    }
  }
}

// raw deflate data; 0 if the whole stream decoded without error
static int inflate_raw(const uint8_t *in, uint32_t inlen, uint8_t *out, uint32_t outlen, uint32_t *got) {
  static struct huff lencode, distcode;
  static uint8_t lengths[320];
  static const uint8_t order[19] = {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15};
  struct inflate s = {in, inlen, 0, out, outlen, 0, 0, 0, 0};
  int last;
  do {
    last = bits(&s, 1);
    int type = bits(&s, 2);
    if (s.err) break;
    if (type == 0) {                                        // stored
      s.bitbuf = 0; s.bitcnt = 0;
      if (s.inpos + 4 > s.inlen) { s.err = 1; break; }
      uint32_t len = le16(s.in + s.inpos);
      if (len != (uint16_t)~le16(s.in + s.inpos + 2)) { s.err = 1; break; }
      s.inpos += 4;
      if (len > s.inlen - s.inpos || len > s.outlen - s.outpos) { s.err = 1; break; }
      for (; len; len--) s.out[s.outpos++] = s.in[s.inpos++];
    } else if (type == 1) {                                 // fixed codes
      int i = 0;
      for (; i < 144; i++) lengths[i] = 8;
      for (; i < 256; i++) lengths[i] = 9;
      for (; i < 280; i++) lengths[i] = 7;
      for (; i < 288; i++) lengths[i] = 8;
      construct(&lencode, lengths, 288);
      for (i = 0; i < 30; i++) lengths[i] = 5;
      construct(&distcode, lengths, 30);
      codes(&s, &lencode, &distcode);
    } else if (type == 2) {                                 // dynamic codes
      int nlen = bits(&s, 5) + 257, ndist = bits(&s, 5) + 1, ncode = bits(&s, 4) + 4, i;
      if (s.err || nlen > 286 || ndist > 30) { s.err = 1; break; }
      for (i = 0; i < ncode; i++) lengths[order[i]] = bits(&s, 3);
      for (; i < 19; i++) lengths[order[i]] = 0;
      if (construct(&lencode, lengths, 19) != 0) { s.err = 1; break; }
      for (i = 0; i < nlen + ndist && !s.err; ) {
        int sym = decode(&s, &lencode);
        if (s.err) break;
        if (sym < 16) lengths[i++] = sym;
        else {
          int len = 0, rep;
          if (sym == 16) {
            if (i == 0) { s.err = 1; break; }
            len = lengths[i - 1]; rep = 3 + bits(&s, 2);
          } else if (sym == 17) rep = 3 + bits(&s, 3);
          else rep = 11 + bits(&s, 7);
          if (i + rep > nlen + ndist) { s.err = 1; break; }
          while (rep--) lengths[i++] = len;
        }
      }
      if (s.err || lengths[256] == 0) { s.err = 1; break; }
      int e = construct(&lencode, lengths, nlen);
      if (e < 0 || (e > 0 && nlen - lencode.count[0] != 1)) { s.err = 1; break; }
      e = construct(&distcode, lengths + nlen, ndist);
      if (e < 0 || (e > 0 && ndist - distcode.count[0] != 1)) { s.err = 1; break; }
      codes(&s, &lencode, &distcode);
    } else s.err = 1;
  } while (!last && !s.err);
  *got = s.outpos;
  return s.err;
}

// ---------------------------------------------------------------- the filesystem
enum { MAGIC = 0x1985, N_DIRENT = 0xe001, N_INODE = 0xe002 };
enum { C_NONE = 0, C_ZERO = 1, C_RTIME = 2, C_ZLIB = 6 };

// the next dirent or inode node at or after *pos whose header and node checksums hold;
// returns its offset and moves *pos past it, or returns -1 at the end
static long next_node(const uint8_t *img, uint32_t size, uint32_t *pos) {
  uint32_t p = *pos;
  while (p + 12 <= size) {
    if (le16(img + p) != MAGIC) { p += 4; continue; }
    uint32_t totlen = le32(img + p + 4);
    uint16_t type = le16(img + p + 2);
    if (totlen < 12 || totlen > size - p || crc32_raw(img + p, 8) != le32(img + p + 8)) { p += 4; continue; }
    uint32_t at = p;
    p += (totlen + 3) & ~3u;
    if (type == N_DIRENT && totlen >= 40 && crc32_raw(img + at, 32) == le32(img + at + 32) &&
        40u + img[at + 28] <= totlen && crc32_raw(img + at + 40, img[at + 28]) == le32(img + at + 36)) {
      *pos = p; return at;
    }
    if (type == N_INODE && totlen >= 68 && crc32_raw(img + at, 60) == le32(img + at + 64) &&
        68 + le32(img + at + 48) <= totlen) {
      *pos = p; return at;
    }
  }
  *pos = size;
  return -1;
}

uint32_t jffs2_find(const uint8_t *img, uint32_t size, const char *name) {
  uint32_t n = 0, pos = 0, best = 0, ino = 0;
  long at;
  while (name[n]) n++;
  while ((at = next_node(img, size, &pos)) >= 0) {
    const uint8_t *d = img + at;
    if (le16(d + 2) != N_DIRENT || le32(d + 12) != 1 || d[28] != n) continue;   // root directory is inode 1
    if (d[29] != 8 && le32(d + 20) != 0) continue;                              // a regular file, or a deletion
    uint32_t i = 0;
    while (i < n && d[40 + i] == (uint8_t)name[i]) i++;
    if (i == n && le32(d + 16) >= best) { best = le32(d + 16); ino = le32(d + 20); }   // inode 0: deleted
  }
  return ino;
}

static int rtime(const uint8_t *in, uint32_t inlen, uint8_t *out, uint32_t outlen) {
  uint16_t positions[256] = {0};
  uint32_t o = 0, p = 0;
  while (o < outlen) {
    if (p + 2 > inlen) return 1;
    uint8_t value = in[p++];
    out[o++] = value;
    uint32_t repeat = in[p++], back = positions[value];
    positions[value] = o;
    if (repeat > outlen - o) return 1;
    for (; repeat; repeat--) out[o++] = out[back++];
  }
  return 0;
}

long jffs2_read(const uint8_t *img, uint32_t size, uint32_t ino, uint8_t *dst, uint32_t max,
                uint32_t *work, uint32_t work_n) {
  uint32_t n = 0, pos = 0;
  long at;
  // the file's nodes, in order of version: a later node replaces what earlier ones put there
  while ((at = next_node(img, size, &pos)) >= 0) {
    const uint8_t *d = img + at;
    if (le16(d + 2) != N_INODE || le32(d + 12) != ino) continue;
    if (crc32_raw(d + 68, le32(d + 48)) != le32(d + 60)) continue;         // data not all written
    if (n == work_n) return -1;
    uint32_t v = le32(d + 16), i = n++;
    for (; i > 0 && le32(img + work[i - 1] + 16) > v; i--) work[i] = work[i - 1];
    work[i] = at;
  }
  if (!n) return -1;
  uint32_t len = 0;
  for (uint32_t k = 0; k < n; k++) {
    const uint8_t *d = img + work[k];
    uint32_t isize = le32(d + 28), off = le32(d + 44), csize = le32(d + 48), dsize = le32(d + 52), got = dsize;
    if (isize > max || off > max || dsize > max - off) return -1;
    for (uint32_t i = isize; i < len; i++) dst[i] = 0;                      // truncated
    for (uint32_t i = len; i < off; i++) dst[i] = 0;                        // a hole
    len = isize;
    const uint8_t *src = d + 68;
    uint8_t *o = dst + off;
    switch (d[56]) {
      case C_NONE: if (csize != dsize) return -1; for (uint32_t i = 0; i < dsize; i++) o[i] = src[i]; break;
      case C_ZERO: for (uint32_t i = 0; i < dsize; i++) o[i] = 0; break;
      case C_RTIME: if (rtime(src, csize, o, dsize)) return -1; break;
      case C_ZLIB:
        // as the kernel does: a two-byte zlib header, if there is one, is stepped over
        if (csize >= 2 && (src[0] & 0x0f) == 8 && !((src[0] << 8 | src[1]) % 31) && !(src[1] & 0x20)) { src += 2; csize -= 2; }
        if (inflate_raw(src, csize, o, dsize, &got) || got != dsize) return -1;
        break;
      default: return -1;
    }
  }
  return len;
}
