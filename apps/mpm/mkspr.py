"""mkspr.py fuente.asm salida.SPR - ensambla con zmac en 0000h y en 0100h y arma
el archivo SPR de MP/M II: 256 bytes de cabecera (bytes 1-2 = largo del codigo),
el codigo y el mapa de reubicacion (un bit por byte, 1 = byte alto a reubicar)."""
import subprocess, sys, os, tempfile
ZMAC = os.environ.get("ZMAC", "zmac")
def asm(src, org, pad=0):
    d = tempfile.mkdtemp()
    p = os.path.join(d, "x.asm")
    open(p, "w").write(f"ORIGEN EQU {org}\nXPAD EQU {pad}\n" + open(src).read())
    r = subprocess.run([ZMAC, "-c", "--od", d, "--oo", "cim,lst", p], capture_output=True, text=True)
    if r.returncode: sys.exit(r.stdout + r.stderr)
    return open(os.path.join(d, "x.cim"), "rb").read(), os.path.join(d, "x.lst")
import re
# GENSYS pone el SPR justo debajo de XDOS (CA00h), alineado a 256: la parte comun
# (desde COMMONBASE) tiene que quedar en C000 o mas arriba, o sea
# redondeo256(largo) - COMMONBASE <= LIMITE. Si el redondeo estorba, se agrega
# relleno (XPAD) en la parte con bancos.
LIMITE = int(os.environ.get("XLIM", "0x900"), 16)   # XDOS en C900 con 5 consolas
def cbase(lst):
    return int(re.search(r"^\s*\d+:\s+([0-9A-F]{4})\s+COMMONBASE:", open(lst).read(), re.M).group(1), 16)
a, lst = asm(sys.argv[1], 0)
pad = 0
if "XPAD" in open(sys.argv[1]).read():
    tot, cb = len(a), cbase(lst)
    comun = tot - cb
    if comun > LIMITE:
        sys.exit(f"la parte comun mide {comun} bytes: no cabe en {LIMITE}")
    while (-(tot + pad)) % 256 > LIMITE - comun:
        pad += 1
    if pad:
        a, lst = asm(sys.argv[1], 0, pad)
b, _ = asm(sys.argv[1], 0x100, pad)
assert len(a) == len(b)
if len(a) % 128 == 0:
    # GENSYS (LDRLWR) reubica mal un modulo cuyo codigo mide un multiplo
    # exacto de 128 bytes (ver gensys.txt del sitio cpm.z80.de): un byte mas.
    a += b"\0"; b += b"\0"
bits = bytearray((len(a) + 7) // 8)
for i, (x, y) in enumerate(zip(a, b)):
    if x != y:
        assert (y - x) & 0xFF == 1, f"byte {i:04X} cambia en {y - x}"
        bits[i // 8] |= 0x80 >> (i % 8)
hdr = bytearray(256); hdr[1] = len(a) & 0xFF; hdr[2] = len(a) >> 8
out = bytes(hdr) + a + bytes(bits)
out += b"\0" * (-len(out) % 128)
open(sys.argv[2], "wb").write(out)
import shutil, re
os.makedirs("zout", exist_ok=True); shutil.copy(lst, "zout/xios.lst"); lst = "zout/xios.lst"
print(f"{sys.argv[2]}: relleno {pad}, comun {len(a)-cbase(lst)} de {LIMITE} bytes")
print(f"{sys.argv[2]}: codigo {len(a)} bytes, {sum(bin(c).count('1') for c in bits)} reubicaciones; listado {lst}")
