#!/bin/bash
# Construye CP/M 3 (con bancos) para la Z80-Retro.
#
# Necesita en el PATH:
#   zmac  - ensamblador Z80 (el mismo de apps/cpm22)
#   zxcc  - emulador de CP/M para ejecutar RMAC, LINK y GENCPM de Digital
#           Research (p. ej. el de RomWBW: Tools/unix/zxcc, o el de John Elliott)
#           Se puede indicar con ZXCC=/ruta/zxcc
#   python3
#
# Resultado (en este directorio):
#   cpm3.sys     - sistema (BDOS + BIOS) generado por GENCPM
#   cpmldr.com   - cargador (CPMLDR de DRI + ldrbios), se carga en 0100h
#   cpmldr.hex   - el mismo cargador en Intel HEX para el comando L de ZLoader
#   cpm3.pkg     - paquete para DOWNLOAD.COM: CPM3.SYS, CCP.COM y utilidades
#                  basicas (DIR, PIP, SHOW, DATE, SET, ...)
#   cpm3dev.pkg  - paquete con las herramientas para regenerar el sistema
#                  en la propia placa (GENCPM, LINK, RMAC, *.SPR, GENCPM.DAT)
#                  y el resto de utilidades de DRI (MAC, ZSID, HELP.HLP...)
set -e
cd "$(dirname "$0")"
ZXCC=${ZXCC:-zxcc}
B=zout/cpm3
rm -rf $B && mkdir -p $B

# 1. Ensamblar los BIOS (Z80) a formato REL
zmac -j --rel7 -I ../../zios --oo rel,lst bios3.asm
zmac -j --rel7 -I ../../zios --oo rel,lst ldrbios.asm

# 2. Herramientas y modulos de DRI en el directorio de trabajo
cp zout/bios3.rel zout/ldrbios.rel $B/
cp dri/cpmldr.asm dri/makedate.lib dri/scb.asm dri/resbdos3.spr dri/bnkbdos3.spr \
   dri/gencpm.com dri/link.com dri/rmac.com gencpm.dat $B/
cd $B
run() { BINDIR80=$PWD/ "$ZXCC" "$@"; }

# 3. CPMLDR = CPMLDR.REL (DRI) + LDRBIOS, cargado en 0100h
run rmac cpmldr '$PZSZ' > rmac_cpmldr.log
run link 'cpmldr[l100]=cpmldr,ldrbios' > link_cpmldr.log
# 4. BNKBIOS3.SPR = BIOS + SCB
run rmac scb '$PZSZ' > rmac_scb.log
run link 'bnkbios3[b]=bios3,scb' > link_bios.log
# 5. CPM3.SYS
run gencpm auto display > gencpm.log
tail -8 gencpm.log
for f in cpmldr.com bnkbios3.spr cpm3.sys; do
  [ -s $f ] || { echo "ERROR: falta $f"; exit 1; }
done
cd ../..
cp $B/cpm3.sys $B/cpmldr.com .
python3 mkpkg.py hex cpmldr.com 0100 > cpmldr.hex
U=dri/util
python3 mkpkg.py pkg cpm3.sys dri/ccp.com $U/DATE.COM $U/DEVICE.COM $U/DIR.COM \
    $U/DUMP.COM $U/ED.COM $U/ERASE.COM $U/GET.COM $U/HELP.COM $U/INITDIR.COM \
    $U/PIP.COM $U/PUT.COM $U/RENAME.COM $U/SAVE.COM $U/SET.COM $U/SETDEF.COM \
    $U/SHOW.COM $U/SUBMIT.COM $U/TYPE.COM > cpm3.pkg
python3 mkpkg.py pkg $B/bnkbios3.spr dri/resbdos3.spr dri/bnkbdos3.spr \
    dri/gencpm.com gencpm.dat dri/link.com dri/rmac.com $U/MAC.COM $U/LIB.COM \
    $U/XREF.COM $U/ZSID.COM $U/GENCOM.COM $U/HEXCOM.COM $U/PATCH.COM \
    $U/HELP.HLP > cpm3dev.pkg
ls -l cpm3.sys cpmldr.com cpmldr.hex cpm3.pkg cpm3dev.pkg
