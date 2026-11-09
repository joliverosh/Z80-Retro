"""mkspr.py fuente.asm salida.SPR - ensambla con zmac en 0000h y en 0100h y arma
el archivo SPR de MP/M II: 256 bytes de cabecera (bytes 1-2 = largo del codigo),
el codigo y el mapa de reubicacion (un bit por byte, 1 = byte alto a reubicar)."""
import subprocess, sys, os, tempfile
ZMAC = os.environ.get("ZMAC", "zmac")
def asm(src, org):
    d = tempfile.mkdtemp()
    p = os.path.join(d, "x.asm")
    open(p, "w").write(f"ORIGEN EQU {org}\n" + open(src).read())
    r = subprocess.run([ZMAC, "-c", "--od", d, "--oo", "cim,lst", p], capture_output=True, text=True)
    if r.returncode: sys.exit(r.stdout + r.stderr)
    return open(os.path.join(d, "x.cim"), "rb").read(), os.path.join(d, "x.lst")
a, lst = asm(sys.argv[1], 0)
b, _ = asm(sys.argv[1], 0x100)
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
print(f"{sys.argv[2]}: codigo {len(a)} bytes, {sum(bin(c).count('1') for c in bits)} reubicaciones; listado {lst}")
