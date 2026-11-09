"""gensys.py - corre GENSYS de MP/M II dentro de cpmsim (z80pack, de Udo Munk)
con las respuestas de la Z80-Retro y saca MPM.SYS. Uso: python3 gensys.py [RSP...]
Requiere z80pack compilado ($Z80PACK, por omision ~/z80pack: cpmsim/srcsim y
cpmsim/srctools con make) y pexpect (pip install pexpect)."""
import pexpect, sys, os, re, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ibm3740 as I
SIM = os.path.join(os.environ.get('Z80PACK', os.path.expanduser('~/z80pack')), 'cpmsim')
D2 = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'dri')
rsps = [r.upper() for r in sys.argv[1:]]
files = [('GENSYS.COM', open(f'{D2}/GENSYS.COM','rb').read())]
for f in ['RESBDOS.SPR','XDOS.SPR','BNKBDOS.SPR','BNKXDOS.SPR','TMP.SPR']:
    d = open(f'{D2}/{f}','rb').read()
    if f == 'XDOS.SPR':
        # Parche: todas las consolas arrancan en el usuario 0 (DRI pone
        # tmp$pd.disk$slct = numero de consola, asi la B arranca en 1A>).
        # mpm.asm:  LXI H,0EH / DAD D / MOV M,B / LXI H,16H / DAD D / MOV M,B
        # pasa a    LXI H,0EH / DAD D / MOV M,B / LXI B,8   / DAD B / MOV M,B
        # (B = 0, HL = PD+16H). B no se vuelve a usar; nada que relocalizar.
        old = bytes([0x21,0x0e,0,0x19,0x70, 0x21,0x16,0,0x19,0x70])
        new = bytes([0x21,0x0e,0,0x19,0x70, 0x01,0x08,0,0x09,0x70])
        assert d.count(old) == 1, 'XDOS.SPR: no encuentro el TMP disk$slct'
        d = d.replace(old, new)
        # Parche: el mensaje de arranque dice que es la version para ZEPHYRUS
        # (mismo largo, 56 bytes; el texto no lleva bits de reubicacion).
        old = b'\r\n\nMP/M II V2.0\r\nCopyright (C) 1981, Digital Research\r\n$'
        new = b'\r\nMP/M II 2.0 ZEPHYRUS 1.4\r\n(C) 1981 Digital Research\r\n$'
        assert d.count(old) == 1 and len(old) == len(new), 'XDOS.SPR: no encuentro el mensaje'
        d = d.replace(old, new)
        # Parche: el retorno de los programas (lo que hay en su pila al empezar)
        # guarda AF BC DE HL antes de llamar a la funcion 143 (terminar). La pila
        # inicial del programa es la de su segmento de memoria en XDOS (20 bytes,
        # una tras otra) y al terminar se bajaba 24: pisaba la direccion de retorno
        # del segmento de abajo, y si ese programa terminaba despues con RET (como
        # DUMP), saltaba a cualquier parte. Terminar no vuelve: sin PUSH ni POP.
        m = re.search(rb'\xf5\xc5\xd5\xe5\x0e\x8f\x11\x00\x00\xcd..\xe1\xd1\xc1\xf1\xc9', d, re.S)
        assert m, 'XDOS.SPR: no encuentro el retorno a terminar'
        i = m.start()
        d = d[:i] + b'\0\0\0\0' + d[i+4:i+12] + b'\0\0\0\0' + d[i+16:]
    files.append((f, d))
files.append(('BNKXIOS.SPR', open('BNKXIOS.SPR','rb').read()))
for r in rsps:
    for ext in ('RSP','BRS'):
        p=f'{D2}/{r}.{ext}'
        if os.path.exists(p): files.append((f'{r}.{ext}', open(p,'rb').read()))
os.makedirs('/tmp/gs', exist_ok=True)
shutil.copy(f'{SIM}/disks/library/cpm22-1.dsk', '/tmp/gs/drivea.dsk')
I.write_img(files, '/tmp/gs/driveb.dsk')
ANS = [  # (texto de la pregunta, respuesta)
    ('Top page', 'FD'), ("Number of TMPs", "#5"), ('Number of Printers', '#1'),
    ('Breakpoint RST', '07'), ('system call user stacks', 'Y'), ('Z80 CPU', 'Y'),
    ('ticks/second', '#60'), ('System Drive', 'H:'), ('Temporary file drive', 'A:'),
    ('locked records/process', ''), ('Total locked records', ''), ('open files/process', ''),
    ('Total open files', ''), ('Bank switched memory', 'Y'), ('user memory segments', '#7'),
    ('Common memory base page', 'C0'), ('Dayfile logging', 'N'),
    ('Accept new system data', 'Y'), ('Accept new memory segment', 'Y'),
]
p = pexpect.spawn(f'{SIM}/cpmsim', ['-d','/tmp/gs'], cwd=SIM, encoding='latin1', timeout=60,
                  env={'PATH': os.path.join(SIM, 'srctools') + ':/usr/bin:/bin'})
p.expect('A>'); p.send('b:\r'); p.expect('B>'); p.send('gensys\r')
log=''; seg=0
while True:
    k = p.expect([r'\? $', r'\? ', r'B>', pexpect.TIMEOUT], timeout=20)
    txt = p.before + (p.after if isinstance(p.after,str) else '')
    log += txt
    if k >= 2: break
    last = txt.strip().splitlines()[-1] if txt.strip() else ''
    a = None
    for q, r in ANS:
        if q in last: a = r; break
    if a is None and re.search(r'RSP \(N\)', last):
        a = 'Y' if last.split()[0] in rsps else 'N'
    if a is None and 'Base,size,attrib,bank' in last:
        a = ''
    if a is None: a = ''
    p.send(a + '\r'); log += a
print(log)
p.send('bye\r')
try: p.expect(pexpect.EOF, timeout=5)
except Exception: pass
out = I.files(I.read_img('/tmp/gs/driveb.dsk'))
if (0,'MPM.SYS') in out:
    open('MPM.SYS','wb').write(out[(0,'MPM.SYS')]); print('MPM.SYS', len(out[(0,'MPM.SYS')]))
else:
    print('sin MPM.SYS')
