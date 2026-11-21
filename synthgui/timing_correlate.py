#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Correlate the mapper's pre-placement timing estimate with routed timing, endpoint by endpoint.

    timing_correlate.py <mapper timing report> <endpoints_pnr.tsv> [clock] [out.tsv]

The report is the mapper's with every endpoint in it (--map-only-timing-paths N); the TSV is
written by OpenSTA from nextpnr's routed netlist and SDF (timing_endpoints.tcl). Both must
describe the same netlist. Delays are launch clock pin to endpoint data pin, in ns.
"""
import re, sys, math, collections

rpt, tsv = sys.argv[1], sys.argv[2]
clock = sys.argv[3] if len(sys.argv) > 3 else 'clk_sys'

def base(n):                       # register bit behind an endpoint pin
    return n.rsplit('/', 1)[0]

# ---- mapper
M = {}
cur = None
for line in open(rpt):
    if line.startswith('#Path '):
        cur = {'lut': 0, 'carry': 0, 'mux': 0, 'net': 0.0, 'cnet': 0.0, 'launch': None, 'pts': 0}
    elif cur is None:
        continue
    elif line.startswith('Endpoint'):
        m = re.match(r'Endpoint\s*:\s*(\S+) \((\S+) clocked by (.*)\)', line)
        cur['end'], cur['clk'] = m.group(1), m.group(3)
    elif line.startswith('Startpoint'):
        cur['start'] = line.split(':', 1)[1].split()[0]
    elif line.startswith('data arrival time') and 'arr' not in cur:
        cur['arr'] = float(line.split()[-1])
        if cur['clk'] == clock and cur['launch'] is not None:
            M[cur['end']] = cur
    elif 'arr' not in cur:
        m = re.match(r'(\S+)/(\S+) \((\w+)\)( \[clock-to-output\])?\s+(-?[\d.]+)\s+(-?[\d.]+)', line)
        if not m: continue
        inst, pin, cell, c2o, incr, path = m.group(1), m.group(2), m.group(3), m.group(4), float(m.group(5)), float(m.group(6))
        if c2o:
            cur['launch'] = path - incr; cur['in_data'] = True
        elif cur.get('in_data'):
            is_out = pin.startswith(('O', 'CO', 'Q', 'DO', 'P'))
            if is_out:
                if cell.startswith('LUT'): cur['lut'] += 1
                elif cell == 'CARRY4': cur['carry'] += 1
                elif cell.startswith('MUXF'): cur['mux'] += 1
            else:
                cur['net'] += incr
                if cell == 'CARRY4' and pin == 'CI': cur['cnet'] += incr

# ---- routed
P = {}
f = open(tsv); hdr = f.readline().rstrip('\n').split('\t')
def names(n):
    """A routed pin under the names the mapper may know it by: nextpnr's slice and block RAM pins
    against the library cell's (SR for R/CLR/S/PRE, WA<k+1> for A<k>, ...L<i>/...U<i> for [i])."""
    inst, pin = n.rsplit('/', 1)
    if pin == 'SR':
        return [inst + '/' + x for x in ('R', 'CLR', 'S', 'PRE')]
    if inst.endswith(('/DP', '/SP')):
        inst = inst[:-3]
        m = re.match(r'WA(\d)$', pin)
        if m: return ['%s/A%d(write)' % (inst, int(m.group(1)) - 1)]
        return [inst + '/' + {'DI1': 'D'}.get(pin, pin)]
    m = re.match(r'([A-Z]+?)[LU]?(\d+)$', pin)
    if m: return [n, '%s/%s[%s]' % (inst, m.group(1), m.group(2))]
    return [n]
for line in f:
    d = dict(zip(hdr, line.rstrip('\n').split('\t')))
    for k in names(d['endpoint']):
        if k in M and (k not in P or float(d['arrival']) - float(d['start_arr']) > float(P[k]['arrival']) - float(P[k]['start_arr'])):
            P[k] = d

rows = []
for e, m in M.items():
    p = P.get(e)
    if not p: continue
    md = m['arr'] - m['launch']
    pd = (float(p['arrival']) - float(p['start_arr'])) * 1e9 + 0.0
    # start_arr is at the launch Q pin: add nothing, and take the mapper's from its Q pin too
    rows.append((e, md, pd, m, p))
print('mapper endpoints on %s: %d   matched with a routed endpoint: %d' % (clock, len(M), len(rows)))
if not rows: sys.exit(1)

