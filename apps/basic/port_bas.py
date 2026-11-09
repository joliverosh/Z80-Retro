#!/usr/bin/env python3
"""port_bas.py - pasa los juegos de VELOX BASIC (SBC 6502) a MBASIC-80 (CP/M).

Cambios:
  - quita la primera linea sin numero (titulo para term.py);
  - la semilla de RND salia del contador del monitor 6502 (PEEK(528), PEEK(529)).
    En CP/M no hay contador: se cuenta mientras se espera Enter (lineas 9000-9030)
    y se usa RANDOMIZE;
  - VELOX agrega ELSE, MOD, XOR, &H, EXIT, CALL...: si aparecen, se avisa
    (los seis juegos no los usan);
  - CR LF al final de cada linea y ^Z al final del archivo, como en CP/M.
"""
import re, sys, pathlib
SEED = re.compile(r"X=RND\(-PEEK\(528\)-256\*PEEK\(529\)-1\)")
VELOX = re.compile(r"\b(ELSE|MOD|XOR|EXIT|CALL|TRON|TROFF)\b|&H")
SUB = ['9000 PRINT "(PULSA ENTER)";:S=0',
       '9010 S=S+1:IF S>32000 THEN S=-32000',
       '9020 IF INKEY$="" THEN 9010',
       '9030 PRINT:RANDOMIZE S:RETURN']

def port(src):
    out, seed = [], False
    for l in src.splitlines():
        l = l.rstrip()
        if not l or not l[0].isdigit():
            continue
        if SEED.search(l):
            l, seed = SEED.sub("GOSUB 9000", l), True
        if VELOX.search(re.sub(r'"[^"]*"', '', l)):
            print("  aviso, VELOX:", l, file=sys.stderr)
        l = l.replace(" - SBC 6502", " - Z80-RETRO")
        out.append(l)
    if seed:
        out += SUB
    return "\r\n".join(out) + "\r\n\x1a"

if __name__ == "__main__":
    dst = pathlib.Path(sys.argv[1])
    for f in sys.argv[2:]:
        p = pathlib.Path(f)
        name = re.sub(r"^\d+_", "", p.stem).upper().replace("MANDELBROT", "MANDEL")[:8] + ".BAS"
        (dst / name).write_bytes(port(p.read_text()).encode("ascii"))
        print(name)
