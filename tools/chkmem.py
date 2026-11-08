#!/usr/bin/env python3
# Comprueba en el mapa del enlazador (zloader/build.log) que nada se pise:
#  - codigo de ZLoader por debajo de sus datos (3600)
#  - datos de ZLoader por debajo del buffer de historia (3C00-3FFF)
#  - codigo de ZIOS dejando al menos 256 bytes de pila bajo FE00
import re, sys
log = open(sys.argv[1] if len(sys.argv) > 1 else 'build.log').read()
mal = False
for a, n, t, m in re.findall(r'^([0-9a-f]{4})\s+([0-9a-f]{4})\s+([PD])\s+-\s+(\S+)', log, re.M):
    a, n = int(a, 16), int(n, 16)
    fin = a + n
    if a < 0x4000 and t == 'P' and fin > 0x3600:
        print('Codigo de ZLoader pisa sus datos (3600):', m, hex(fin)); mal = True
    if a < 0x4000 and t == 'D' and fin > 0x3C00:
        print('Datos de ZLoader pisan el historial (3C00):', m, hex(fin)); mal = True
    if 0xC500 <= a < 0xFE00 and t == 'P' and fin > 0xFD00:
        print('ZIOS deja menos de 256 bytes de pila bajo FE00:', m, hex(fin)); mal = True
    if 0x9000 <= a < 0xC000 and t == 'P' and fin > 0xBFF0:
        print('El overlay (pagina 02 de la flash) pisa la cabecera del disco en flash (BFF0):', m, hex(fin)); mal = True
sys.exit(1 if mal else 0)
