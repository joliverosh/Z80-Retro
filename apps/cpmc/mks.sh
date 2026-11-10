#!/bin/bash
# mks.sh [prog...] - los filtros de Semilla (semilla/*.c, sin cambios o casi)
# con filtro.c: opciones y archivos en la linea de ordenes, salida con >ARCH.
set -e
cd "$(dirname "$0")"
mkdir -p obj
CF="-mz80 --std-sdcc11 ${XCF:---opt-code-size}"
# los que no leen una linea de opciones
SINOPC=" od nl rev tac cksum factor calc vida primos hanoi "
sdasz80 -g -o obj/crt0.rel crt0.s
sdcc $CF -c cpm.c -o obj/cpm.rel
progs="$@"; [ -z "$progs" ] && progs=$(cd semilla && ls *.c | sed 's/\.c$//')
for p in $progs; do
  o=1; case "$SINOPC" in *" $p "*) o=0;; esac
  fl=""; grep -q "double\|float" semilla/$p.c && fl="-DFLOATS"
  sdcc $CF -DOPC=$o $fl -c filtro.c -o obj/filtro_$p.rel
  sdcc $CF -I. -Dmain=prog_main -Dexit=fexit -Wp-include,filtro.h -c semilla/$p.c -o obj/s_$p.rel
  sdcc $CF --no-std-crt0 --code-loc 0x0110 --data-loc 0 -o obj/s_$p.ihx obj/crt0.rel obj/s_$p.rel obj/filtro_$p.rel obj/cpm.rel
  python3 - obj/s_$p.ihx ${p^^}.COM <<'Y'
import sys
mem={}
for l in open(sys.argv[1]):
    l=l.strip()
    if not l.startswith(':'): continue
    n=int(l[1:3],16); a=int(l[3:7],16); t=int(l[7:9],16)
    if t==0:
        for i in range(n): mem[a+i]=int(l[9+2*i:11+2*i],16)
hi=max(mem); b=bytes(mem.get(i,0) for i in range(0x100,hi+1))
open(sys.argv[2],'wb').write(b); print(f"{sys.argv[2]}: {len(b)} bytes, hasta {hi:04X}h")
Y
done
