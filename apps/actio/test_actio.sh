#!/bin/bash
# test_actio.sh - compila los ejemplos de ACTIO para Z80 y compara con sus .out
AQUI="$(cd "$(dirname "$0")" && pwd)"
SBC6502="${SBC6502:-$HOME/sbc6502}"
RUN="${CPMRUN:-$AQUI/../pi/run/cpmrun}"
mkdir -p "$AQUI/build" && cd "$AQUI/build"
ok=0; mal=0
for f in "$SBC6502"/lang/examples/*.act; do
  n=$(basename "$f" .act); out="${f%.act}.out"; [ -f "$out" ] || continue
  if ! KEEP=1 "$AQUI/actio_z80.sh" "$f" "$n" >/dev/null 2>err.txt; then echo "  FALLA $n (compilar): $(head -3 err.txt)"; mal=$((mal+1)); continue; fi
  inp="${f%.act}.in"; [ -f "$inp" ] || inp=/dev/null
  INPUT="$inp" MAXC=4000000000 "$RUN" "$n.COM" 7.3728 > "$n.txt" 2> "$n.err"
  t=$(grep -o "T = [0-9.]* s" "$n.err")
  if cmp -s "$n.txt" "$out"; then echo "  PASA  $n  ($t a 7,37 MHz)"; ok=$((ok+1)); else echo "  FALLA $n"; mal=$((mal+1)); fi
done
echo "$ok pasan, $mal fallan"
