// SPDX-License-Identifier: Apache-2.0
// Boot monitor for legend64 on the VC707. Runs in machine mode from block RAM.
//
// It checks the DDR3 memory and the FPU, brings up the Ethernet MAC, answers ARP and ping, and
// loads images into memory over UDP so that firmware, kernel and device tree arrive in seconds
// (see fpga/scripts/netload.py for the host side). Images can also be sent over the serial line.
//
// Serial commands (115200 8N1):
//   i  status            m  memory test            f  floating-point check
//   d  initialise and level the DDR3 again (LiteDRAM builds)
//   L  load: 4-byte little-endian length, the image, 1-byte sum; stored at 0x8000_0000
//   g  jump to 0x8000_0000 (a0 = 0, a1 = 0)
//
// UDP loader, port 6464. Request and reply share a 24-byte header, little-endian:
//   u32 magic 'FBL1'   u8 command, 3 bytes zero   u32 sequence   u64 address   u32 length
//   command 1  write `length` bytes that follow to `address`
//   command 2  jump to `address`; the 8 bytes that follow are passed in a1 (a0 = 0)
//   command 3  no operation (probe)
// The reply is the same header with bit 7 set in the command and no payload.
#include <stdint.h>
#include <stddef.h>

#define REG8(a)  (*(volatile uint8_t *)(a))
#define REG32(a) (*(volatile uint32_t *)(a))
#define REG64(a) (*(volatile uint64_t *)(a))
#define UART_THR   REG8(0x10000000)
#define UART_LSR   REG8(0x10000005)
#define LEDS       REG32(0x20000000)
#define STATUS     REG32(0x20000008)
#define CLOCK_HZ   REG32(0x2000000c)
#define BUILD_ID   REG32(0x20000010)
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

static void udp_loader(const uint8_t *r, int len) {
  const uint8_t *h = r + 42;
  if (len < 42 + 24 || rdle32(h) != 0x314c4246) return;   // 'FBL1'
  uint8_t cmd = h[4];
  uint64_t addr = rdle64(h + 12);
  uint32_t n = rdle32(h + 20);
  if (cmd == 1 && 42 + 24 + (int)n <= len) {
    uint8_t *dst = (uint8_t *)addr;
    const uint8_t *src = h + 24;
    for (uint32_t i = 0; i < n; i++) dst[i] = src[i];
    n_load += n;
  } else if (cmd == 2 && len >= 42 + 32) {
    boot_entry = (void (*)(uint64_t, uint64_t))addr;
    boot_arg = rdle64(h + 24);
  } else if (cmd != 3) return;
  // reply: swap addresses and ports, echo the header with bit 7 set in the command
  uint8_t *t = TX_BUF;
  for (int i = 0; i < 6; i++) { t[i] = r[6 + i]; t[6 + i] = my_mac[i]; }
  t[12] = 0x08; t[13] = 0x00;
  for (int i = 14; i < 34; i++) t[i] = r[i];
  t[16] = 0; t[17] = 20 + 8 + 24;
  t[22] = 64; t[24] = 0; t[25] = 0;
  for (int i = 0; i < 4; i++) { t[26 + i] = my_ip[i]; t[30 + i] = r[26 + i]; }
  uint16_t ck = ip_checksum(t + 14, 20);
  t[24] = ck >> 8; t[25] = ck;
  t[34] = r[36]; t[35] = r[37]; t[36] = r[34]; t[37] = r[35];
  t[38] = 0; t[39] = 8 + 24; t[40] = 0; t[41] = 0;        // UDP checksum not used
  for (int i = 0; i < 24; i++) t[42 + i] = h[i];
  t[42 + 4] = cmd | 0x80;
  eth_send(42 + 24);
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
  puts_("  clock "); putdec(CLOCK_HZ); puts_(" Hz, build "); puthex(BUILD_ID, 8);
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

static void boot(void (*entry)(uint64_t, uint64_t), uint64_t arg) {
  puts_("\njumping to 0x"); puthex((uint64_t)entry, 10); puts_(" a1=0x"); puthex(arg, 10); putch('\n');
  eth_stop();                                  // no DMA into memory the next stage owns
  while (!(UART_LSR & 0x40)) ;                 // let the last character out
  entry(0, arg);
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
#ifndef QUICK
  puts_("memory test:\n");
  int bad = ddr_bad | memtest();
  puts_("floating point:\n");
  bad |= fpcheck();
  LEDS = bad ? 0x1f : 3;
  puts_(bad ? "SELF-TEST FAILED\n" : "self-test passed\n");
#endif
  arp_send(0, 0, my_ip);   // gratuitous ARP announces the address
  puts_("> ");
  for (;;) {
    eth_poll();
    if (boot_entry) boot(boot_entry, boot_arg);
    int c = getch_nb();
    if (c < 0) continue;
    if (c == 'i') { putch('\n'); status(); }
    else if (c == 'm') { putch('\n'); memtest(); }
#ifndef QUICK
    else if (c == 'd' && (STATUS & ST_DDR_SOFT)) { putch('\n'); eth_stop(); sdram_init(); eth_init(); }
#endif
    else if (c == 'f') { putch('\n'); fpcheck(); }
    else if (c == 'L') serial_load();
    else if (c == 'g') boot((void (*)(uint64_t, uint64_t))DDR_BASE, 0);
    else continue;
    puts_("> ");
  }
}
