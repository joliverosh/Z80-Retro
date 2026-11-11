#!/usr/bin/env python3
# mkzdb.py: arma ZDB.COM = cargador + ZDB (ensamblado en 0) + mapa de reubicacion.
# ZDB se ensambla en 0000h y en 0100h; los bytes que difieren (en 1) son
# bytes altos de direcciones y se marcan en el mapa.
import subprocess, sys, os
ZMAC = os.environ.get('ZMAC', 'zmac')
def zm(src):
    r = subprocess.run([ZMAC, '-c', '--od', 'zout', '--oo', 'cim,lst', src], capture_output=True, text=True)
    out = r.stdout + r.stderr
    if r.returncode or 'error' in out.lower():
        sys.exit(out)
    return open('zout/' + os.path.splitext(os.path.basename(src))[0] + '.cim', 'rb').read()
for b, f in ((0, 'zdb0.asm'), (0x100, 'zdb1.asm')):
    open(f, 'w').write(f'RBASE EQU {b}\n        INCLUDE zdb.asm\n')
a = zm('zdb0.asm'); b = zm('zdb1.asm')
assert len(a) == len(b), (len(a), len(b))
bits = bytearray((len(a) + 7) // 8)
n = 0
for i, (x, y) in enumerate(zip(a, b)):
    if x != y:
        assert (y - x) & 0xFF == 1, f'byte {i:04X}: {x:02X} {y:02X}'
        bits[i >> 3] |= 0x80 >> (i & 7); n += 1
npg = (len(a) + 255) // 256
open('zdbsz.inc', 'w').write(f'ISZ EQU {len(a)}\nNPG EQU {npg}\n')
ldr = zm('zdbldr.asm')
com = ldr + a + bits
com += b'\x1a' * (-len(com) % 128)
open('ZDB.COM', 'wb').write(com)
for f in ('zdb0.asm', 'zdb1.asm'): os.remove(f)
print(f'ZDB.COM: {len(com)} bytes (ZDB {len(a)} bytes, {npg} paginas, {n} reubicaciones)')
