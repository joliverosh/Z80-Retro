"""gen_data.py - datos de la Enigma y del mensaje para bombe.asm (zmac).
Tablas con renglones de 32 bytes: FW[t][k][x] y BW[t][k][x] para los rotores
I-V (t = 0..4) con el rotor en la posicion k, el reflector B, las muescas y el
mensaje de bombe.py (el parte meteorologico del Mar del Norte)."""
import bombe as B
from enigma import ROTORS, REFLECTORS
A = ord('A')
names = ['I', 'II', 'III', 'IV', 'V']
o = ['; generado por gen_data.py desde bombe.py y enigma.py']
def rows(tab):
    for k in range(26):
        o.append('        DEFB ' + ','.join(str(v) for v in tab[k]) + ',0,0,0,0,0,0')
    for k in range(26, 32):
        o.append('        DEFS 32')
o.append('        ORG ($+255)/256*256')
o.append('FWT:')
for t in names:
    w = [ord(c) - A for c in ROTORS[t][0]]
    rows([[(w[(x + k) % 26] - k) % 26 for x in range(26)] for k in range(26)])
o.append('BWT:')
for t in names:
    w = [ord(c) - A for c in ROTORS[t][0]]; inv = [w.index(i) for i in range(26)]
    rows([[(inv[(x + k) % 26] - k) % 26 for x in range(26)] for k in range(26)])
o.append('REFB:   DEFB ' + ','.join(str(ord(c) - A) for c in REFLECTORS['B']))
o.append('NOTCH:  DEFB ' + ','.join(str(ord(ROTORS[t][1]) - A) for t in names))
o.append('ORDER0: DEFB ' + ','.join(str(names.index(r)) for r in B.KEY['rotors']) + '   ; ' + ' '.join(B.KEY['rotors']))
ct = B.encipher()
o.append(f'CRIBLEN EQU {len(B.CRIB)}')
o.append(f"CRIB:   DEFB '{B.CRIB}'")
o.append('CIPHER:')
for i in range(0, len(ct), 40):
    o.append(f"        DEFB '{ct[i:i+40]}'")
o.append('        DEFB 0')
print('\n'.join(o))
