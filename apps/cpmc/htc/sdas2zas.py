#!/usr/bin/env python3
"""sdas2zas.py entrada.s salida.as [prefijo] - pasa un fuente de sdasz80 (SDCC)
a la sintaxis de ZAS (HI-TECH C 3.09). Las instrucciones son las mismas; cambia
lo de alrededor:
  #n -> n, 0x1F -> 01Fh, n(ix) -> (ix+n), #<x / #>x -> low x / high x,
  .area _CODE/_DATA -> psect text/data, .globl -> global, x:: -> global x + x:,
  .db/.dw/.ds/.ascii -> defb/defw/defs/defm, X = n -> X equ n,
  etiquetas locales 1$ -> unicas.
Con prefijo, las funciones globales que llaman desde C se renombran (_f ->
prefijo + f) para ponerles delante un puente de convencion (ver puentes.py)."""
import re, sys

def num(m):
    return '0' + m.group(1).upper() + 'h'

def expr(s):
    s = re.sub(r'#\s*<\s*\(?([\w+\-]+)\)?', r'low(\1)', s)
    s = re.sub(r'#\s*>\s*\(?([\w+\-]+)\)?', r'high(\1)', s)
    s = s.replace('#', '')
    s = re.sub(r'\b0[xX]([0-9a-fA-F]+)\b', num, s)
    # n(ix) / -n(iy) / (ix)
    s = re.sub(r'(?<![\w)])(-?[\w+\-*]+)\s*\((ix|iy)\)', lambda m: '(%s%s%s)' % (m.group(2), '' if m.group(1).startswith('-') else '+', m.group(1)), s)
    return s

def split_comment(l):
    q = None
    for i, c in enumerate(l):
        if q:
            if c == q: q = None
        elif c in '"\'':
            # 'x' como caracter
            if c == "'" and i + 2 < len(l) and l[i + 2] == "'": q = "'"
            elif c == '"': q = '"'
        elif c == ';':
            return l[:i], l[i:]
    return l, ''

TABLA = re.compile(r'(\n\s*ld\s+a,\s*l\s*(?:;[^\n]*)?\n\s*add\s+a,\s*#<(\w+)\s*(?:;[^\n]*)?\n\s*ld\s+l,\s*a\s*(?:;[^\n]*)?\n\s*ld\s+a,\s*h\s*(?:;[^\n]*)?\n\s*adc\s+a,\s*#>(\w+)\s*(?:;[^\n]*)?\n\s*ld\s+h,\s*a\s*(?:;[^\n]*)?)\n')

def conv(src, pref=None, rename=(), tag='L'):
    # HL += tabla con #< y #>: ZAS no saca bytes de una direccion que se reubica
    src = TABLA.sub(lambda m: '\n\tpush\tbc\t; (HL += %s)\n\tld\tbc,#%s\n\tadd\thl,bc\n\tpop\tbc\n' % (m.group(2), m.group(2)), src)
    out = []; scope = 0; locmap = {}
    def loc(n):
        k = (scope, n)
        if k not in locmap: locmap[k] = '%s%d_%s' % (tag, scope, n)
        return locmap[k]
    for l in src.split('\n'):
        code, com = split_comment(l.rstrip())
        com = com.replace('\t', ' ')
        if not code.strip():
            out.append(com); continue
        m = re.match(r'^(\s*)([A-Za-z_.$][\w.$]*)(::?)\s*(.*)$', code)
        lab = None; gl = False
        if m and not re.match(r'^\s*\.', code):
            lab, gl, code = m.group(2), m.group(3) == '::', m.group(4)
        elif re.match(r'^\s*(\d+)\$:\s*(.*)$', code):
            m2 = re.match(r'^\s*(\d+)\$:\s*(.*)$', code); lab = '%s$' % m2.group(1); code = m2.group(2)
        if lab:
            if lab.endswith('$'):
                lab = loc(lab[:-1])
            else:
                scope += 1
                if lab in rename: lab = pref + lab[1:]
            if gl: out.append('global\t' + lab)
            out.append(lab + ':' + ('\t' + com if com and not code.strip() else ''))
        code = code.strip()
        if not code:
            continue
        code = re.sub(r'\b(\d+)\$', lambda m: loc(m.group(1)), code)
        m = re.match(r'^([A-Za-z_]\w*)\s*=\s*(.*)$', code)
        if m:
            out.append('%s\tequ\t%s\t%s' % (m.group(1), expr(m.group(2)), com)); continue
        m = re.match(r'^\.(\w+)\s*(.*)$', code)
        if m:
            d, a = m.group(1), m.group(2)
            if d == 'module': continue
            if d == 'area':
                ps = 'text' if 'CODE' in a or 'HOME' in a else 'data'
                out.append('psect\t' + ps); continue
            if d == 'globl':
                names = [x.strip() for x in a.split(',')]
                out.append('global\t' + ', '.join(pref + x[1:] if x in rename else x for x in names)); continue
            if d == 'db': out.append('defb\t' + expr(a) + '\t' + com); continue
            if d == 'dw': out.append('defw\t' + expr(a) + '\t' + com); continue
            if d == 'ds': out.append('defs\t' + expr(a) + '\t' + com); continue
            if d in ('ascii', 'str'): out.append('defm\t' + a + '\t' + com); continue
            if d in ('asciz', 'strz'): out.append('defm\t' + a); out.append('defb\t0\t' + com); continue
            raise SystemExit('directiva sin traducir: .' + d)
        m = re.match(r'^(\w+)\s*(.*)$', code)
        op, args = m.group(1), m.group(2)
        args = expr(args)
        for r in rename: args = re.sub(r'\b%s\b' % re.escape(r), pref + r[1:], args)
        out.append(op + ('\t' + args if args else '') + ('\t' + com if com else ''))
    # lo que se usa y no esta aqui: global (ZAS no lo supone)
    defs = set(); uses = set()
    for l in out:
        if l.startswith(';'): continue
        m = re.match(r'^([A-Za-z_$][\w$]*):', l)
        if m: defs.add(m.group(1))
        m = re.match(r'^([A-Za-z_]\w*)\tequ', l)
        if m: defs.add(m.group(1))
        code = split_comment(l)[0]
        if re.match(r'^global\b', code): continue
        for t in re.findall(r'\b(_\w+)', code.split('\t', 1)[1] if '\t' in code else ''): uses.add(t)
    ext = sorted(uses - defs)
    head = ['global\t' + ', '.join(ext[i:i + 6]) for i in range(0, len(ext), 6)]
    return '\n'.join(head + out) + '\n'

if __name__ == '__main__':
    src = open(sys.argv[1]).read()
    pref = sys.argv[3] if len(sys.argv) > 3 else None
    ren = [r for r in sys.argv[4].split(',') if r] if len(sys.argv) > 4 else ()
    tag = sys.argv[5] if len(sys.argv) > 5 else 'L'
    open(sys.argv[2], 'w').write(conv(src, pref, ren, tag))
