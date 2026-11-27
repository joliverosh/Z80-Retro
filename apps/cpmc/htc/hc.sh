#!/bin/bash
# hc.sh prog... - compila en zemu, bajo ZOS, con HI-TECH C 3.09 (como en la placa):
# prog.c con CPM.LIB -> out/PROG.COM; los filtros de Semilla son s_nombre.
# La salida del compilador en out/log.txt. HTC=carpeta de HI-TECH C, ZOS=zos.bin
set -e
cd "$(dirname "$0")"
HTC=${HTC:-/tmp/pr/z80/por_probar/utilidades/maslin_cpmprog/hitec-c1.lbr_contenido}
ZOS=${ZOS:-/tmp/claude-0/zb/zos/build/zos.bin}
ZEMU=${ZEMU:-/tmp/claude-0/zemu}
MKSD=${MKSD:-/tmp/claude-0/zb/zos/tools/mksd.py}
T=$(mktemp -d); mkdir -p out $T/d
cp $HTC/* $T/d/
crlf() { local n=$(basename "$1" | tr a-z A-Z); sed 's/$/\r/' "$1" > "$T/d/$n"; printf '\x1a' >> "$T/d/$n"; }
for f in hitc.h cpmz.as mklib.sub cpm[0-9]*.c filtro[01f].c s_*.c ../*.h ../cpm.c ../filtro.c ../semilla/*.c; do crlf $f; done
echo '~A>' > $T/g.txt
[ -z "$NOLIB" ] && printf "MKLIB\n~LIBR M CPM.LIB\n~A>\n" >> $T/g.txt
NOOPT=${NOOPT:-"s_awk"}
SINOPC=" od nl rev tac cksum factor calc vida primos hanoi "
if echo " $* " | grep -q ' s_'; then printf 'C -O -C FILTRO1.C\n~A>\nC -O -C FILTRO0.C\n~A>\nC -O -C FILTROF.C\n~A>\n' >> $T/g.txt; fi
for p in "$@"; do
  case $p in
    s_*) n=${p#s_}; lib="FILTRO1.OBJ CPM.LIB"
         case "$SINOPC" in *" $n "*) lib="FILTRO0.OBJ CPM.LIB";; esac
         [ $n = awk ] && lib="FILTROF.OBJ CPM.LIB -LF" ;;
    *) [ -f ../$p.c ] && crlf ../$p.c || { crlf $p; p=$(basename $p .c); }
       lib=${LIBS:-CPM.LIB} ;;
  esac
  o=-O; case " $NOOPT " in *" $p "*) o="";; esac   # sin el optimizador (OPTIM se queda sin memoria)
  printf 'C %s %s %s.C %s\n~A>\n' "$XO" "$o" ${p^^} "$lib" >> $T/g.txt
  [ -n "$UPT" ] && printf 'UPTIME\n~A>\n' >> $T/g.txt
done
python3 $MKSD $T/t.img 24 $T/d/* >/dev/null
timeout ${TMO:-3600} $ZEMU $ZOS -s $T/t.img -i $T/g.txt -E 5 -c ${C:-9000000000000} 2>&1 | tr -d '\r' > out/log.txt || true
python3 - $T/t.img "$@" <<'Y'
import sys, os; sys.path.insert(0,'/tmp/claude-0/zb/zos/tools')
from cpmfs import sd_vdisk
fs=sd_vdisk(bytearray(open(sys.argv[1],'rb').read()),1)
for p in sys.argv[2:]:
    P=os.path.basename(p).replace('.c','').upper()
    try: d=fs.read(P+'.COM'); open('out/'+P+'.COM','wb').write(d); print(P+'.COM', len(d))
    except Exception: print(P+'.COM: no salio'); continue
    try: open('out/'+P+'.MAP','wb').write(fs.read(P+'.MAP'))
    except Exception: pass
Y
rm -rf $T
