#!/usr/bin/env python3
"""puentes.py salida.as prefijo [r:] prototipo... - puentes entre la convencion
de HI-TECH C 3.09 y la de SDCC sdcccall(0), para usar con HI-TECH el
ensamblador escrito para SDCC (pasado con sdas2zas.py).

Las dos ponen los argumentos en la pila, de derecha a izquierda, y los saca el
que llama. Cambia:
  - un char: HI-TECH pone 2 bytes, SDCC 1;
  - un long que se devuelve: HI-TECH en HL:DE (HL la parte alta), SDCC en
    DEHL (HL la parte baja);
  - HI-TECH guarda variables en IY y su marco en IX: el puente los guarda.

Con 1: la funcion es del ensamblador y usa sdcccall(1) (registros).
Cada prototipo, como en C: "uint8_t addbcd(uint8_t *a, const uint8_t *b, uint16_t n)".
Sin r: la funcion es del ensamblador (su nombre alli es prefijo+nombre) y la
llama C: el puente se llama _nombre. Con r: la funcion es de C (la compila
HI-TECH) y la llama el ensamblador: el puente se llama prefijo+nombre."""
import re, sys

def size(t):
    t = t.strip()
    if '*' in t: return 2
    t = re.sub(r'\b(const|volatile|register|static|signed)\b', '', t).strip()
    if t in ('uint8_t', 'int8_t', 'char', 'unsigned char', 'bool'): return 1
    if t in ('uint32_t', 'int32_t', 'long', 'unsigned long'): return 4
    if t == 'void': return 0
    return 2

def parse(p):
    m = re.match(r'\s*(.*?)\b(\w+)\s*\((.*)\)\s*;?\s*$', p)
    ret, name, args = m.group(1), m.group(2), m.group(3)
    al = [] if args.strip() in ('', 'void') else [size(re.sub(r'\w+\s*$', '', a) if not a.strip().endswith('*') else a) for a in args.split(',')]
    return size(ret) if '*' not in ret else 2, name, al

def hitech_to_sdcc(name, pref, ret, al):
    """C (HI-TECH) llama a la funcion del ensamblador (SDCC)"""
    o = ['global\t_%s, %s%s' % (name, pref, name), '_%s:' % name,
         'push\tix', 'push\tiy', 'ld\tix,0', 'add\tix,sp']
    off = 6; offs = []
    for s in al: offs.append(off); off += 4 if s == 4 else 2
    n = 0
    for s, of in reversed(list(zip(al, offs))):
        if s == 4:
            o += ['ld\tl,(ix+%d)' % (of + 2), 'ld\th,(ix+%d)' % (of + 3), 'push\thl',
                  'ld\tl,(ix+%d)' % of, 'ld\th,(ix+%d)' % (of + 1), 'push\thl']; n += 4
        elif s == 1:
            o += ['ld\ta,(ix+%d)' % of, 'push\taf', 'inc\tsp']; n += 1
        else:
            o += ['ld\tl,(ix+%d)' % of, 'ld\th,(ix+%d)' % (of + 1), 'push\thl']; n += 2
    o.append('call\t%s%s' % (pref, name))
    if n:
        o += ['exx', 'ld\thl,%d' % n, 'add\thl,sp', 'ld\tsp,hl', 'exx']
    o += ['pop\tiy', 'pop\tix']
    if ret == 4: o.append('ex\tde,hl')
    o.append('ret')
    return o

def hitech_to_sdcc1(name, pref, ret, al):
    """como hitech_to_sdcc, para las de sdcccall(1) (lo de SDCC si no se dice):
    el 1er argumento en A (8 bits) o HL (16), el 2do en L (8, si el 1ro es de
    8) o DE (16); se devuelve en A (8 bits) o DE (16)"""
    o = ['global\t_%s, %s%s' % (name, pref, name), '_%s:' % name,
         'push\tix', 'push\tiy', 'ld\tix,0', 'add\tix,sp']
    if len(al) > 2 or 4 in al: raise SystemExit('sdcccall(1) sin hacer: ' + name)
    if al:
        if al[0] == 1: o.append('ld\ta,(ix+6)')
        else: o += ['ld\tl,(ix+6)', 'ld\th,(ix+7)']
    if len(al) == 2:
        if al[0] == 1 and al[1] == 1: o.append('ld\tl,(ix+8)')
        elif al[1] == 2: o += ['ld\te,(ix+8)', 'ld\td,(ix+9)']
        else: raise SystemExit('sdcccall(1) sin hacer: ' + name)
    o.append('call\t%s%s' % (pref, name))
    if ret == 1: o.append('ld\tl,a')
    elif ret == 2: o.append('ex\tde,hl')
    elif ret == 4: raise SystemExit('sdcccall(1) sin hacer: ' + name)
    o += ['pop\tiy', 'pop\tix', 'ret']
    return o

def sdcc_to_hitech(name, pref, ret, al):
    """el ensamblador (SDCC) llama a una funcion de C (HI-TECH)"""
    o = ['global\t_%s, %s%s' % (name, pref, name), '%s%s:' % (pref, name),
         'push\tix', 'push\tiy', 'ld\tix,0', 'add\tix,sp']
    off = 6; offs = []
    for s in al: offs.append(off); off += s
    n = 0
    for s, of in reversed(list(zip(al, offs))):
        if s == 4:
            o += ['ld\tl,(ix+%d)' % (of + 2), 'ld\th,(ix+%d)' % (of + 3), 'push\thl',
                  'ld\tl,(ix+%d)' % of, 'ld\th,(ix+%d)' % (of + 1), 'push\thl']; n += 4
        elif s == 1:
            o += ['ld\tl,(ix+%d)' % of, 'ld\th,0', 'push\thl']; n += 2
        else:
            o += ['ld\tl,(ix+%d)' % of, 'ld\th,(ix+%d)' % (of + 1), 'push\thl']; n += 2
    o.append('call\t_%s' % name)
    if n:
        o += ['exx', 'ld\thl,%d' % n, 'add\thl,sp', 'ld\tsp,hl', 'exx']
    o += ['pop\tiy', 'pop\tix']
    if ret == 4: o.append('ex\tde,hl')
    o.append('ret')
    return o

if __name__ == '__main__':
    outf, pref = sys.argv[1], sys.argv[2]
    lines = ['; %s - puentes de convencion (los hace htc/puentes.py)' % outf.split('/')[-1], 'psect\ttext']
    for p in sys.argv[3:]:
        k = p[:2] if p[:2] in ('r:', '1:') else ''
        ret, name, al = parse(p[len(k):])
        lines.append('; ' + p[len(k):] + (' (sdcccall 1)' if k == '1:' else ''))
        lines += {'r:': sdcc_to_hitech, '1:': hitech_to_sdcc1, '': hitech_to_sdcc}[k](name, pref, ret, al)
    open(outf, 'w').write('\n'.join(lines) + '\n')
