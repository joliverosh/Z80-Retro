#!/usr/bin/env python3
"""test_bombe.py - compara BOMBE.COM (en cpmrun) con bombe.py: cada parada, las
clavijas deducidas y el descifrado de prueba.
  python3 test_bombe.py          # el orden II-V-III
  python3 test_bombe.py all      # los 60 ordenes"""
import os, re, subprocess, sys, time
import bombe as B
ROMAN = ['I', 'II', 'III', 'IV', 'V']
everything = len(sys.argv) > 1 and sys.argv[1] == 'all'
here = os.path.dirname(os.path.abspath(__file__))
t = time.time()
r = subprocess.run([os.path.join(here, '../../pi/run/cpmrun'), os.path.join(here, 'BOMBE.COM'), '7.3728']
                   + (['ALL'] if everything else []), capture_output=True, timeout=7200)
out = r.stdout.decode('latin1').replace('\r', '')
print(f'Z80: {time.time() - t:.0f} s en el PC; {r.stderr.decode().strip()}')
got_stops = re.findall(r'STOP ([IV]+)-([IV]+)-([IV]+) ([A-Z]{3}) ([A-Z])-([A-Z])', out)
got_check = []
for m in re.finditer(r'\n([A-Z]{3}): (?:Stecker ([A-Z ]*)\n((?:[A-Z ]+\n)+)|(contradiction))', out):
    got_check.append(m.groups())
ct = B.encipher(); crib_ct = ct[:len(B.CRIB)]
orders = [['II', 'V', 'III']] if not everything else \
    [[ROMAN[a], ROMAN[b], ROMAN[c]] for a in range(5) for b in range(5) for c in range(5) if len({a, b, c}) == 3]
want_stops, want_check = [], []
t = time.time()
for order in orders:
    stops, test, _ = B.run(order, B.CRIB, crib_ct)
    for l, m, rr, st in stops:
        want_stops.append((*order, B.pos(l, m, rr), chr(test + B.A), chr(st + B.A)))
    want_check += B.checking(order, B.CRIB, ct, stops)
print(f'Python: {time.time() - t:.0f} s')
ok = [tuple(s) for s in got_stops] == want_stops
print(f'paradas: Z80 {len(got_stops)}, Python {len(want_stops)}: {"IGUALES" if ok else "DISTINTAS"}')
good = 0
for g, w in zip(got_check, want_check):
    pos, pairs, text, contra = g
    if w[1] is None:
        good += bool(contra)
    else:
        good += pos == w[0] and pairs.split() == w[1] and re.sub(r'[^A-Z]', '', text).startswith(w[2])
ok &= good == len(want_check) == len(got_check)
print(f'verificacion: {good}/{len(want_check)} iguales (clavijas y descifrado)')
print(re.search(r'Stops:.*\n.*', out).group(0))
sys.exit(0 if ok else 1)
