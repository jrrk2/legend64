// SPDX-License-Identifier: Apache-2.0
// Boot monitor for legend64 on the VC707. Runs in machine mode from block RAM.
//
// It checks the DDR3 memory and the FPU, brings up the Ethernet MAC, answers ARP and ping, and
// loads images into memory over UDP so that firmware, kernel and device tree arrive in seconds
// (see fpga/scripts/netload.py for the host side). Images can also be sent over the serial line.
//
// After the self-test it boots by itself: it fetches firmware, kernel and device tree from a TFTP
// server (TFTP_SERVER, files under legend64/) and starts the firmware. Any key during the three
// second countdown, or while it loads, stops that and gives the prompt; so does a failed fetch.
//
// Serial commands (115200 8N1):
//   i  status            m  memory test            f  floating-point check
//   b  boot from the TFTP server now
//   F  identify the configuration flash
//   U  fetch legend64/flash.img from the TFTP server and write it to the flash
//   R  reload the FPGA from its flash
//   d  initialise and level the DDR3 again (LiteDRAM builds)
//   L  load: 4-byte little-endian length, the image, 1-byte sum; stored at 0x8000_0000
//   g  jump to 0x8000_0000 (a0 = 0, a1 = 0)
//
// UDP loader, port 6464. Request and reply share a 24-byte header, little-endian:
//   u32 magic 'FBL1'   u8 command, 3 bytes zero   u32 sequence   u64 address   u32 length
//   command 1  write `length` bytes that follow to `address`
//   command 2  jump to `address`; the 8 bytes that follow are passed in a1 (a0 = 0)
//   command 3  no operation (probe)
//   command 4  read `length` bytes (at most 1400) at `address`; they follow the reply's header
//   command 5  write the `length` bytes at `address` (an image already loaded into memory, laid
//              out as the flash is seen at 0x6000_0000) to the flash; two u64 follow: the
//              offset in the flash, and flags (1: reload the FPGA afterwards, 2: do not insist
//              that an image for offset 0 looks like a bitstream). Acknowledged at once.
//   command 6  flash job status: four u32 follow the reply's header: state (0 none, 1 running,
//              2 done, 3 failed), blocks done, blocks in all, blocks that had to be written
// The reply is the same header with bit 7 set in the command. Any command but a probe also
// cancels the countdown to the network boot.
#include <stdint.h>
#include <stddef.h>

#define REG8(a)  (*(volatile uint8_t *)(a))
#define REG32(a) (*(volatile uint32_t *)(a))
#define REG64(a) (*(volatile uint64_t *)(a))
#define UART_THR   REG8(0x10000000)
#define UART_LSR   REG8(0x10000005)
#define LEDS       REG32(0x20000000)
#define STATUS     REG32(0x20000008)
#define CLOCK_BUILT REG32(0x2000000c)   // the clock the bitstream was built for
#define CLOCK_MEAS  REG32(0x20000014)   // the clock as the hardware measures it; 0 until it has
#define CLOCK_HZ    clock_hz()
// The core clock in hertz. The hardware times it against the board's reference, so a bitstream
// reclocked after it was built still gives the right answer; until the first measurement is in
// (a quarter of a second after reset) it is what the bitstream was built for.
static inline uint32_t clock_hz(void) { uint32_t m = CLOCK_MEAS; return m ? m : CLOCK_BUILT; }
#define BUILD_ID   REG32(0x20000010)
#define RECONFIG   REG32(0x20000018)
#define FLASH_BASE 0x60000000UL
#define FLASH_SIZE 0x02000000UL
#define FL16(off)  (*(volatile uint16_t *)(FLASH_BASE + (off)))
#define FL64(off)  (*(volatile uint64_t *)(FLASH_BASE + (off)))
#define UPDATE_ADDR 0x90000000UL  // where an image for the flash is fetched to
#define MTIME      REG64(0x0200bff8)
#define ETH(r)     REG32(0x30000000 + (r))
enum { E_CTRL = 0x00, E_STATUS = 0x04, E_IRQ = 0x08, E_MAC_LO = 0x10, E_MAC_HI = 0x14,
       E_RX_BASE = 0x20, E_RX_SIZE = 0x28, E_RX_HEAD = 0x2c, E_RX_TAIL = 0x30,
       E_TX_BASE = 0x40, E_TX_SIZE = 0x48, E_TX_HEAD = 0x4c, E_TX_TAIL = 0x50, E_DROPPED = 0x60 };
#define ST_DDR_READY (1u << 16)
#define ST_DDR_SOFT  (1u << 17)   // LiteDRAM: the memory is initialised and levelled by sdram_init()
int sdram_init(void);             // LiteX's liblitedram, built from the LiteX sources (see Makefile)
#define DDR_BASE   0x80000000UL
#define DDR_SIZE   0x40000000UL

