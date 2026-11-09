#!/bin/bash
# mk.sh NDIG NOMBRE [bare]  ->  NOMBRE.COM (CP/M) o NOMBRE.HEX (sin sistema, para L y G 100 en ZLoader)
set -e
cd "$(dirname "$0")"
{ echo "NDIG EQU $1"; python3 gen.py $1 $3; } > $2.asm
/home/claude/sim/bin/zmac -c --od zout --oo cim,hex,lst $2.asm
if [ "$3" = bare ]; then cp zout/$2.hex $2.HEX; ls -la $2.HEX; else cp zout/$2.cim $2.COM; ls -la $2.COM; fi
