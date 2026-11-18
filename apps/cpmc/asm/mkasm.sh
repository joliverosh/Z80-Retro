#!/bin/bash
# mkasm.sh [prog...] - arma los programas en ensamblador: asm/prog.z80 -> PROG.COM
# (en apps/cpmc, junto a los de C). Requiere zmac (ZMAC=ruta si no esta en el PATH).
# Sin argumentos arma todos. Los .z80 incluyen zcon.inc, zfile.inc y zmisc.inc.
set -e
cd "$(dirname "$0")"
ZMAC=${ZMAC:-zmac}
mkdir -p obj
progs="$@"; [ -z "$progs" ] && progs=$(ls *.z80 | sed 's/\.z80$//')
for p in $progs; do
  "$ZMAC" --zmac -z --od obj --oo cim,lst $p.z80
  cp obj/$p.cim ../${p^^}.COM
  echo "${p^^}.COM: $(stat -c%s ../${p^^}.COM) bytes"
done
