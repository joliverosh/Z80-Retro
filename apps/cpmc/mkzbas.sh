#!/bin/bash
# mkzbas.sh - compila ZBAS.COM (el interprete, con los numeros de znum_a.s y znum.c) y
# ZBAS.OVL (zbov1-3.c: las partes que se cargan cuando hacen falta). FAST=1: sin
# --max-allocs-per-node (prueba rapida)
set -e
cd "$(dirname "$0")"
mkdir -p obj
CF="-mz80 --std-sdcc11 --opt-code-size"
XF="--max-allocs-per-node 100000"; [ -n "$FAST" ] && XF=""
sdasz80 -g -o obj/crt0.rel crt0.s
sdcc $CF -DCPM_LITE -c cpm.c -o obj/cpml.rel
sdasz80 -g -o obj/znum_a.rel znum_a.s
sdasz80 -g -o obj/zbovh.rel zbovh.s
sdcc $CF $XF -c znum.c -o obj/znum.rel &
sdcc $CF $XF -c zbas.c -o obj/zbas.rel &
for o in zbovk zbovr zbov1 zbov2 zbov3; do sdcc $CF $XF --codeseg OVL --constseg OVL --dataseg OVL -c $o.c -o obj/$o.rel & done
wait
for o in zbas znum zbovk zbovr zbov1 zbov2 zbov3; do [ -f obj/$o.rel ] || { echo "falta obj/$o.rel"; exit 1; }; done
L="sdcc $CF --no-std-crt0 --code-loc 0x0110 --data-loc 0"
R="obj/crt0.rel obj/zbas.rel obj/znum_a.rel obj/znum.rel"
$L -o obj/zbas.ihx $R obj/cpml.rel
P1="obj/zbov1.rel obj/zbovk.rel obj/zbovr.rel"; P2="obj/zbov2.rel obj/zbovk.rel"; P3="obj/zbov3.rel obj/zbovr.rel"
for p in 1 2 3; do
    eval "o=\$P$p"
    $L -Wl-b_OVL=0xC000 -o obj/p${p}a.ihx $R obj/zbovh.rel $o obj/cpml.rel
    $L -Wl-b_OVL=0xC100 -o obj/p${p}b.ihx $R obj/zbovh.rel $o obj/cpml.rel
done
python3 - <<'P'
import sys,re
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
def syms(fn): return set(l.split()[1] for l in open(fn) if re.match(r'\s+[0-9A-F]{8}\s+_',l))
main=ihx('obj/zbas.ihx'); hi=max(main)
b=bytes(main.get(i,0) for i in range(0x100,hi+1))
open('ZBAS.COM','wb').write(b)
heap=sym('obj/zbas.map','s__HEAP'); lcode=sym('obj/zbas.map','l__CODE')
print(f"ZBAS.COM: {len(b)} bytes, hasta {hi:04X}h; heap {heap:04X}h")
hdr=bytearray(b'ZBOVL')+bytes([lcode&255,lcode>>8,heap&255,heap>>8])
body=b''; rec=1
for p in (1,2,3):
    m0=ihx(f'obj/p{p}a.ihx'); m1=ihx(f'obj/p{p}b.ihx')
    for m,base in ((m0,0xC000),(m1,0xC100)):
        for a,v in main.items():
            if m.get(a)!=v:
                sys.exit(f"parte {p}: cambia el programa principal en {a:04X}h; trae de la biblioteca: {sorted(syms(f'obj/p{p}a.map')-syms('obj/zbas.map'))[:60]}")
        for a in m:
            if a not in main and not (base<=a<base+0x3F00): sys.exit(f"parte {p}: escribe fuera de su lugar en {a:04X}h")
    ln=sym(f'obj/p{p}a.map','l__OVL')
    i0=bytes(m0.get(0xC000+i,0) for i in range(ln)); i1=bytes(m1.get(0xC100+i,0) for i in range(ln))
    rel=[]
    for i in range(ln):
        if i0[i]!=i1[i]:
            if i1[i]!=(i0[i]+1)&255 or not (0xC0<=i0[i]<0xC0+((ln+255)>>8)): sys.exit(f"parte {p}: byte {i:04X}h raro: {i0[i]:02X}/{i1[i]:02X}")
            rel.append(i)
    nir=(ln+127)//128
    img=i0+bytes(nir*128-ln)
    rb=b''.join(bytes([r&255,r>>8]) for r in rel)
    rb+=bytes((-len(rb))%128)
    hdr+=bytes([rec&255,rec>>8,nir&255,nir>>8,len(rel)&255,len(rel)>>8])
    body+=img+rb; rec+=(len(img)+len(rb))//128
    print(f"  parte {p}: {ln} bytes, {len(rel)} direcciones")
hdr+=bytes(128-len(hdr))
open('ZBAS.OVL','wb').write(bytes(hdr)+body)
print(f"ZBAS.OVL: {128+len(body)} bytes")
P
