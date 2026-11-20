// Reference vectors for legend64_fpu, computed on the host FPU (x86-64 SSE/FMA, IEEE 754 with
// tininess detected after rounding, the same choice RISC-V makes).
// Output lines: insn a b c x rm result flags   (hex; flags = NV DZ OF UF NX)
// Where RISC-V and x86 differ by definition the expected value is computed explicitly:
// canonical NaN results, NV for fma(inf, 0, qNaN), saturating float-to-integer conversion.
// Round-to-nearest-max-magnitude does not exist on x86, so it is not covered here.
// usage: fpu_vectors <seed> <count>
#include <fenv.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#pragma STDC FENV_ACCESS ON

static uint64_t s[2];
static uint64_t rnd(void) {  // xorshift128+
  uint64_t a = s[0], b = s[1];
  s[0] = b; a ^= a << 23; s[1] = a ^ b ^ (a >> 17) ^ (b >> 26);
  return s[1] + b;
}
static double d_of(uint64_t u) { double d; memcpy(&d, &u, 8); return d; }
static uint64_t u_of(double d) { uint64_t u; memcpy(&u, &d, 8); return u; }
static float f_of(uint32_t u) { float f; memcpy(&f, &u, 4); return f; }
static uint32_t u_off(float f) { uint32_t u; memcpy(&u, &f, 4); return u; }

static uint64_t rand_d(void) {
  static const uint64_t sp[] = {0, 0x8000000000000000ull, 0x7ff0000000000000ull, 0xfff0000000000000ull,
    0x7ff8000000000000ull, 0x7ff0000000000001ull, 1, 0x000fffffffffffffull, 0x0010000000000000ull,
    0x7fefffffffffffffull, 0x3ff0000000000000ull, 0xbff0000000000000ull, 0x3ff0000000000001ull,
    0x3fefffffffffffffull, 0x4000000000000000ull, 0x8000000000000001ull, 0x43e0000000000000ull,
    0xc3e0000000000000ull, 0x41e0000000000000ull, 0x41dfffffffc00000ull, 0x3fe0000000000000ull};
  uint64_t r = rnd();
  switch (r % 10) {
    case 0: return sp[(r >> 8) % (sizeof sp / sizeof *sp)];
    case 1: return rnd();
    case 2: return (rnd() & 0x800fffffffffffffull) | ((uint64_t)((r >> 8) % 8) << 52);            // tiny
    case 3: return (rnd() & 0x800fffffffffffffull) | ((uint64_t)(0x7f8 + (r >> 8) % 7) << 52);    // huge
    case 4: return (rnd() & 0x800fffffffffffffull) | ((uint64_t)(0x3ff - 60 + (r >> 8) % 130) << 52);
    case 5: return (rnd() & 0x8000000000000000ull) | ((uint64_t)(0x3ff + (r >> 8) % 4) << 52) | (1ull << ((r >> 16) % 52));
    default: return (rnd() & 0x800fffffffffffffull) | ((uint64_t)(0x3ff - 3 + (r >> 8) % 7) << 52);
  }
}
static uint32_t rand_s(void) {
  static const uint32_t sp[] = {0, 0x80000000, 0x7f800000, 0xff800000, 0x7fc00000, 0x7f800001, 1, 0x007fffff,
    0x00800000, 0x7f7fffff, 0x3f800000, 0xbf800000, 0x3f800001, 0x3f7fffff, 0x40000000, 0x80000001,
    0x5f000000, 0xdf000000, 0x4f000000, 0x4effffff, 0x3f000000};
  uint64_t r = rnd();
  switch (r % 10) {
    case 0: return sp[(r >> 8) % (sizeof sp / sizeof *sp)];
    case 1: return (uint32_t)rnd();
    case 2: return ((uint32_t)rnd() & 0x807fffff) | ((uint32_t)((r >> 8) % 8) << 23);
    case 3: return ((uint32_t)rnd() & 0x807fffff) | ((uint32_t)(0xf8 + (r >> 8) % 7) << 23);
    case 4: return ((uint32_t)rnd() & 0x807fffff) | ((uint32_t)(0x7f - 30 + (r >> 8) % 70) << 23);
    case 5: return ((uint32_t)rnd() & 0x80000000) | ((uint32_t)(0x7f + (r >> 8) % 4) << 23) | (1u << ((r >> 16) % 23));
    default: return ((uint32_t)rnd() & 0x807fffff) | ((uint32_t)(0x7f - 3 + (r >> 8) % 7) << 23);
  }
}
static uint64_t rand_x(void) {
  uint64_t r = rnd();
  switch (r % 6) {
    case 0: return (uint64_t)(int64_t)(int8_t)(r >> 8);
    case 1: return rnd() >> ((r >> 8) % 64);
    case 2: return -(rnd() >> ((r >> 8) % 64));
    case 3: return (1ull << ((r >> 8) % 64)) + (int64_t)((r >> 16) % 5) - 2;
    default: return rnd();
  }
}
static int host_flags(void) {
  int e = fetestexcept(FE_ALL_EXCEPT), f = 0;
  if (e & FE_INVALID) f |= 16;
  if (e & FE_DIVBYZERO) f |= 8;
  if (e & FE_OVERFLOW) f |= 4;
  if (e & FE_UNDERFLOW) f |= 2;
  if (e & FE_INEXACT) f |= 1;
  return f;
}
static const int host_rm[4] = {FE_TONEAREST, FE_TOWARDZERO, FE_DOWNWARD, FE_UPWARD};
#define BOX(u32) (0xffffffff00000000ull | (uint32_t)(u32))
static int isnan_d(uint64_t u) { return (u & 0x7fffffffffffffffull) > 0x7ff0000000000000ull; }
static int isnan_s(uint32_t u) { return (u & 0x7fffffff) > 0x7f800000; }
static int iszero_d(uint64_t u) { return (u << 1) == 0; }
static int isinf_d(uint64_t u) { return (u << 1) == 0xffe0000000000000ull; }
static int iszero_s(uint32_t u) { return (u << 1) == 0; }
static int isinf_s(uint32_t u) { return (u << 1) == 0xff000000u; }

