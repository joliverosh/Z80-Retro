"""bombe.py - a Turing-Welchman Bombe (with Welchman's diagonal board), the
reference for examples/bombe.s.

Like the real machine it tests one wheel order: for every one of the 17,576
rotor positions it assumes a stecker partner for the test letter, follows the
menu's chain of implications (letter a steckered to x, scrambler at offset i,
so letter b is steckered to S_i(x)), plus the diagonal board (a-x implies
x-a), and stops when the test register shows 1 live wire (the assumption is
consistent) or 25 (the one dead wire is the answer). Ring settings are taken
as AAA and the middle rotor as not turning over inside the crib, as on the
real Bombe.

  python3 bombe.py demo        # cipher the demo message, run the Bombe, check the stops
  python3 bombe.py inc ../examples/bombe_data.inc
"""
import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'enigma'))
from enigma import Enigma, ROTORS, REFLECTORS, ORDER   # noqa: E402

A = ord('A')

# ---------------------------------------------------------------- the demo message
# A weather report enciphered on an Enigma I. The crib is its first 25 letters,
# guessed the way Bletchley did: weather reports were sent every day in the same form.
KEY = dict(rotors=['II', 'V', 'III'], reflector='B', rings='AAA',
           plugs='AQ BJ DV EU FX GR HO KT LW NZ')
START = 'MQW'           # right rotor W: no turnover of the middle rotor inside the crib
PLAIN = ('WETTERVORHERSAGEFUERDIENORDSEEXNEBELBISMITTAGXSICHTZWEIKILOMETERXWIND'
         'NORDWESTVIERXSEEGANGDREIXLUFTDRUCKFALLEND')
CRIB = 'WETTERVORHERSAGEFUERDIENO'


def encipher():
    m = Enigma(**KEY)
    m.set(START)
    return m.text(PLAIN)


# ---------------------------------------------------------------- the scrambler
def tables(order):
    """FW[k][x], BW[k][x] for the right rotor at offset k; core(l, m) -> 26-list"""
    w = [ord(c) - A for c in ROTORS[order[2]][0]]
    inv = [w.index(i) for i in range(26)]
    FW = [[(w[(x + k) % 26] - k) % 26 for x in range(26)] for k in range(26)]
    BW = [[(inv[(x + k) % 26] - k) % 26 for x in range(26)] for k in range(26)]
    return FW, BW


def core(order, l, m):
    """middle rotor at m, left at l, reflector B: the fixed part of the scrambler"""
    wm = [ord(c) - A for c in ROTORS[order[1]][0]]
    wl = [ord(c) - A for c in ROTORS[order[0]][0]]
    ref = [ord(c) - A for c in REFLECTORS['B']]
    out = []
    for x in range(26):
        c = (wm[(x + m) % 26] - m) % 26
        c = (wl[(c + l) % 26] - l) % 26
        c = ref[c]
        c = (wl.index((c + l) % 26) - l) % 26
        c = (wm.index((c + m) % 26) - m) % 26
        out.append(c)
    return out


# ---------------------------------------------------------------- the menu
def menu(crib, cipher):
    """edges per letter: (other letter, crib offset), in offset order; and the test letter"""
    adj = {a: [] for a in range(26)}
    for i, (p, c) in enumerate(zip(crib, cipher)):
        a, b = ord(p) - A, ord(c) - A
        adj[a].append((b, i))
        adj[b].append((a, i))
    test = max(range(26), key=lambda a: (len(adj[a]), -a))
    return adj, test


def loops(crib, cipher):
    """closures in the menu = edges - letters + connected components"""
    adj, _ = menu(crib, cipher)
    seen, comps = set(), 0
    letters = [a for a in range(26) if adj[a]]
    for a in letters:
        if a in seen:
            continue
        comps += 1
        st = [a]
        while st:
            x = st.pop()
            if x in seen:
                continue
            seen.add(x)
            st += [b for b, _ in adj[x]]
    return len(crib) - len(letters) + comps