def pearson(x, y):
    n = len(x); mx = sum(x) / n; my = sum(y) / n
    sxy = sum((a - mx) * (b - my) for a, b in zip(x, y)); sxx = sum((a - mx) ** 2 for a in x); syy = sum((b - my) ** 2 for b in y)
    return sxy / math.sqrt(sxx * syy), sxy / sxx, my - sxy / sxx * mx
def ranks(v):
    o = sorted(range(len(v)), key=lambda i: v[i]); r = [0.0] * len(v); i = 0
    while i < len(o):
        j = i
        while j + 1 < len(o) and v[o[j + 1]] == v[o[i]]: j += 1
        for k in range(i, j + 1): r[o[k]] = (i + j) / 2.0
        i = j + 1
    return r
def stats(sel, label):
    x = [r[1] for r in sel]; y = [r[2] for r in sel]
    if len(sel) < 3: return
    r, slope, icpt = pearson(x, y); rs = pearson(ranks(x), ranks(y))[0]
    ratio = sorted(b / a for a, b in zip(x, y) if a > 0)
    err = [b - a for a, b in zip(x, y)]
    rms = math.sqrt(sum(e * e for e in err) / len(err))
    print('%-34s n=%6d  r=%.3f  rank r=%.3f  routed = %.2f*est %+.2f ns  routed/est median %.2f (10%%..90%%: %.2f..%.2f)  mean err %+.2f rms %.2f ns'
          % (label, len(sel), r, rs, slope, icpt, ratio[len(ratio) // 2], ratio[len(ratio) // 10], ratio[len(ratio) * 9 // 10], sum(err) / len(err), rms))

# the mapper's delay is from the launch clock pin; the routed one from the launch Q pin: put both at Q
rows = [(e, md - 0.303, pd, m, p) for e, md, pd, m, p in rows]
stats(rows, 'all endpoints')
stats([r for r in rows if r[2] > 10], 'routed delay > 10 ns')
stats([r for r in rows if r[2] > 20], 'routed delay > 20 ns')
for lo, hi in ((0, 0), (1, 8), (9, 24), (25, 99)):
    stats([r for r in rows if lo <= r[3]['carry'] <= hi], 'mapper path CARRY4s %d..%d' % (lo, hi))
for lo, hi in ((0, 3), (4, 8), (9, 15), (16, 99)):
    stats([r for r in rows if lo <= r[3]['lut'] <= hi], 'mapper path LUTs %d..%d' % (lo, hi))

# do they agree on which endpoints are critical?
by_m = sorted(rows, key=lambda r: -r[1]); by_p = sorted(rows, key=lambda r: -r[2])
for k in (20, 100, 500, 2000):
    a = set(r[0] for r in by_m[:k]); b = set(r[0] for r in by_p[:k])
    print('worst %4d by each: %4d in common (%.0f %%)' % (k, len(a & b), 100.0 * len(a & b) / k))
print('worst routed endpoint %s: %.2f ns routed, %.2f ns estimated, rank %d in the mapper\'s order'
      % (by_p[0][0], by_p[0][2], by_p[0][1], [r[0] for r in by_m].index(by_p[0][0]) + 1))
print('worst estimated endpoint %s: %.2f ns estimated, %.2f ns routed, rank %d in the routed order'
      % (by_m[0][0], by_m[0][1], by_m[0][2], [r[0] for r in by_p].index(by_m[0][0]) + 1))

# where the difference comes from: regress the error on what the mapper's path is made of
def groupname(e):
    for k, v in (('u_fpu', 'FPU'), ('u_core_m_val', 'core m_val'), ('u_core', 'core other'), ('u_cache', 'cache'), ('u_eth', 'ethernet'), ('u_flash', 'flash')):
        if k in e: return v
    return 'other'
g = collections.defaultdict(list)
for r in rows: g[groupname(r[0])].append(r)
for k in sorted(g, key=lambda k: -len(g[k])): stats(g[k], 'block: ' + k)
tot_c = sum(r[3]['cnet'] for r in by_m[:500]); tot_n = sum(r[3]['net'] for r in by_m[:500]); tot_d = sum(r[1] for r in by_m[:500])
print('mapper\'s worst 500 paths: %.0f %% of their estimated delay is net delay; %.0f %% is the net delay charged on carry-chain links'
      % (100 * tot_n / tot_d, 100 * tot_c / tot_d))
if len(sys.argv) > 4:
    with open(sys.argv[4], 'w') as o:
        o.write('endpoint\testimated_ns\trouted_ns\tluts\tcarry4\tmuxf\tcarry_link_net_ns\n')
        for e, md, pd, m, p in rows: o.write('%s\t%.3f\t%.3f\t%d\t%d\t%d\t%.3f\n' % (e, md, pd, m['lut'], m['carry'], m['mux'], m['cnet']))
