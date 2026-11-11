#!/bin/bash
# mkzcalc.sh - compila ZCALC.COM y ZCALC.OVL (las partes que se cargan cuando hacen falta)
# FAST=1: sin --max-allocs-per-node (prueba rapida)
set -e
cd "$(dirname "$0")"
mkdir -p obj
CF="-mz80 --std-sdcc11 --opt-code-size"
XF="--max-allocs-per-node 200000"; [ -n "$FAST" ] && XF=""
sdasz80 -g -o obj/crt0.rel crt0.s
sdcc $CF -c cpm.c -o obj/cpm.rel
sdasz80 -g -o obj/zcalc_a.rel zcalc_a.s
sdasz80 -g -o obj/znum_a.rel znum_a.s
sdasz80 -g -o obj/zcovh.rel zcovh.s
OV="zcov1 zcov2 zcov3 zcov4 zcov5 zcov6 zcov7 zcov8 zcov9 zcova"
sdcc $CF $XF -c zcalc.c -o obj/zcalc.rel &
sdcc $CF $XF -c znum.c -o obj/znum.rel &
for o in $OV; do sdcc $CF $XF --codeseg OVL --constseg OVL --dataseg OVL -c $o.c -o obj/$o.rel & done
wait
for o in zcalc znum $OV; do [ -f obj/$o.rel ] || { echo "falta obj/$o.rel"; exit 1; }; done
L="sdcc $CF --no-std-crt0 --code-loc 0x0110 --data-loc 0"
$L -o obj/zcalc.ihx obj/crt0.rel obj/zcalc.rel obj/zcalc_a.rel obj/znum_a.rel obj/znum.rel obj/cpm.rel
base=$(awk '/ _ovlreg /{print $1}' obj/zcalc.map)
for o in $OV; do $L -Wl-b_OVL=0x$base -o obj/$o.ihx obj/crt0.rel obj/zcalc.rel obj/zcalc_a.rel obj/znum_a.rel obj/znum.rel obj/zcovh.rel obj/$o.rel obj/cpm.rel; done
python3 - $base $OV <<'Y'
import sys,re
base=int(sys.argv[1],16); ovs=sys.argv[2:]
def ihx(fn):
    mem={}
    for l in open(fn):
        l=l.strip()
        if not l.startswith(':'): continue
        n=int(l[1:3],16); a=int(l[3:7],16); t=int(l[7:9],16)
        if t==0:
            for i in range(n): mem[a+i]=int(l[9+2*i:11+2*i],16)
    return mem
def sym(fn,name):
    for l in open(fn):
        m=re.match(r'\s+([0-9A-F]{8})\s+(\S+)',l)
        if m and m.group(2)==name: return int(m.group(1),16)
osz=None
for l in open('zcalc.h'):
    m=re.match(r'#define OVLSZ (\d+)',l)
    if m: osz=int(m.group(1))
main=ihx('obj/zcalc.ihx'); hi=max(main)
b=bytes(main.get(i,0) for i in range(0x100,hi+1))
open('ZCALC.COM','wb').write(b)
heap=sym('obj/zcalc.map','s__HEAP'); lcode=sym('obj/zcalc.map','l__CODE')
print(f"ZCALC.COM: {len(b)} bytes, hasta {hi:04X}h; ovlreg {base:04X}h ({osz}), heap {heap:04X}h")
hdr=bytearray(b'ZCOVL')+bytes([lcode&255,lcode>>8,heap&255,heap>>8])
body=bytearray(); rec=1
for o in ovs:
    m=ihx(f'obj/{o}.ihx')
    for a,v in main.items():
        if m.get(a)!=v:
            ms=set(l.split()[1] for l in open('obj/zcalc.map') if re.match(r'\s+[0-9A-F]{8}\s+_',l))
            os_=set(l.split()[1] for l in open(f'obj/{o}.map') if re.match(r'\s+[0-9A-F]{8}\s+_',l))
            sys.exit(f"{o}: cambia el programa principal en {a:04X}h; trae de la biblioteca: {sorted(os_-ms-{'_ovl_entry'})}")
    for a in m:
        if a not in main and not (base<=a<base+osz): sys.exit(f"{o}: escribe fuera de su lugar en {a:04X}h")
    ln=sym(f'obj/{o}.map','l__OVL')
    if ln>osz: sys.exit(f"{o}: {ln} bytes, no cabe en {osz}")
    img=bytes(m.get(base+i,0) for i in range(ln))
    nrec=(ln+127)//128
    img=img+bytes(nrec*128-ln)
    hdr+=bytes([rec,nrec]); body+=img; rec+=nrec
    print(f"  {o}: {ln} bytes")
hdr+=bytes(128-len(hdr))
open('ZCALC.OVL','wb').write(bytes(hdr)+bytes(body))
print(f"ZCALC.OVL: {128+len(body)} bytes")
Y