// The monitor's packet memory sits at the top of RAM, clear of anything it loads.
#define NET_BASE   0xbfe00000UL
#define RX_N       8
#define TX_N       4
struct desc { uint64_t addr; uint32_t len; uint32_t flags; };
#define RX_RING    ((volatile struct desc *)(NET_BASE))
#define TX_RING    ((volatile struct desc *)(NET_BASE + 0x100))
#define RX_BUF(i)  (NET_BASE + 0x10000 + 2048UL * (i))
#define TX_BUF     ((uint8_t *)(NET_BASE + 0x8000 + 2))

static const uint8_t my_mac[6] = {0x02, 0x00, 0x00, 0xfa, 0xb1, 0xe5};
static const uint8_t my_ip[4] = {192, 168, 1, 51};
#ifndef TFTP_SERVER
#define TFTP_SERVER 192, 168, 1, 176
#endif
#ifndef TFTP_PORT
#define TFTP_PORT 69
#endif
static const uint8_t srv_ip[4] = {TFTP_SERVER};
static uint8_t srv_mac[6];
static int srv_known;
// what a TFTP boot loads; the first is entered with a1 = the address of the last
static const struct { const char *name; uint64_t addr; } boot_files[] = {
  {"legend64/fw_jump.bin",        0x80000000UL},
  {"legend64/Image",              0x80200000UL},
  {"legend64/legend64-vc707.dtb", 0x86000000UL},
};
static uint32_t n_arp, n_ping, n_rx, n_tx, n_load, rx_next, rx_tail, tx_next;

static void putch(int c) {
  if (c == '\n') putch('\r');
  while (!(UART_LSR & 0x20)) ;
  UART_THR = c;
}
void mon_putch(int c) { putch(c); }          // for the DDR3 initialisation code (ddr/glue.c)
static void puts_(const char *s) { while (*s) putch(*s++); }
static int getch_nb(void) { return (UART_LSR & 1) ? UART_THR : -1; }
static int getch(void) { int c; while ((c = getch_nb()) < 0) ; return c; }
static void puthex(uint64_t v, int digits) { for (int i = digits - 1; i >= 0; i--) putch("0123456789abcdef"[(v >> (4 * i)) & 15]); }
static void putdec(uint64_t v) {
  char b[24]; int n = 0;
  do { b[n++] = '0' + v % 10; v /= 10; } while (v);
  while (n) putch(b[--n]);
}

void trap_report(uint64_t cause, uint64_t epc, uint64_t tval) {
  puts_("\n*** trap: mcause="); puthex(cause, 16); puts_(" mepc="); puthex(epc, 16);
  puts_(" mtval="); puthex(tval, 16); puts_("\n");
}

// ---------------------------------------------------------------- memory test
static uint64_t mix(uint64_t x) { x ^= x >> 33; x *= 0xff51afd7ed558ccdULL; x ^= x >> 33; x *= 0xc4ceb9fe1a85ec53ULL; return x ^ (x >> 33); }

static int memtest(void) {
  volatile uint64_t *m = (volatile uint64_t *)DDR_BASE;
  uint64_t bad = 0, t0 = MTIME;
  // dense: the first 4 MiB, far more than the 64 KiB cache, so every line goes out to DDR and back
  const uint64_t dense = (4u << 20) / 8;
  for (uint64_t i = 0; i < dense; i++) m[i] = mix(i);
  for (uint64_t i = 0; i < dense; i++) if (m[i] != mix(i)) { if (!bad++) { puts_("  first mismatch at "); puthex(DDR_BASE + 8 * i, 10); putch('\n'); } }
  puts_("  dense 4 MiB: "); putdec(bad); puts_(" errors\n");
  // sparse: one word every 4 KiB across the whole gigabyte, catches address aliasing
  uint64_t bad2 = 0;
  // (not the pages the Ethernet rings and buffers are in: the MAC is already receiving into them)
#define NET_PAGE(a) ((a) >= NET_BASE - DDR_BASE && (a) < NET_BASE - DDR_BASE + 0x20000)
  for (uint64_t a = 0; a < DDR_SIZE; a += 4096) if (!NET_PAGE(a)) m[(a + (mix(a) & 0xff8)) / 8] = mix(a ^ 0x5555);
  for (uint64_t a = 0; a < DDR_SIZE; a += 4096) if (!NET_PAGE(a) && m[(a + (mix(a) & 0xff8)) / 8] != mix(a ^ 0x5555)) { if (!bad2++) { puts_("  first mismatch at "); puthex(DDR_BASE + a, 10); putch('\n'); } }
  puts_("  sparse 1 GiB, 262112 words: "); putdec(bad2); puts_(" errors\n");
  uint64_t bad3 = 0;
  volatile uint8_t *b = (volatile uint8_t *)(DDR_BASE + 0x100000);
  for (int i = 0; i < 4096; i++) b[i] = (uint8_t)(i * 7 + 3);
  for (int i = 0; i < 4096; i++) if (b[i] != (uint8_t)(i * 7 + 3)) bad3++;
  puts_("  byte access: "); putdec(bad3); puts_(" errors\n");
  puts_("  time: "); putdec((MTIME - t0) / (CLOCK_HZ / 1000)); puts_(" ms\n");
  return (bad | bad2 | bad3) != 0;
}