def propagate(adj, test, x0, FW, BW, M, r):
    """marks reachable from 'test steckered to x0'; None if the test register fills up"""
    mark = set()
    queue = []
    count = 0

    def add(a, x):
        nonlocal count
        for p, q in ((a, x), (x, a)):          # the diagonal board
            if (p, q) not in mark:
                mark.add((p, q))
                queue.append((p, q))
                if p == test:
                    count += 1
        return count < 26

    if not add(test, x0):
        return None, count
    qi = 0
    while qi < len(queue):
        a, x = queue[qi]
        qi += 1
        for b, i in adj[a]:
            k = (r + i + 1) % 26
            if not add(b, BW[k][M[FW[k][x]]]):
                return None, count
    return mark, count


def run(order, crib, cipher, x0=0):
    adj, test = menu(crib, cipher)
    FW, BW = tables(order)
    stops, tests = [], 0
    for l in range(26):
        for m in range(26):
            M = core(order, l, m)
            for r in range(26):
                tests += 1
                mark, count = propagate(adj, test, x0, FW, BW, M, r)
                if mark is None or count not in (1, 25):
                    continue
                st = x0 if count == 1 else next(y for y in range(26) if (test, y) not in mark)
                stops.append((l, m, r, st))
    return stops, test, tests


def deduce(order, crib, cipher, stop):
    """the checking step: propagate from the stop's stecker; consistent? -> plugboard pairs"""
    l, m, r, st = stop
    adj, test = menu(crib, cipher)
    FW, BW = tables(order)
    mark, count = propagate(adj, test, st, FW, BW, core(order, l, m), r)
    if mark is None or count != 1:
        return None
    partner = {}
    for a, x in mark:
        if partner.get(a, x) != x:
            return None
        partner[a] = x
    return partner


def pos(l, m, r):
    return ''.join(chr(v + A) for v in (l, m, r))


def write_inc(path):
    ct = encipher()
    with open(path, 'w') as f:
        f.write('; generated by bombe/bombe.py - the demo message for examples/bombe.s\n')
        f.write('        .segment "RODATA"\n')
        f.write('ORDER0: .byte   ' + ', '.join(str(ORDER.index(r)) for r in KEY['rotors']) + '   ; ' +
                ' '.join(KEY['rotors']) + '\n')
        f.write(f'CRIBLEN = {len(CRIB)}\n')
        f.write(f'CRIB:   .byte   "{CRIB}"\n')
        f.write('CIPHER:\n')
        for i in range(0, len(ct), 40):
            f.write(f'        .byte   "{ct[i:i + 40]}"\n')
        f.write('        .byte   0\n')


def checking(order, crib, cipher_all, stops):
    """what the 6502 prints for each stop: deduced plugs and the start of the decryption"""
    out = []
    for s in stops:
        d = deduce(order, crib, cipher_all[:len(crib)], s)
        if not d:
            out.append((pos(*s[:3]), None, None))
            continue
        pairs = sorted(chr(a + A) + chr(b + A) for a, b in d.items() if a < b)
        m = Enigma(order, 'B', 'AAA', ' '.join(pairs))
        m.set(pos(*s[:3]))
        out.append((pos(*s[:3]), pairs, m.text(cipher_all)))
    return out


if __name__ == '__main__':
    if sys.argv[1] == 'inc':
        write_inc(sys.argv[2])
    elif sys.argv[1] == 'demo':
        ct = encipher()
        print('ciphertext:', ct)
        print('menu loops:', loops(CRIB, ct[:len(CRIB)]), ' test letter:', chr(menu(CRIB, ct)[1] + A))
        import time
        t0 = time.time()
        stops, test, n = run(KEY['rotors'], CRIB, ct[:len(CRIB)])
        print(f'{n} positions, {len(stops)} stops, {time.time() - t0:.1f} s')
        for s in stops:
            d = deduce(KEY['rotors'], CRIB, ct[:len(CRIB)], s)
            print(' ', pos(*s[:3]), chr(test + A) + '-' + chr(s[3] + A), 'consistent' if d else 'contradiction',
                  ' '.join(sorted(chr(a + A) + chr(b + A) for a, b in d.items() if a < b)) if d else '')
