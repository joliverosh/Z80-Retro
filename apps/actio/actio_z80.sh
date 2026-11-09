#!/bin/bash
# actio_z80.sh PROG.act [SALIDA]  ->  SALIDA.COM para CP/M en la Z80-Retro
# Usa el COMPILATOR del repositorio sbc6502 ($SBC6502, por omision ~/sbc6502)
# y traduce su salida 6502 a Z80 con z80back.py. Requiere zmac.
set -e
AQUI="$(cd "$(dirname "$0")" && pwd)"
SBC6502="${SBC6502:-$HOME/sbc6502}"
ZMAC="${ZMAC:-zmac}"
SRC="$1"; BASE="${2:-$(basename "${SRC%.*}" | tr a-z A-Z | cut -c1-8)}"
TMP=$(mktemp -d)
python3 "$SBC6502/lang/compiler.py" "$SRC" -o "$TMP/p.s"
python3 "$AQUI/z80back.py" "$TMP/p.s" -o "$TMP/p.z80"
cp "$AQUI/z80rt.inc" "$TMP/"
( cd "$TMP" && "$ZMAC" -c --od zout --oo cim,lst p.z80 >/dev/null )
cp "$TMP/zout/p.cim" "$BASE.COM"
[ -n "$KEEP" ] && cp "$TMP/p.z80" "$BASE.z80"
rm -rf "$TMP"
ls -la "$BASE.COM"
