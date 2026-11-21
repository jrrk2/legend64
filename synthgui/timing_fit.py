#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Fit Vivado's delays to the calibrated (typical) delays of the same route, as one scale factor.

    timing_fit.py <correlation.tsv> <vivado ep dir> [scale ...]

correlation.tsv is timing_correlate.py's table (calibrated routed delay per endpoint, register
output to data pin, with the make-up of the path); the directory holds setup_slow.tsv,
setup_fast.tsv and hold.tsv from vivado_endpoints.tcl on the json2dcp checkpoint of that route.
Setup: calibrated ~ scale * Vivado, fitted through the origin, overall and by path class; then
the clock's Fmax for a choice of scales on Vivado's slow-corner delays. Hold: Vivado's own
fast-corner result, unscaled.
"""
import csv, math, re, sys, collections
cor, ep = sys.argv[1], sys.argv[2]
scales = [float(x) for x in sys.argv[3:]]
CLK2Q = 0.30          # the calibrated table starts at the register's output; Vivado's paths at its clock pin

def key(n):           # a Vivado pin under the mapper's name for it
    m = re.match(r'(.*)__(?:DP|SP)/(\w+)$', n)
    if m:
        inst, pin = m.group(1), m.group(2)
        a = re.match(r'WADR(\d)$', pin)
        return '%s/A%s(write)' % (inst, a.group(1)) if a else inst + '/' + {'I': 'D'}.get(pin, pin)
    return n
def load(f):
    d = {}
    for r in csv.DictReader(open(f), delimiter='\t'):
        k = key(r['endpoint'])
        if k not in d or float(r['datapath']) > float(d[k]['datapath']): d[k] = r
    return d
C = {r['endpoint']: r for r in csv.DictReader(open(cor), delimiter='\t')}
S, F, H = load(ep + '/setup_slow.tsv'), load(ep + '/setup_fast.tsv'), load(ep + '/hold.tsv')
rows = [(e, float(c['routed_ns']) + CLK2Q, float(S[e]['datapath']), float(F[e]['datapath']), c, S[e]) for e, c in C.items() if e in S and e in F]
print('endpoints: calibrated %d, Vivado %d, in both %d' % (len(C), len(S), len(rows)))

def fit(sel, i):
    x = [r[i] for r in sel]; y = [r[1] for r in sel]
    s = sum(a * b for a, b in zip(x, y)) / sum(a * a for a in x)
    res = [b - s * a for a, b in zip(x, y)]
    rms = math.sqrt(sum(e * e for e in res) / len(res))
    rat = sorted(b / a for a, b in zip(x, y) if a > 0)
    return s, rms, rat[len(rat) // 10], rat[len(rat) // 2], rat[len(rat) * 9 // 10]
def line(label, sel):
    if len(sel) < 20: return
    a = fit(sel, 2); b = fit(sel, 3)
    print('%-30s n=%6d | slow: scale %.3f  rms %.2f ns  ratio 10/50/90%%: %.2f %.2f %.2f | fast: scale %.3f  rms %.2f ns  ratio %.2f %.2f %.2f'
          % ((label, len(sel)) + a + b))
line('all endpoints', rows)
line('calibrated delay > 10 ns', [r for r in rows if r[1] > 10])
line('calibrated delay > 20 ns', [r for r in rows if r[1] > 20])
for lo, hi in ((0, 0), (1, 8), (9, 24), (25, 999)):
    line('CARRY4s on the path %d..%d' % (lo, hi), [r for r in rows if lo <= int(r[4]['carry4']) <= hi])
# logic and net separately: calibrated ~ a*logic + b*net (slow corner)
def fit2(sel):
    sxx = sxy = syy = sxz = syz = 0.0
    for r in sel:
        x, y, z = float(r[5]['logic']), float(r[5]['net']), r[1]
        sxx += x * x; sxy += x * y; syy += y * y; sxz += x * z; syz += y * z
    det = sxx * syy - sxy * sxy
    return (sxz * syy - syz * sxy) / det, (syz * sxx - sxz * sxy) / det
a, b = fit2([r for r in rows if r[1] > 10])
print('logic and net apart (calibrated > 10 ns, slow corner): calibrated = %.3f * logic + %.3f * net' % (a, b))

s_all = fit([r for r in rows if r[1] > 10], 2)[0]
print('\nFmax of the clock with Vivado slow-corner delays scaled (data path scaled, clock skew and requirement as Vivado has them):')
allS = list(csv.DictReader(open(ep + '/setup_slow.tsv'), delimiter='\t'))
req = float(allS[0]['requirement'])
for s in sorted(set(scales + [1.0, round(s_all, 3)]), reverse=True):
    worst = min(allS, key=lambda r: float(r['slack']) + (1 - s) * float(r['datapath']))
    sl = float(worst['slack']) + (1 - s) * float(worst['datapath'])
    nfail = sum(1 for r in allS if float(r['slack']) + (1 - s) * float(r['datapath']) < 0)
    tag = ' (Vivado slow, as is)' if s == 1.0 else ' (fitted to calibrated)' if abs(s - s_all) < 5e-4 else ''
    print('  scale %.3f%-24s period %.2f ns  Fmax %.1f MHz  failing at %.0f ns: %d  worst %s' % (s, tag, req - sl, 1000 / (req - sl), req, nfail, worst['endpoint']))

hv = sorted((float(r['slack']), k) for k, r in H.items() if float(r['slack']) < 0)
print('\nhold, Vivado fast corner, unscaled: %d endpoints checked, %d violate%s' % (len(H), len(hv), ''.join('\n  %.3f ns  %s' % x for x in hv[:10])))
print('smallest hold slacks:', ', '.join('%.3f' % float(r['slack']) for r in sorted(H.values(), key=lambda r: float(r['slack']))[:8]))