// ---------------------------------------------------------------- floating point
static int fpcheck(void) {
  volatile double a = 2.0, b = 3.0, c = 10.0;
  volatile float f = 0.1f;
  double s = __builtin_sqrt(a);
  double pi = 0, sign = 1;
  for (int k = 1; k < 2000; k++) { pi += sign * 4.0 / ((2.0 * k) * (2.0 * k + 1) * (2.0 * k + 2)); sign = -sign; }
  pi += b;
  uint64_t sb; uint32_t fb;
  __builtin_memcpy(&sb, &s, 8);
  float g = f * (float)c; __builtin_memcpy(&fb, &g, 4);
  int ok = sb == 0x3ff6a09e667f3bcdULL && fb == 0x3f800000u && (int64_t)(pi * 1e9) == 3141592653LL;
  puts_("  sqrt(2) = 0x"); puthex(sb, 16); puts_(", pi*1e9 = "); putdec((uint64_t)(pi * 1e9));
  puts_(ok ? "  OK\n" : "  WRONG\n");
  return !ok;
}

// ---------------------------------------------------------------- Ethernet
static uint16_t rd16(const uint8_t *p) { return (uint16_t)(p[0] << 8 | p[1]); }
static uint32_t rdle32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }
static uint64_t rdle64(const uint8_t *p) { return rdle32(p) | (uint64_t)rdle32(p + 4) << 32; }

static void eth_init(void) {
  ETH(E_CTRL) = 0x100;                       // stop, ring positions to zero
  for (int i = 0; i < RX_N; i++) { RX_RING[i].addr = RX_BUF(i); RX_RING[i].len = 0; RX_RING[i].flags = 0; }
  for (int i = 0; i < TX_N; i++) { TX_RING[i].addr = 0; TX_RING[i].len = 0; TX_RING[i].flags = 0; }
  ETH(E_MAC_LO) = my_mac[0] | my_mac[1] << 8 | my_mac[2] << 16 | (uint32_t)my_mac[3] << 24;
  ETH(E_MAC_HI) = my_mac[4] | my_mac[5] << 8;
  ETH(E_RX_BASE) = (uint32_t)(uintptr_t)RX_RING; ETH(E_RX_BASE + 4) = 0; ETH(E_RX_SIZE) = RX_N;
  ETH(E_TX_BASE) = (uint32_t)(uintptr_t)TX_RING; ETH(E_TX_BASE + 4) = 0; ETH(E_TX_SIZE) = TX_N;
  rx_next = 0; tx_next = 0; rx_tail = RX_N - 1;
  ETH(E_RX_TAIL) = rx_tail;
  ETH(E_CTRL) = 3;
}
static void eth_stop(void) { ETH(E_CTRL) = 0x100; }

// send the frame built in TX_BUF and wait until the hardware has taken it
static void eth_send(int len) {
  volatile struct desc *d = &TX_RING[tx_next];
  d->addr = (uintptr_t)TX_BUF; d->len = len; d->flags = 0;
  tx_next = (tx_next + 1) % TX_N;
  ETH(E_TX_TAIL) = tx_next;
  for (uint64_t t0 = MTIME; !(d->flags & 1) && MTIME - t0 < CLOCK_HZ / 10; ) ;
  n_tx++;
}

static void arp_send(int reply, const uint8_t *dst_mac, const uint8_t *dst_ip) {
  uint8_t *t = TX_BUF;
  for (int i = 0; i < 6; i++) { t[i] = reply ? dst_mac[i] : 0xff; t[6 + i] = my_mac[i]; }
  t[12] = 0x08; t[13] = 0x06; t[14] = 0; t[15] = 1; t[16] = 8; t[17] = 0; t[18] = 6; t[19] = 4; t[20] = 0; t[21] = reply ? 2 : 1;
  for (int i = 0; i < 6; i++) { t[22 + i] = my_mac[i]; t[32 + i] = reply ? dst_mac[i] : 0; }
  for (int i = 0; i < 4; i++) { t[28 + i] = my_ip[i]; t[38 + i] = dst_ip[i]; }
  eth_send(42);
}

static uint16_t ip_checksum(const uint8_t *p, int n) {
  uint32_t s = 0;
  for (int i = 0; i < n; i += 2) s += rd16(p + i);
  while (s >> 16) s = (s & 0xffff) + (s >> 16);
  return ~s;
}

static void (*boot_entry)(uint64_t, uint64_t);
static uint64_t boot_arg;
static int loader_seen;             // the UDP loader was given something to do
static struct {
  uint32_t state, done, total, written;     // as command 6 reports them
  int      pending;
  uint64_t src, off, flags;
  uint32_t len;
} fj;

