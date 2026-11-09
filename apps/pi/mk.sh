#!/bin/bash
# mk.sh NDIG NOMBRE  ->  NOMBRE.COM
set -e
cd "$(dirname "$0")"
{ echo "NDIG EQU $1"; python3 gen.py $1; } > $2.asm
/home/claude/sim/bin/zmac -c --od zout --oo cim,lst $2.asm
cp zout/$2.cim $2.COM
ls -la $2.COM