static uint32_t op_fp(int f5, int dbl, int rs2, int rm) { return (f5 << 27) | (dbl << 25) | (rs2 << 20) | (rm << 12) | 0x53; }
static uint32_t op_fma(int kind, int dbl, int rm) { return (dbl << 25) | (rm << 12) | 0x43 | (kind << 2); }

int main(int argc, char **argv) {
  s[0] = 0x9e3779b97f4a7c15ull ^ strtoull(argv[1], 0, 0); s[1] = 0xbf58476d1ce4e5b9ull;
  long n = atol(argv[2]);
  for (int i = 0; i < 20; i++) rnd();
  for (long i = 0; i < n; i++) {
    int rm = rnd() % 4, dbl = rnd() & 1, kind = rnd() % 16;
    uint64_t a64 = rand_d(), b64 = rand_d(), c64 = rand_d(), x = rand_x();
    uint32_t a32 = rand_s(), b32 = rand_s(), c32 = rand_s();
    if (rnd() % 4 == 0) { b64 = a64 ^ (rnd() % 3 == 0 ? 0x8000000000000000ull : 0) ^ ((rnd() % 4 == 0) ? 1 : 0); b32 = a32 ^ (rnd() % 3 == 0 ? 0x80000000 : 0) ^ ((rnd() % 4 == 0) ? 1 : 0); }
    volatile double da = d_of(a64), db = d_of(b64), dc = d_of(c64), dr = 0;
    volatile float fa = f_of(a32), fb = f_of(b32), fc = f_of(c32), fr = 0;
    uint64_t A = dbl ? a64 : BOX(a32), B = dbl ? b64 : BOX(b32), C = dbl ? c64 : BOX(c32), res = 0;
    uint32_t insn = 0;
    int fl = 0, fp_result = 1;
    if (kind >= 8 && kind <= 11 && rnd() % 3 == 0) {  // make fma cancellation likely: c ~ -(a*b)
      fesetround(FE_TONEAREST);
      if (dbl) { dc = -(da * db); c64 = u_of(dc) ^ (rnd() % 4 == 0 ? 1 : 0); dc = d_of(c64); C = c64; }
      else { fc = -(fa * fb); c32 = u_off(fc) ^ (rnd() % 4 == 0 ? 1 : 0); fc = f_of(c32); C = BOX(c32); }
    }
    fesetround(host_rm[rm]);
    feclearexcept(FE_ALL_EXCEPT);
    switch (kind) {
      case 0: insn = op_fp(0, dbl, 0, rm); if (dbl) dr = da + db; else fr = fa + fb; break;
      case 1: insn = op_fp(1, dbl, 0, rm); if (dbl) dr = da - db; else fr = fa - fb; break;
      case 2: case 3: insn = op_fp(2, dbl, 0, rm); if (dbl) dr = da * db; else fr = fa * fb; break;
      case 4: case 5: insn = op_fp(3, dbl, 0, rm); if (dbl) dr = da / db; else fr = fa / fb; break;
      case 6: case 7: insn = op_fp(11, dbl, 0, rm); if (dbl) dr = sqrt(da); else fr = sqrtf(fa); break;
      case 8: insn = op_fma(0, dbl, rm); if (dbl) dr = fma(da, db, dc); else fr = fmaf(fa, fb, fc); break;
      case 9: insn = op_fma(1, dbl, rm); if (dbl) dr = fma(da, db, -dc); else fr = fmaf(fa, fb, -fc); break;
      case 10: insn = op_fma(2, dbl, rm); if (dbl) dr = fma(-da, db, dc); else fr = fmaf(-fa, fb, fc); break;
      case 11: insn = op_fma(3, dbl, rm); if (dbl) dr = fma(-da, db, -dc); else fr = fmaf(-fa, fb, -fc); break;
      case 12: {  // float <-> float
        insn = op_fp(8, dbl, dbl ? 0 : 1, rm);
        if (dbl) { dr = (double)fa; A = BOX(a32); } else { fr = (float)da; A = a64; }
        break;
      }
      case 13: {  // integer -> float
        int t = rnd() % 4;
        insn = op_fp(26, dbl, t, rm);
        if (dbl) dr = t == 0 ? (double)(int32_t)x : t == 1 ? (double)(uint32_t)x : t == 2 ? (double)(int64_t)x : (double)x;
        else     fr = t == 0 ? (float)(int32_t)x : t == 1 ? (float)(uint32_t)x : t == 2 ? (float)(int64_t)x : (float)x;
        break;
      }
      default: {  // float -> integer, saturating
        int t = rnd() % 4;
        insn = op_fp(24, dbl, t, rm);
        fp_result = 0;
        volatile double v = dbl ? da : (double)fa;   // widening is exact
        int nan = dbl ? isnan_d(a64) : isnan_s(a32);
        feclearexcept(FE_ALL_EXCEPT);
        volatile double r = rint(v);
        int inexact = !nan && r != v;
        double lo = t == 0 ? -2147483648.0 : t == 2 ? -9223372036854775808.0 : 0.0;
        double hi = t == 0 ? 2147483648.0 : t == 1 ? 4294967296.0 : t == 2 ? 9223372036854775808.0 : 18446744073709551616.0;
        if (nan || r >= hi) { res = t == 0 ? 0x7fffffffull : t == 2 ? 0x7fffffffffffffffull : ~0ull; fl = 16; }
        else if (r < lo)    { res = t == 0 ? 0xffffffff80000000ull : t == 2 ? 0x8000000000000000ull : 0; fl = 16; }
        else {
          if (t == 0) res = (uint64_t)(int64_t)(int32_t)r;
          else if (t == 1) res = (uint64_t)(int64_t)(int32_t)(uint32_t)r;
          else if (t == 2) res = (uint64_t)(int64_t)r;
          else res = r >= 9223372036854775808.0 ? (uint64_t)(r - 9223372036854775808.0) + 0x8000000000000000ull : (uint64_t)r;
          fl = inexact;
        }
      }
    }
    if (fp_result) {
      fl = host_flags();
      if (dbl) res = isnan_d(u_of(dr)) ? 0x7ff8000000000000ull : u_of(dr);
      else     res = BOX(isnan_s(u_off(fr)) ? 0x7fc00000 : u_off(fr));
      if (kind >= 8 && kind <= 11) {  // RISC-V raises NV for inf*0 even when the addend is a quiet NaN
        int iz = dbl ? (isinf_d(a64) && iszero_d(b64)) || (iszero_d(a64) && isinf_d(b64))
                     : (isinf_s(a32) && iszero_s(b32)) || (iszero_s(a32) && isinf_s(b32));
        if (iz) fl |= 16;
      }
    }
    fesetround(FE_TONEAREST);
    printf("%08x %016llx %016llx %016llx %016llx %d %016llx %02x\n", insn, (unsigned long long)A, (unsigned long long)B,
           (unsigned long long)C, (unsigned long long)x, rm, (unsigned long long)res, fl);
  }
  return 0;
}