static void udp_loader(const uint8_t *r, int len) {
  const uint8_t *h = r + 42;
  if (len < 42 + 24 || rdle32(h) != 0x314c4246) return;   // 'FBL1'
  uint8_t cmd = h[4];
  uint64_t addr = rdle64(h + 12);
  uint32_t n = rdle32(h + 20);
  int extra = 0;                    // payload bytes in the reply
  if (cmd == 1 && 42 + 24 + (int)n <= len) {
    uint8_t *dst = (uint8_t *)addr;
    const uint8_t *src = h + 24;
    for (uint32_t i = 0; i < n; i++) dst[i] = src[i];
    n_load += n;
  } else if (cmd == 2 && len >= 42 + 32) {
    boot_entry = (void (*)(uint64_t, uint64_t))addr;
    boot_arg = rdle64(h + 24);
  } else if (cmd == 4 && n <= 1400) {
    const volatile uint8_t *src = (const volatile uint8_t *)addr;
    for (uint32_t i = 0; i < n; i++) TX_BUF[42 + 24 + i] = src[i];
    extra = n;
  } else if (cmd == 5 && len >= 42 + 40) {
    if (fj.state != 1 && !fj.pending) {
      fj.src = addr; fj.len = n; fj.off = rdle64(h + 24); fj.flags = rdle64(h + 32);
      fj.state = 1; fj.done = fj.total = fj.written = 0; fj.pending = 1;
    }
  } else if (cmd == 6) {
    const uint32_t v[4] = {fj.state, fj.done, fj.total, fj.written};
    for (int i = 0; i < 16; i++) TX_BUF[42 + 24 + i] = v[i / 4] >> (8 * (i % 4));
    extra = 16;
  } else if (cmd != 3) return;
  if (cmd != 3 && cmd != 6) loader_seen = 1;
  // reply: swap addresses and ports, echo the header with bit 7 set in the command
  uint8_t *t = TX_BUF;
  for (int i = 0; i < 6; i++) { t[i] = r[6 + i]; t[6 + i] = my_mac[i]; }
  t[12] = 0x08; t[13] = 0x00;
  for (int i = 14; i < 34; i++) t[i] = r[i];
  t[16] = (20 + 8 + 24 + extra) >> 8; t[17] = 20 + 8 + 24 + extra;
  t[22] = 64; t[24] = 0; t[25] = 0;
  for (int i = 0; i < 4; i++) { t[26 + i] = my_ip[i]; t[30 + i] = r[26 + i]; }
  uint16_t ck = ip_checksum(t + 14, 20);
  t[24] = ck >> 8; t[25] = ck;
  t[34] = r[36]; t[35] = r[37]; t[36] = r[34]; t[37] = r[35];
  t[38] = (8 + 24 + extra) >> 8; t[39] = 8 + 24 + extra; t[40] = 0; t[41] = 0;   // UDP checksum not used
  for (int i = 0; i < 24; i++) t[42 + i] = h[i];
  t[42 + 4] = cmd | 0x80;
  eth_send(42 + 24 + extra);
}

// ---------------------------------------------------------------- TFTP client (RFC 1350, 2347, 2348)
// an IPv4/UDP frame to the server: the caller has put `n` bytes of payload at TX_BUF + 42
static void udp_send(uint16_t sport, uint16_t dport, int n) {
  uint8_t *t = TX_BUF;
  for (int i = 0; i < 6; i++) { t[i] = srv_mac[i]; t[6 + i] = my_mac[i]; }
  t[12] = 0x08; t[13] = 0x00;
  t[14] = 0x45; t[15] = 0; t[16] = (20 + 8 + n) >> 8; t[17] = 20 + 8 + n;
  t[18] = 0; t[19] = 0; t[20] = 0x40; t[21] = 0; t[22] = 64; t[23] = 17; t[24] = 0; t[25] = 0;
  for (int i = 0; i < 4; i++) { t[26 + i] = my_ip[i]; t[30 + i] = srv_ip[i]; }
  uint16_t ck = ip_checksum(t + 14, 20);
  t[24] = ck >> 8; t[25] = ck;
  t[34] = sport >> 8; t[35] = sport; t[36] = dport >> 8; t[37] = dport;
  t[38] = (8 + n) >> 8; t[39] = 8 + n; t[40] = 0; t[41] = 0;   // UDP checksum not used
  eth_send(42 + n);
}

enum { TFTP_BLKSIZE = 1400 };
static struct {
  int      active, done, failed;
  uint16_t my_port, srv_port;       // the server answers from a port of its own choosing
  uint16_t next;                    // the data block expected
  uint32_t blksize;
  uint8_t  *dst;
  uint32_t got;
  int      progress;                // something arrived since the last look
} tf;

static void tftp_ack(uint16_t block) {
  uint8_t *t = TX_BUF + 42;
  t[0] = 0; t[1] = 4; t[2] = block >> 8; t[3] = block;
  udp_send(tf.my_port, tf.srv_port, 4);
}

static void tftp_rrq(const char *name) {
  static const char opts[] = "octet\0blksize\0001400";       // mode, then the block size option
  uint8_t *t = TX_BUF + 42;
  int n = 0;
  t[n++] = 0; t[n++] = 1;
  do t[n++] = *name; while (*name++);
  for (unsigned i = 0; i < sizeof opts; i++) t[n++] = opts[i];
  udp_send(tf.my_port, TFTP_PORT, n);
}

