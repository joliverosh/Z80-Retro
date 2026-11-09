#!/bin/bash
# build.sh - MP/M II para la Z80-Retro:
#   xios.asm -> BNKXIOS.SPR (mkspr.py), GENSYS en cpmsim -> MPM.SYS,
#   ldrbios.asm dentro de MPMLDR.COM, rtc.asm -> RTC.COM y la imagen de flash
#   zloader_sst39sf040_v6_mpm.bin con MP/M en el disco H:.
# Requiere zmac, z80pack ($Z80PACK) y pexpect. Ver LEEME.md.
set -e
cd "$(dirname "$0")"
ZMAC=${ZMAC:-zmac}
export ZMAC
python3 mkspr.py xios.asm BNKXIOS.SPR
python3 gensys.py ${RSPS:-} > gensys.log
grep -q "^MPM.SYS" gensys.log || { cat gensys.log; exit 1; }
# la parte comun del XIOS tiene que quedar en C000 o mas arriba
python3 - <<'C'
import re
base=int(re.findall(r"BNKXIOS SPR  ([0-9A-F]{4})H", open("gensys.log").read())[-1],16)
cb=int(re.search(r"^\s*\d+:\s+([0-9A-F]{4})\s+COMMONBASE:", open("zout/xios.lst").read(), re.M).group(1),16)
print(f"BNKXIOS en {base:04X}H, parte comun desde {base+cb:04X}H (margen {base+cb-0xC000} bytes)")
assert base+cb >= 0xC000, "la parte comun del XIOS empieza debajo de C000"
assert base >= 0x8000, "la parte con bancos tiene que quedar en la ventana 2 (BKCALL)"
C
$ZMAC -c --od zout --oo cim,lst ldrbios.asm >/dev/null
$ZMAC -c --od zout --oo cim,lst rtc.asm >/dev/null && cp zout/rtc.cim RTC.COM
$ZMAC -c --od zout --oo cim,lst zloader.asm >/dev/null && cp zout/zloader.cim ZLOADER.COM
$ZMAC -c --od zout --oo cim,lst baud.asm >/dev/null && cp zout/baud.cim BAUD.COM
$ZMAC -c --od zout --oo cim,lst lstfile.asm >/dev/null && cp zout/lstfile.cim LSTFILE.COM
python3 - <<'P'
m=open('dri/MPMLDR.COM','rb').read(); l=open('zout/ldrbios.cim','rb').read()
o=b'MP/M II V2.0 Loader   '; n=b'MP/M II 2.0 ZEPHYRUS  '   # mismo largo
assert m.count(o)==1 and len(o)==len(n); m=m.replace(o,n)
img=bytearray(m[:0x1600])+l; img+=b'\0'*(0x1800-len(img)); open('MPMLDR.COM','wb').write(img)
# MPMLDR.HEX: el mismo cargador para arrancar MP/M directo desde ZLoader (L + WI + WB)
out=[]
for i in range(0,len(img),32):
    ch=bytes(img[i:i+32]); ad=0x100+i
    rec=bytes([len(ch),ad>>8,ad&255,0])+ch
    out.append(':'+rec.hex().upper()+'%02X'%(-sum(rec)&255))
open('MPMLDR.HEX','w').write('\n'.join(out)+'\n:00000001FF\n')
P
Z=../..
P=prl
# Con el atributo SYS (-s) los programas se ven desde todas las consolas y
# usuarios; los .BAS quedan sin el (-n).
python3 $Z/tools/mkflashdisk.py $Z/zloader/zloader_sst39sf040.bin zloader_sst39sf040_v6_mpm.bin \
  MPMLDR.COM MPM.SYS \
  -s $Z/cpmtools/download.hex $Z/images/cpm22apps.pkg $Z/cpmtools/format.hex \
     $P/ABORT.PRL $P/CONSOLE.PRL $P/DIR.PRL $P/DSKRESET.PRL $P/DUMP.PRL $P/ED.PRL $P/ERA.PRL $P/ERAQ.PRL \
     $P/MPMSTAT.PRL $P/PIP.PRL $P/PRLCOM.PRL $P/REN.PRL $P/SDIR.PRL $P/SET.PRL $P/SHOW.PRL $P/STAT.PRL \
     $P/SUBMIT.PRL $P/TOD.PRL $P/TYPE.PRL $P/USER.PRL $P/SCHED.PRL $P/SPOOL.PRL $P/STOPSPLR.PRL \
     $P/PRINTER.PRL $P/RDT.PRL \
     RTC.COM ZLOADER.COM BAUD.COM LSTFILE.COM $Z/apps/mat/PRIMOS.COM $Z/apps/mat/PRIMOS7.COM $Z/apps/pi/PI1K.COM $Z/apps/mat/bombe/BOMBE.COM \
  -n $Z/apps/basic/bas/*.BAS > flash.log
grep "Disco en flash" flash.log
