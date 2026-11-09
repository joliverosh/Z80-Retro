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
    ('Top page', 'FD'), ('Number of TMPs', '#2'), ('Number of Printers', '#1'),
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