// a UDP datagram from the server to the transfer's port: p is the TFTP packet, n its length
static void tftp_rx(const uint8_t *p, int n, uint16_t sport) {
  if (!tf.active || tf.done || tf.failed || n < 4) return;
  uint16_t op = rd16(p), block = rd16(p + 2);
  if (tf.srv_port && sport != tf.srv_port) return;
  if (op == 5) {                                            // error: code, then a message
    puts_(" server says: ");
    for (int i = 4; i < n && p[i]; i++) putch(p[i]);
    tf.failed = 1;
  } else if (op == 6 && tf.next == 1 && !tf.srv_port) {     // option acknowledgement
    tf.srv_port = sport;
    for (int i = 2; i + 8 < n; ) {                          // "blksize\0<digits>\0"
      int is_blk = p[i] == 'b' && p[i + 1] == 'l' && p[i + 2] == 'k';
      while (i < n && p[i]) i++;
      i++;
      uint32_t v = 0;
      while (i < n && p[i]) v = v * 10 + (p[i++] - '0');
      i++;
      if (is_blk && v >= 8 && v <= TFTP_BLKSIZE) tf.blksize = v;
    }
    tftp_ack(0);
    tf.progress = 1;
  } else if (op == 3) {
    if (!tf.srv_port) tf.srv_port = sport;                  // a server without options: 512-byte blocks
    if (block == tf.next) {
      const uint8_t *src = p + 4;
      for (int i = 0; i < n - 4; i++) tf.dst[tf.got + i] = src[i];
      tf.got += n - 4;
      tf.next++;
      tf.progress = 1;
      if ((uint32_t)(n - 4) < tf.blksize) tf.done = 1;
    }
    tftp_ack(tf.next - 1);                                  // also repeats the last one for a duplicate
  }
}

static void eth_poll(void) {
  volatile struct desc *d = &RX_RING[rx_next];
  if (!(d->flags & 1)) return;
  int len = d->len;
  const uint8_t *r = (const uint8_t *)(RX_BUF(rx_next) + 2);
  n_rx++;
  int for_me = len >= 34 && r[30] == my_ip[0] && r[31] == my_ip[1] && r[32] == my_ip[2] && r[33] == my_ip[3];
  if (len >= 42 && rd16(r + 12) == 0x0806 && rd16(r + 20) == 1 &&
      r[38] == my_ip[0] && r[39] == my_ip[1] && r[40] == my_ip[2] && r[41] == my_ip[3]) {
    arp_send(1, r + 22, r + 28);
    n_arp++;
  } else if (len >= 42 && rd16(r + 12) == 0x0806 && rd16(r + 20) == 2 &&
             r[28] == srv_ip[0] && r[29] == srv_ip[1] && r[30] == srv_ip[2] && r[31] == srv_ip[3]) {
    for (int i = 0; i < 6; i++) srv_mac[i] = r[22 + i];     // the reply to our request for the server
    srv_known = 1;
  } else if (for_me && rd16(r + 12) == 0x0800 && r[14] == 0x45 && r[23] == 1 && len >= 42 && r[34] == 8) {
    int total = 14 + rd16(r + 16);
    if (total <= len && total <= 1514) {
      uint8_t *t = TX_BUF;
      for (int i = 0; i < total; i++) t[i] = r[i];
      for (int i = 0; i < 6; i++) { t[i] = r[6 + i]; t[6 + i] = my_mac[i]; }
      for (int i = 0; i < 4; i++) { t[26 + i] = r[30 + i]; t[30 + i] = r[26 + i]; }
      t[34] = 0;                                   // echo reply; adjust the checksum for type 8 -> 0
      uint32_t ck = rd16(r + 36) + 0x0800u;
      ck = (ck & 0xffff) + (ck >> 16);
      t[36] = ck >> 8; t[37] = ck;
      eth_send(total);
      n_ping++;
    }
  } else if (for_me && rd16(r + 12) == 0x0800 && r[14] == 0x45 && r[23] == 17 && len >= 42 && rd16(r + 36) == 6464) {
    udp_loader(r, len);
  } else if (for_me && rd16(r + 12) == 0x0800 && r[14] == 0x45 && r[23] == 17 && len >= 46 && tf.active &&
             rd16(r + 36) == tf.my_port && r[26] == srv_ip[0] && r[27] == srv_ip[1] && r[28] == srv_ip[2] && r[29] == srv_ip[3]) {
    int n = rd16(r + 38) - 8;
    if (n >= 4 && 42 + n <= len) tftp_rx(r + 42, n, rd16(r + 34));
  }
  // give the descriptor back
  d->flags = 0;
  rx_next = (rx_next + 1) % RX_N;
  rx_tail = (rx_tail + 1) % RX_N;
  ETH(E_RX_TAIL) = rx_tail;
}

