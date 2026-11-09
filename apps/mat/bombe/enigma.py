"""enigma.py - reference Enigma I / M3 / M4, the model for examples/enigma.s.

Rotor and reflector wirings from Dirk Rijmenants, "Technical Details of the
Enigma Machine" (as used by Py-Enigma, MIT licence). The tests decrypt real
messages: Operation Barbarossa 1941 (Enigma I), the M4 Project breaks of
U-264 (1942) and Scharnhorst, and the HMS Hurricane intercept.

  python3 enigma.py test
  python3 enigma.py inc ../examples/enigma_data.inc
"""
import sys

A = ord('A')
ROTORS = {   # wiring, turnover letters
    'I': ('EKMFLGDQVZNTOWYHXUSPAIBRCJ', 'Q'),
    'II': ('AJDKSIRUXBLHWTMCQGZNPYFVOE', 'E'),
    'III': ('BDFHJLCPRTXVZNYEIWGAKMUSQO', 'V'),
    'IV': ('ESOVPZJAYQUIRHXLNFTGKDCMWB', 'J'),
    'V': ('VZBRGITYUPSDNHLXAWMJQOFECK', 'Z'),
    'VI': ('JPGVOUMFYQBENHZRDKASXLICTW', 'ZM'),
    'VII': ('NZJHGRCXMYSWBOUFAIVLPEKQDT', 'ZM'),
    'VIII': ('FKQHTLXOCBJSPDZRAMEWNIUYGV', 'ZM'),
    'BETA': ('LEYJVCNIXWPBQMDRTAKZGFUHOS', ''),
    'GAMMA': ('FSOKANUERHMBTIYCWLQPZXVGJD', ''),
}
ORDER = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'BETA', 'GAMMA']
REFLECTORS = {
    'B': 'YRUHQSLDPXNGOKMIEBFZCWVJAT',
    'C': 'FVPJIAOYEDRZXWGCTKUQSBNMHL',
    'B-THIN': 'ENKQAUYWJICOPBLMDXZVFTHRGS',
    'C-THIN': 'RDOBJNTKVEHMLFCWZAXGYIPSUQ',
}
RORDER = ['B', 'C', 'B-THIN', 'C-THIN']


class Enigma:
    def __init__(self, rotors, reflector, rings, plugs=''):
        """rotors left to right (3 for Enigma I/M3, 4 for M4: Greek first)"""
        self.rot = [r.upper() for r in rotors]
        self.refl = REFLECTORS[reflector.upper()]
        self.ring = [ord(c) - A for c in rings.upper()]
        self.pos = [0] * len(self.rot)
        self.plug = list(range(26))
        for p in plugs.upper().split():
            a, b = ord(p[0]) - A, ord(p[1]) - A
            self.plug[a], self.plug[b] = b, a

    def set(self, s):
        self.pos = [ord(c) - A for c in s.upper()]

    def display(self):
        return ''.join(chr(p + A) for p in self.pos)

    def notch(self, i):
        return chr(self.pos[i] + A) in ROTORS[self.rot[i]][1]

    def step(self):
        n = len(self.rot)
        L, M, R = n - 3, n - 2, n - 1
        if self.notch(M):                 # double step
            self.pos[M] = (self.pos[M] + 1) % 26
            self.pos[L] = (self.pos[L] + 1) % 26
        elif self.notch(R):
            self.pos[M] = (self.pos[M] + 1) % 26
        self.pos[R] = (self.pos[R] + 1) % 26

    def press(self, ch):
        self.step()
        c = self.plug[ord(ch) - A]
        n = len(self.rot)
        for i in range(n - 1, -1, -1):    # right to left
            sh = self.pos[i] - self.ring[i]
            c = (ord(ROTORS[self.rot[i]][0][(c + sh) % 26]) - A - sh) % 26
        c = ord(self.refl[c]) - A
        for i in range(n):                # left to right
            sh = self.pos[i] - self.ring[i]
            c = (ROTORS[self.rot[i]][0].index(chr((c + sh) % 26 + A)) - sh) % 26
        return chr(self.plug[c] + A)

    def text(self, s):
        return ''.join(self.press(c) for c in s.upper() if c.isalpha())


