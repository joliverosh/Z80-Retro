#!/bin/bash
# mk.sh N NOMBRE -> NOMBRE.COM  (PRIMOS hasta N, N <= 10^8)
set -e
cd "$(dirname "$0")"
python3 - $1 > $2.asm <<'P'
import sys, math
n=int(sys.argv[1]); m=(n-1)//2; sq=math.isqrt(n)
print(f"N EQU {n}\nNLO EQU {n & 0xFFFF}\nNHI EQU {n >> 16}\nSQ EQU {sq}\nSEGS EQU {m//16384+1}\nLASTLEN EQU {m%16384+1}")
P
cat primos.asm >> $2.asm
/home/claude/sim/bin/zmac -c --od zout --oo cim,lst $2.asm
cp zout/$2.cim $2.COM; ls -la $2.COM