// ---------------------------------------------------------------- monitor
static void status(void) {
  uint32_t st = STATUS, es = ETH(E_STATUS);
  puts_("  clock "); putdec(CLOCK_HZ); puts_(CLOCK_MEAS ? " Hz measured (built for " : " Hz (built for ");
  putdec(CLOCK_BUILT); puts_("), build "); puthex(BUILD_ID, 8);
  puts_(", DDR3 "); puts_((st >> 16) & 1 ? "calibrated" : "NOT calibrated");
  puts_("\n  ethernet 02:00:00:fa:b1:e5 192.168.1.51, link "); puts_(es & 1 ? "up" : "down");
  puts_(", pcs 0x"); puthex(es >> 16, 4);
  puts_("\n  frames rx "); putdec(n_rx); puts_(" tx "); putdec(n_tx); puts_(" dropped "); putdec(ETH(E_DROPPED));
  puts_(", arp "); putdec(n_arp); puts_(", ping "); putdec(n_ping); puts_(", loaded "); putdec(n_load); puts_(" bytes\n");
}

static void serial_load(void) {
  uint32_t len = 0;
  for (int i = 0; i < 4; i++) len |= (uint32_t)getch() << (8 * i);
  volatile uint8_t *p = (volatile uint8_t *)DDR_BASE;
  uint8_t sum = 0;
  for (uint32_t i = 0; i < len; i++) { uint8_t c = getch(); p[i] = c; sum += c; }
  uint8_t want = getch();
  puts_("loaded "); putdec(len); puts_(sum == want ? " bytes, sum OK\n" : " bytes, SUM MISMATCH\n");
}

// A device tree handed to the next stage is given this machine's clock: the timebase and the
// CPU's clock frequency, the properties of /cpus and of its children, are overwritten in place
// with the measured clock. So one device tree serves a bitstream at any clock.
static uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }
static int name_is(const uint8_t *p, const char *s) { while (*s) if (*p++ != (uint8_t)*s++) return 0; return *p == 0; }
static void fdt_set_clock(uint64_t addr, uint32_t hz) {
  uint8_t *fdt = (uint8_t *)addr;
  if (addr < DDR_BASE || (addr & 3) || be32(fdt) != 0xd00dfeed) return;
  uint32_t total = be32(fdt + 4), strs = be32(fdt + 12);
  uint8_t *p = fdt + be32(fdt + 8), *end = fdt + total;
  int depth = 0, cpus = 0, n = 0;       // cpus: the depth of the /cpus node while inside it
  while (p + 4 <= end) {
    uint32_t tok = be32(p); p += 4;
    if (tok == 1) {                                        // a node begins: its name, padded
      depth++;
      if (depth == 2 && name_is(p, "cpus")) cpus = depth;
      while (p < end && *p) p++;
      p = (uint8_t *)(((uint64_t)p + 4) & ~3UL);
    } else if (tok == 2) {                                 // a node ends
      if (depth == cpus) cpus = 0;
      depth--;
    } else if (tok == 3) {                                 // a property: length, name, value
      uint32_t len = be32(p); const uint8_t *nm = fdt + strs + be32(p + 4);
      p += 8;
      if (cpus && len == 4 && (name_is(nm, "timebase-frequency") || name_is(nm, "clock-frequency"))) {
        p[0] = hz >> 24; p[1] = hz >> 16; p[2] = hz >> 8; p[3] = hz; n++;
      }
      p += (len + 3) & ~3u;
    } else if (tok != 4) break;                            // the end, or not a device tree
  }
  puts_("device tree: clock "); putdec(hz); puts_(" Hz in "); putdec(n); puts_(" properties\n");
}

static void boot(void (*entry)(uint64_t, uint64_t), uint64_t arg) {
  fdt_set_clock(arg, CLOCK_HZ);
  puts_("\njumping to 0x"); puthex((uint64_t)entry, 10); puts_(" a1=0x"); puthex(arg, 10); putch('\n');
  eth_stop();                                  // no DMA into memory the next stage owns
  while (!(UART_LSR & 0x40)) ;                 // let the last character out
  entry(0, arg);
}

// Wait up to `ms` for *flag, serving the network meanwhile. Returns 0 when the flag is set,
// 1 on time-out, 2 if a key was pressed or the UDP loader was told to start something.
static int wait_for(const int *flag, uint32_t ms) {
  uint64_t t0 = MTIME, ticks = (uint64_t)(CLOCK_HZ / 1000) * ms;
  while (!(flag && *flag)) {
    eth_poll();
    if (boot_entry || loader_seen || getch_nb() >= 0) return 2;
    if (MTIME - t0 >= ticks) return 1;
  }
  return 0;
}

// ---------------------------------------------------------------- configuration flash
// Micron G18 (Intel command set): 256 KiB blocks that power up locked, programmed through a
// 512-word buffer, one 1 KiB programming region at a time.
enum { FL_BLOCK = 0x40000, FL_REGION = 0x400 };

