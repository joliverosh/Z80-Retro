#!/usr/bin/env python3
"""partecad.py archivo.c... - parte las llamadas pstr (os, msg) con un texto largo
hecho de varias cadenas seguidas ("..." "...") en varias llamadas: a HI-TECH C
3.09 (P1) no le caben las de mas de unos cientos de bytes. Lo que sale es lo mismo."""
import re, sys
LIT = r'"(?:\\.|[^"\\\n])*"'
PAT = re.compile(r'(?P<ind>[ \t]*)(?P<fn>pstr|os|puts_|msg)\((?P<lits>(?:\s*' + LIT + r')+)\s*\);')
def litlen(l): return len(l) - 2
for f in sys.argv[1:]:
    s = open(f).read(); n = 0
    def rep(m):
        global n
        lits = re.findall(LIT, m.group('lits'))
        if sum(map(litlen, lits)) < 300 or len(lits) < 2: return m.group(0)
        n += 1; ind = m.group('ind'); out = []; cur = []; size = 0
        for l in lits:
            if cur and size + litlen(l) > 200:
                out.append(cur); cur = []; size = 0
            cur.append(l); size += litlen(l)
        if cur: out.append(cur)
        fn = m.group('fn'); sep = '\n' + ind + ' ' * (len(fn) + 1)
        return '\n'.join(ind + fn + '(' + sep.join(c) + ');' for c in out)
    s2 = PAT.sub(rep, s)
    if n: open(f, 'w').write(s2); print(f, n)
