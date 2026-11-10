#!/bin/bash
# mk.sh [prog...] - compila los programas en C (SDCC) para CP/M y MP/M: prog.c -> PROG.COM
set -e
cd "$(dirname "$0")"
mkdir -p obj
CF="-mz80 --std-sdcc11 ${XCF:---opt-code-size}"
sdasz80 -g -o obj/crt0.rel crt0.s
sdcc $CF -c cpm.c -o obj/cpm.rel
progs="$@"; [ -z "$progs" ] && progs=$(ls *.c | grep -v '^cpm.c$\|^filtro.c$' | sed 's/\.c$//')
for p in $progs; do
  sdcc $CF -c $p.c -o obj/$p.rel
  ex=""; if [ -f ${p}_a.s ]; then sdasz80 -g -o obj/${p}_a.rel ${p}_a.s; ex=obj/${p}_a.rel; fi
  if grep -q crc32.h $p.c; then sdasz80 -g -o obj/crc32_a.rel crc32_a.s; ex="$ex obj/crc32_a.rel"; fi
  sdcc $CF --no-std-crt0 --code-loc 0x0110 --data-loc 0 -o obj/$p.ihx obj/crt0.rel obj/$p.rel $ex obj/cpm.rel
  python3 - obj/$p.ihx ${p^^}.COM <<'Y'
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