# ---------------------------------------------------------------- historical messages
BARBAROSSA = dict(rotors=['II', 'IV', 'V'], reflector='B', rings='BUL',
                  plugs='AV BS CG DL FU HZ IN KM OW RX')
BARB1 = ('WXC', 'KCH',
         'EDPUDNRGYSZRCXNUYTPOMRMBOFKTBZREZKMLXLVEFGUEYSIOZVEQMIKUBPMMYLKLTTDEISMDICAGYKUA'
         'CTCDOMOHWXMUUIAUBSTSLRNBZSZWNRFXWFYSSXJZVIJHIDISHPRKLKAYUPADTXQSPINQMATLPIFSVKDA'
         'SCTACDPBOPVHJK',
         'AUFKLXABTEILUNGXVONXKURTINOWAXKURTINOWAXNORDWESTLXSEBEZXSEBEZXUAFFLIEGERSTRASZER'
         'IQTUNGXDUBROWKIXDUBROWKIXOPOTSCHKAXOPOTSCHKAXUMXEINSAQTDREINULLXUHRANGETRETENXAN'
         'GRIFFXINFXRGTX')
BARB2 = ('CRS', 'YPJ',
         'SFBWDNJUSEGQOBHKRTAREEZMWKPPRBXOHDROEQGBBGTQVPGVKBVVGBIMHUSZYDAJQIROAXSSSNREHYGG'
         'RPISEZBOVMQIEMMZCYSGQDGRERVBILEKXYQIRGIRQNRDNVRXCYYTNJR',
         'DREIGEHTLANGSAMABERSIQERVORWAERTSXEINSSIEBENNULLSEQSXUHRXROEMXEINSXINFRGTXDREIXA'
         'UFFLIEGERSTRASZEMITANFANGXEINSSEQSXKMXKMXOSTWXKAMENECXK')
U264 = dict(rotors=['BETA', 'II', 'IV', 'I'], reflector='B-THIN', rings='AAAV',
            plugs='AT BL DF GJ HM NW OP QY RZ VX')
U264_START = 'VJNA'
U264_CT = ('NCZWVUSXPNYMINHZXMQXSFWXWLKJAHSHNMCOCCAKUQPMKCSMHKSEINJUSBLKIOSXCKUBHMLLXCSJUSRR'
           'DVKOHULXWCCBGVLIYXEOAHXRHKKFVDREWEZLXOBAFGYUJQUKGRTVUKAMEURBVEKSUHHVOYHABCJWMAKL'
           'FKLMYFVNRIZRVVRTKOFDANJMOLBGFFLEOPRGTFLVRHOWOPBEKVWMUQFMPWPARMFHAGKXIIBG')
U264_PT = ('VONVONJLOOKSJHFFTTTEINSEINSDREIZWOYYQNNSNEUNINHALTXXBEIANGRIFFUNTERWASSERGEDRUEC'
           'KTYWABOSXLETZTERGEGNERSTANDNULACHTDREINULUHRMARQUANTONJOTANEUNACHTSEYHSDREIYZWOZ'
           'WONULGRADYACHTSMYSTOSSENACHXEKNSVIERMBFAELLTYNNNNNNOOOVIERYSICHTEINSNULL')


