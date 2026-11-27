#!/usr/bin/env python3
"""revisa.py PROG.AS... - busca en lo que genera HI-TECH C 3.09 (C -S) el
error de CGEN al pasar un char a long ("ld l,(hl)" y enseguida "ld hl,0":
el valor se pierde y queda 0) y dice en que linea del fuente esta. Se
arregla en el fuente con un (uint16_t) antes: (uint32_t)(uint16_t)c."""
import re, sys
bad = 0
for f in sys.argv[1:]:
    src = '?'
    L = open(f, 'rb').read().decode('latin-1').replace('\r', '').split('\n')
    for i, l in enumerate(L):
        if l.startswith(';') and ': ' in l: src = l[1:]
        a = l.split(';')[0].split()
        b = L[i + 1].split(';')[0].split() if i + 1 < len(L) else []
        if len(a) == 2 and a[0] == 'ld' and re.match(r'l,\(', a[1]) and b == ['ld', 'hl,0']:
            print('%s: %s' % (f, src.strip())); bad += 1
print(bad, 'casos')
