// SPDX-License-Identifier: Apache-2.0
// Read-only JFFS2 reader (jffs2.c). The image is the whole filesystem in memory.
#include <stdint.h>
// the inode number of the regular file `name` in the root directory, or 0 if there is none
uint32_t jffs2_find(const uint8_t *img, uint32_t size, const char *name);
// unpack the file to dst (at most max bytes); returns its length, or -1. work lends room for
// one entry per data node of the file (a node holds at most a page: 4 KiB).
long jffs2_read(const uint8_t *img, uint32_t size, uint32_t ino, uint8_t *dst, uint32_t max,
                uint32_t *work, uint32_t work_n);