def test():
    m = Enigma(['III', 'II', 'I'], 'B', 'AAA')
    m.set('KDO')
    seen = []
    for _ in range(6):
        m.press('A')
        seen.append(m.display())
    assert seen == ['KDP', 'KDQ', 'KER', 'LFS', 'LFT', 'LFU'], seen
    for start, key, ct, pt in (BARB1, BARB2):
        m = Enigma(**BARBAROSSA)
        m.set(start)
        k = m.text(key)
        m.set(k)
        assert m.text(ct) == pt
        print(f'Barbarossa: {start} {key} -> {k}: OK')
    m = Enigma(**U264)
    m.set(U264_START)
    assert m.text(U264_CT) == U264_PT and m.display() == 'VJWY'
    print('U-264 (M4): OK, final', m.display())
    m = Enigma(['III', 'VI', 'VIII'], 'B', 'AHM', 'AN EZ HK IJ LR MQ OT PV SW UX')
    m.set('UZV')
    assert m.text('ykaenzapmschzbfocuvmrmdpycofhadzizmefxthflolpzlfggbotg'
                  'oxgretdwtjiqhlmxvjwkzuastr') == ('steuerejtanafjordjanstandortquaaacccvierneunneunzwofah'
                                                     'rtzwonulsmxxscharnhorsthco').upper()
    print('Scharnhorst: OK')
    m = Enigma(['BETA', 'VI', 'I', 'III'], 'B-THIN', 'ZZDG', 'BQ CR DI EJ KW MT OS PX UZ GH')
    m.set('NAQL')
    assert m.text('HCEYZTCSOPUPPZDICQRDLWXXFACTTJMBRDVCJJMMZRPYIKHZAWGLYXWTMJPQUEFSZBOTVR'
                  'LALZXWVXTSLFFFAUDQFBWRRYAPSBOWJMKLDUYUPFUQDOWVHAHCDWAUARSWTKOFVOYFPUFH'
                  'VZFDGGPOOVGRMBPXXZCANKMONFHXPCKHJZBUMXJWXKAUODXZUCVCXPFT') == (
        'BOOTKLARXBEIJSCHNOORBETWAZWOSIBENXNOVXSECHSNULCBMXPROVIANTBISZWONULXDE'
        'ZXBENOETIGEGLMESERYNOCHVIEFKLHRXSTEHEMARQUBRUNOBRUNFZWOFUHFXLAGWWIEJKC'
        'HAEFERJXNNTWWWFUNFYEINSFUNFMBSTEIGENDYGUTESIWXDVVVJRASCH')
    print('HMS Hurricane intercept (M4): OK')


def write_inc(path):
    with open(path, 'w') as f:
        f.write('; generated by enigma/enigma.py - wirings (0-25), turnover letters, messages\n')
        f.write('        .segment "RODATA"\n')
        for tab, lab in ((ORDER, 'WIRE'), (RORDER, 'REFL')):
            f.write(f'{lab}:\n')
            for k in tab:
                w = ROTORS[k][0] if lab == 'WIRE' else REFLECTORS[k]
                f.write(f'        .byte   {", ".join(str(ord(c) - A) for c in w)}   ; {k}\n')
        f.write('INVW:\n')
        for k in ORDER:
            w = ROTORS[k][0]
            f.write(f'        .byte   {", ".join(str(w.index(chr(i + A))) for i in range(26))}\n')
        f.write('NOTCH1: .byte   ' + ', '.join(str(ord(ROTORS[k][1][0]) - A) if ROTORS[k][1] else '255'
                                            for k in ORDER) + '\n')
        f.write('NOTCH2: .byte   ' + ', '.join(str(ord(ROTORS[k][1][1]) - A) if len(ROTORS[k][1]) > 1 else '255'
                                            for k in ORDER) + '\n')
        rows = ['QWERTZUIO', 'ASDFGHJK', 'PYXCVBNML']     # the German lampboard
        lr, lc = [0] * 26, [0] * 26
        for r, keys in enumerate(rows):
            for k, ch in enumerate(keys):
                lr[ord(ch) - A] = 9 + 2 * r
                lc[ord(ch) - A] = 6 + 2 * r + 4 * k
        f.write('LAMPR:  .byte   ' + ', '.join(map(str, lr)) + '\n')
        f.write('LAMPC:  .byte   ' + ', '.join(map(str, lc)) + '\n')
        for name, s in (('CT_B1', BARB1[2]), ('CT_B2', BARB2[2]), ('CT_U264', U264_CT)):
            f.write(f'{name}:\n')
            for i in range(0, len(s), 40):
                f.write(f'        .byte   "{s[i:i + 40]}"\n')
            f.write('        .byte   0\n')


if __name__ == '__main__':
    if sys.argv[1] == 'test':
        test()
    elif sys.argv[1] == 'inc':
        write_inc(sys.argv[2])