static void flash_id(void) {
  FL16(0) = 0x90;
  uint16_t man = FL16(0), dev = FL16(2);
  FL16(0) = 0x98;
  uint16_t q = FL16(0x20), r = FL16(0x22), y = FL16(0x24), set = (FL16(0x26) & 0xff) | (FL16(0x28) & 0xff) << 8, size = FL16(0x4e);
  FL16(0) = 0xff;
  puts_("  flash: manufacturer "); puthex(man, 4); puts_(" device "); puthex(dev, 4);
  if (q == 'Q' && r == 'R' && y == 'Y') {
    puts_(", CFI command set "); puthex(set, 4); puts_(", "); putdec(1u << ((size & 0xff) - 20)); puts_(" MiB");
  } else puts_(", no CFI answer");
  puts_(", first words "); puthex(FL64(0), 16); putch('\n');
}

// wait for the operation in the block at `b`; 0 if it ended without an error
static int flash_wait(uint32_t b, uint32_t ms) {
  uint64_t t0 = MTIME, ticks = (uint64_t)(CLOCK_HZ / 1000) * ms;
  for (;;) {
    uint16_t st = FL16(b);
    if (st & 0x80) {
      if (!(st & 0x3a)) return 0;
      FL16(b) = 0x50;
      puts_("\n  flash error, status "); puthex(st, 2); puts_(" at "); puthex(b, 7); putch('\n');
      return 1;
    }
    if (MTIME - t0 >= ticks) { puts_("\n  flash time-out at "); puthex(b, 7); putch('\n'); return 1; }
    eth_poll();
  }
}

static int flash_same(uint32_t off, const uint64_t *src, uint32_t n) {
  for (uint32_t i = 0; i < n; i += 8) if (FL64(off + i) != src[i / 8]) return 0;
  return 1;
}

// Make the flash from `off` equal to the `len` bytes at `src`. Only the blocks that differ are
// erased and written, so an interrupted update can simply be run again.
static int flash_update(const uint64_t *src, uint32_t len, uint32_t off, int force) {
  int ok = 0;
  if ((len & 7) || (off & (FL_BLOCK - 1)) || !len || off >= FLASH_SIZE || len > FLASH_SIZE - off) {
    puts_("  bad offset or length\n"); goto out;
  }
  if (off == 0 && !force) {         // the synchronisation word aa995566, as it lies in the flash
    int sync = 0;
    const uint8_t *p = (const uint8_t *)src;
    for (uint32_t i = 0; i + 4 <= 1024 && i + 4 <= len; i += 2)
      if (p[i] == 0x99 && p[i + 1] == 0x55 && p[i + 2] == 0x66 && p[i + 3] == 0xaa) sync = 1;
    if (!sync) { puts_("  not a bitstream image: refused\n"); goto out; }
  }
  fj.total = (len + FL_BLOCK - 1) / FL_BLOCK; fj.done = fj.written = 0;
  puts_("  flash "); puthex(off, 7); puts_(" + "); putdec(len); puts_(" bytes: ");
  FL16(0) = 0xff;
  for (uint32_t b = 0; b < len; b += FL_BLOCK, fj.done++) {
    uint32_t n = len - b < FL_BLOCK ? len - b : FL_BLOCK, fb = off + b;
    const uint64_t *s = src + b / 8;
    if (flash_same(fb, s, n)) { putch('.'); continue; }
    FL16(fb) = 0x60; FL16(fb) = 0xd0;                       // unlock
    FL16(fb) = 0x20; FL16(fb) = 0xd0;                       // erase
    if (flash_wait(fb, 30000)) goto out;
    for (uint32_t r = 0; r < n; r += FL_REGION) {
      uint32_t m = n - r < FL_REGION ? n - r : FL_REGION, blank = 1;
      const uint16_t *w = (const uint16_t *)s + r / 2;
      for (uint32_t i = 0; i < m / 2; i++) if (w[i] != 0xffff) blank = 0;
      if (blank) continue;
      FL16(fb) = 0x50;
      FL16(fb) = 0xe9; FL16(fb) = m / 2 - 1;
      for (uint32_t i = 0; i < m / 2; i++) FL16(fb + r + 2 * i) = w[i];
      FL16(fb) = 0xd0;
      if (flash_wait(fb, 5000)) goto out;
    }
    FL16(fb) = 0xff;
    if (!flash_same(fb, s, n)) { puts_("\n  verify failed at "); puthex(fb, 7); putch('\n'); goto out; }
    fj.written++;
    putch('W');
  }
  puts_(" done, "); putdec(fj.written); puts_(" of "); putdec(fj.total); puts_(" blocks written\n");
  ok = 1;
out:
  FL16(0) = 0xff;
  return ok;
}

static void reconfigure(void) {
  puts_("reloading the FPGA from flash\n");
  eth_stop();
  while (!(UART_LSR & 0x40)) ;
  RECONFIG = 0x49505247;
  for (;;) ;
}

static void flash_job(void) {
  fj.pending = 0;
  int ok = flash_update((const uint64_t *)fj.src, fj.len, fj.off, (fj.flags >> 1) & 1);
  fj.state = ok ? 2 : 3;
  if (ok && (fj.flags & 1)) {
    for (uint64_t t0 = MTIME; MTIME - t0 < 3 * (uint64_t)CLOCK_HZ; ) eth_poll();   // the host reads the result
    reconfigure();
  }
}

