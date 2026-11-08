#!/usr/bin/env python3
"""Utilidades de empaquetado para CP/M 3 en la Z80-Retro.

  mkpkg.py hex FICHERO ORIGEN      -> Intel HEX (para el comando L de ZLoader)
  mkpkg.py pkg FICHERO...          -> paquete para DOWNLOAD.COM (mismo formato
                                      que tools/bin2cpmhex.js)
"""
import os
import sys


def ihex(data, org):
    out = []
    for off in range(0, len(data), 32):
        chunk = data[off:off + 32]
        addr = org + off
        rec = bytes([len(chunk), addr >> 8, addr & 0xFF, 0]) + chunk
        cs = (-sum(rec)) & 0xFF
        out.append(':' + rec.hex().upper() + '%02X' % cs)
    out.append(':00000001FF')
    return '\n'.join(out) + '\n'


def pkg(paths, user=0):
    out = []
    for p in paths:
        data = open(p, 'rb').read()
        name = os.path.basename(p).upper()
        out.append('A:DOWNLOAD %s\n\nU%X\n:' % (name, user))
        for off in range(0, len(data), 45):
            out.append(data[off:off + 45].hex().upper() + '\n')
        out.append('>%02X%02X\n' % (len(data) & 0xFF, sum(data) & 0xFF))
    return ''.join(out)


if __name__ == '__main__':
    if len(sys.argv) >= 4 and sys.argv[1] == 'hex':
        sys.stdout.write(ihex(open(sys.argv[2], 'rb').read(), int(sys.argv[3], 16)))
    elif len(sys.argv) >= 3 and sys.argv[1] == 'pkg':
        sys.stdout.write(pkg(sys.argv[2:]))
    else:
        sys.exit(__doc__)
