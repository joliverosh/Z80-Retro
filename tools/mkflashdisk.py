#!/usr/bin/env python3
"""mkflashdisk.py - arma el disco en flash de la Z80-Retro (unidad H: de CP/M)
dentro de la imagen de 512 KB de la SST39SF040.

Uso:
  mkflashdisk.py ENTRADA.bin SALIDA.bin [ARCHIVOS o PAQUETES .pkg ...]

  - ENTRADA.bin: imagen de ZLoader (zloader_sst39sf040.bin)
  - Si un nombre se repite, gana el ultimo.
  - -uN: los archivos que siguen van al area de usuario N (por omision 0).
  - -s / -n: los archivos que siguen llevan (o no) el atributo SYS (para MP/M:
    los de la unidad del sistema con SYS se ven desde todas las unidades).
  - Los .pkg son paquetes de DOWNLOAD.COM (como images/cpm22apps.pkg); los
    .hex con formato Intel se convierten en .COM (cargados desde 0100h); los
    demas archivos se copian tal cual.

Formato (igual que el que espera ZIOS, zios/memdsk.asm): paginas de flash
03-1F (hasta 464 KB), bloques de 2 KB, 128 entradas de directorio en los
bloques 0 y 1, sin pistas reservadas, usuario 0. Cabecera "FLSHDSK1" + numero
de paginas en la pagina 02, desplazamiento 3FF0 (despues del juego de
caracteres de 8000-8FFF, que no se toca).
"""
import sys, os

PG = 16384
PG0 = 3
PGMAX = 29
BLK = 2048
DIRBLK = 2
DIRENT = 128

def unpack_pkg(text):
    files = []
    lines = [l.strip() for l in text.replace('\r', '\n').split('\n')]
    i = 0
    while i < len(lines):
        l = lines[i]
        if l.upper().startswith('A:DOWNLOAD '):
            name = l[11:].strip().upper()
            i += 1
            hexdata = ''
            while i < len(lines) and not lines[i].startswith('>'):
                s = lines[i]
                if s.startswith(':'):
                    s = s[1:]
                if not s.upper().startswith('U') or hexdata:
                    hexdata += s
                i += 1
            data = bytes.fromhex(hexdata)
            if i < len(lines):
                chk = lines[i][1:]
                ln, cs = int(chk[:2], 16), int(chk[2:4], 16)
                if (len(data) & 0xFF) != ln or (sum(data) & 0xFF) != cs:
                    sys.exit(f"{name}: longitud o suma del paquete no coinciden")
            files.append((name, data))
        i += 1
    return files

def hex2com(text):
    mem = {}
    for l in text.splitlines():
        l = l.strip()
        if not l.startswith(':'):
            continue
        b = bytes.fromhex(l[1:])
        n, a, t = b[0], (b[1] << 8) | b[2], b[3]
        if t == 0:
            for k in range(n):
                mem[a + k] = b[4 + k]
    lo, hi = 0x100, max(mem) + 1
    return bytes(mem.get(a, 0) for a in range(lo, hi))

def cpmname(name):
    base, _, ext = name.upper().partition('.')
    if not base or len(base) > 8 or len(ext) > 3:
        sys.exit(f"Nombre no valido para CP/M: {name}")
    return base.ljust(8).encode(), ext.ljust(3).encode()

def build(files, pages):
    # files: lista de (usuario, nombre, datos)
    dsm = pages * PG // BLK - 1
    if dsm > 255:
        sys.exit("demasiadas paginas")
    disk = bytearray(b'\xE5' * (pages * PG))
    nextblk = DIRBLK
    entries = []
    for user, name, data, sysat in files:
        recs = (len(data) + 127) // 128
        data = data + b'\x1A' * (recs * 128 - len(data))
        n8, e3 = cpmname(name)
        if sysat:
            e3 = bytes([e3[0], e3[1] | 0x80, e3[2]])
        ent = 0
        left = recs
        while True:
            r = min(256, left)
            nblk = (r + 15) // 16
            blks = list(range(nextblk, nextblk + nblk))
            if blks and blks[-1] > dsm:
                sys.exit(f"No cabe {name}: el disco en flash es de {pages * 16} KB")
            off = (recs - left) * 128
            for k, b in enumerate(blks):
                chunk = data[off + k * BLK: off + (k + 1) * BLK]
                disk[b * BLK: b * BLK + len(chunk)] = chunk
            nextblk += nblk
            if r > 128:
                ex, rc = 2 * ent + 1, r - 128
            else:
                ex, rc = 2 * ent, r
            al = bytes(blks) + bytes(16 - len(blks))
            entries.append(bytes([user]) + n8 + e3 + bytes([ex, 0, 0, rc]) + al)
            left -= r
            ent += 1
            if left <= 0:
                break
    if len(entries) > DIRENT:
        sys.exit("Demasiadas entradas de directorio")
    for k, e in enumerate(entries):
        disk[k * 32:(k + 1) * 32] = e
    used = nextblk * BLK
    return disk, used, dsm

def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    img = bytearray(open(sys.argv[1], 'rb').read())
    if len(img) != 524288:
        sys.exit("La imagen de entrada debe ser de 512 KB")
    files = []
    user = 0
    sysat = False
    for f in sys.argv[3:]:
        if f.startswith('-u'):
            user = int(f[2:])
            continue
        if f in ('-s', '-n'):
            sysat = f == '-s'
            continue
        raw = open(f, 'rb').read()
        if f.lower().endswith('.pkg'):
            files += [(user, n, d, sysat) for n, d in unpack_pkg(raw.decode('latin-1'))]
        elif f.lower().endswith('.hex'):
            files.append((user, os.path.basename(f)[:-4] + '.COM', hex2com(raw.decode('latin-1')), sysat))
        else:
            files.append((user, os.path.basename(f), raw, sysat))
    # Si un archivo se repite gana el ultimo (p. ej. un FORMAT.COM nuevo
    # despues del paquete)
    final = {}
    for u, n, d, sa in files:
        final[(u, n.upper())] = (d, sa)
    files = [(u, n, d, sa) for (u, n), (d, sa) in final.items()]
    # Paginas libres de la flash a partir de la 03 (lo que haya en 03-1F se pisa)
    if any(b != 0xFF for b in img[PG0 * PG:]):
        print("Aviso: habia datos en la flash despues de la pagina 02; se reemplazan")
    disk, used, dsm = build(files, PGMAX)
    img[PG0 * PG:(PG0 + PGMAX) * PG] = disk
    hdr = b'FLSHDSK1' + bytes([PGMAX]) + b'\x00' * 7
    img[2 * PG + 0x3FF0: 2 * PG + 0x4000] = hdr
    open(sys.argv[2], 'wb').write(img)
    print(f"Disco en flash: {len(files)} archivos, {used // 1024} KB usados de "
          f"{(dsm + 1) * 2} KB (DSM={dsm})")
    for u, n, d, _sa in files:
        print(f"  {u:2d}:{n:12s} {len(d):7d}")

if __name__ == '__main__':
    main()