static int selftest_failed;

static int tftp_get(const char *name, uint64_t addr) {
  static uint16_t port = 0x6c00;
  puts_("  "); puts_(name); puts_(" -> 0x"); puthex(addr, 8); puts_(": ");
  __builtin_memset(&tf, 0, sizeof tf);
  tf.my_port = ++port; tf.next = 1; tf.blksize = 512; tf.dst = (uint8_t *)addr; tf.active = 1;
  uint64_t t0 = MTIME;
  int tries = 0, why = 0;
  tftp_rrq(name);
  while (!tf.done && !tf.failed) {
    tf.progress = 0;
    why = wait_for(&tf.progress, 1000);
    if (why == 2) break;
    if (why == 1) {                                         // nothing for a second: say it again
      if (++tries == 6) break;
      if (tf.srv_port) tftp_ack(tf.next - 1); else tftp_rrq(name);
    } else tries = 0;
  }
  tf.active = 0;
  if (tf.done) {
    putdec(tf.got); puts_(" bytes in "); putdec((MTIME - t0) / (CLOCK_HZ / 1000)); puts_(" ms\n");
    return 0;
  }
  puts_(tf.failed ? "\n" : why == 2 ? "interrupted\n" : "no answer\n");
  return 1;
}

static int tftp_server(void) {
  srv_known = 0;
  for (int i = 0; i < 4 && !srv_known; i++) {
    arp_send(0, 0, srv_ip);
    if (wait_for(&srv_known, 500) == 2) { puts_("  interrupted\n"); return 0; }
  }
  if (!srv_known) puts_("  no ARP reply from the server\n");
  return srv_known;
}

static void tftp_flash(void) {
  if (!tftp_server() || tftp_get("legend64/flash.img", UPDATE_ADDR)) return;
  while (tf.got & 7) ((uint8_t *)UPDATE_ADDR)[tf.got++] = 0xff;
  flash_update((const uint64_t *)UPDATE_ADDR, tf.got, 0, 0);
}

// fetch the boot files and start the first; returns only if that could not be done
static void tftp_boot(void) {
  puts_("TFTP boot from "); putdec(srv_ip[0]); putch('.'); putdec(srv_ip[1]); putch('.'); putdec(srv_ip[2]); putch('.'); putdec(srv_ip[3]); putch('\n');
  if (!tftp_server()) return;
  const int n = sizeof boot_files / sizeof boot_files[0];
  for (int i = 0; i < n; i++) if (tftp_get(boot_files[i].name, boot_files[i].addr)) return;
  boot_entry = (void (*)(uint64_t, uint64_t))boot_files[0].addr;
  boot_arg = boot_files[n - 1].addr;
}

int main(void) {
  LEDS = 1;
  puts_("\n\nlegend64 on VC707 - RV64GC boot monitor\n");
  int ddr_bad = 0;
  (void)ddr_bad;
#ifndef QUICK
  if (STATUS & ST_DDR_SOFT) {
    ddr_bad = !sdram_init();
    puts_(ddr_bad ? "DDR3 INITIALISATION FAILED\n" : "DDR3 ready\n");
  }
#endif
  eth_init();
  status();
  flash_id();
#ifndef QUICK
  puts_("memory test:\n");
  int bad = ddr_bad | memtest();
  puts_("floating point:\n");
  bad |= fpcheck();
  LEDS = bad ? 0x1f : 3;
  selftest_failed = bad;
  puts_(bad ? "SELF-TEST FAILED\n" : "self-test passed\n");
#endif
  arp_send(0, 0, my_ip);   // gratuitous ARP announces the address
#if !defined(QUICK) || defined(AUTOBOOT)
  if (!selftest_failed) {
    puts_("booting from the network in 3 s; any key for the prompt\n");
    if (wait_for(0, 3000) == 1) tftp_boot();
  }
#endif
  puts_("> ");
  for (;;) {
    eth_poll();
    if (boot_entry) boot(boot_entry, boot_arg);
    if (fj.pending) { putch('\n'); flash_job(); puts_("> "); }
    int c = getch_nb();
    if (c < 0) continue;
    if (c == 'i') { putch('\n'); status(); }
    else if (c == 'm') { putch('\n'); memtest(); }
#ifndef QUICK
    else if (c == 'd' && (STATUS & ST_DDR_SOFT)) { putch('\n'); eth_stop(); sdram_init(); eth_init(); }
#endif
    else if (c == 'f') { putch('\n'); fpcheck(); }
    else if (c == 'b') { putch('\n'); loader_seen = 0; tftp_boot(); }
    else if (c == 'F') { putch('\n'); flash_id(); }
    else if (c == 'U') { putch('\n'); loader_seen = 0; tftp_flash(); }
    else if (c == 'R') { putch('\n'); reconfigure(); }
    else if (c == 'L') serial_load();
    else if (c == 'g') boot((void (*)(uint64_t, uint64_t))DDR_BASE, 0);
    else continue;
    puts_("> ");
  }
}
