#!/bin/bash
# mkzgpt.sh - ZGPT.COM con el cpm.c reducido (CPM_LITE: sin pf, freadn ni mul16), para
# que quepan los pesos (ZGPT.BIN, 27 KB) y la memoria de K y V en la TPA de MP/M
set -e
cd "$(dirname "$0")"
mkdir -p obj
CF="-mz80 --std-sdcc11 --opt-code-size"
XF="--max-allocs-per-node 50000"; [ -n "$FAST" ] && XF=""
sdasz80 -g -o obj/crt0.rel crt0.s
sdcc $CF -DCPM_LITE -c cpm.c -o obj/cpml.rel
sdasz80 -g -o obj/zgpt_a.rel zgpt_a.s
sdcc $CF $XF -c zgpt.c -o obj/zgpt.rel
sdcc $CF --no-std-crt0 --code-loc 0x0110 --data-loc 0 -o obj/zgpt.ihx obj/crt0.rel obj/zgpt.rel obj/zgpt_a.rel obj/cpml.rel
python3 - obj/zgpt.ihx ZGPT.COM <<'Y'
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
grep -E "s__HEAP" obj/zgpt.map | awk '{print "datos hasta " $1 "h"}'
