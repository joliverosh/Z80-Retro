"""ibm3740.py - lista y extrae archivos de una imagen de disco CP/M de 8" SD (IBM 3740)."""
import sys, os
SKEW=[1,7,13,19,25,5,11,17,23,3,9,15,21,2,8,14,20,26,6,12,18,24,4,10,16,22]
def read_img(p): return open(p,'rb').read()
def sector(img, lsec):          # sector logico desde la pista 2
    t, s = divmod(lsec, 26); t += 2; ps = SKEW[s]-1
    off = (t*26+ps)*128
    return img[off:off+128]
def block(img, b): return b''.join(sector(img, b*8+i) for i in range(8))
def dirents(img):
    d=b''.join(sector(img,i) for i in range(16))
    for i in range(64):
        e=d[i*32:i*32+32]
        if e[0]==0xE5: continue
        yield e
def files(img):
    fs={}
    for e in dirents(img):
        name=(e[1:9].decode('latin1').rstrip()+'.'+bytes(c&0x7f for c in e[9:12]).decode().rstrip()).upper()
        user=e[0]; ex=e[12]+32*e[14]; rc=e[15]
        blocks=[b for b in e[16:32] if b]
        fs.setdefault((user,name),[]).append((ex,rc,blocks))
    out={}
    for k,ents in fs.items():
        ents.sort(); data=b''
        for ex,rc,blocks in ents:
            chunk=b''.join(block(img,b) for b in blocks)
            data=data[:ex*16384] if False else data
            data+=chunk[:rc*128] if ex==ents[-1][0] else chunk[:16384]
        out[k]=data
    return out
def write_img(files, path):
    """files: lista de (nombre, datos). Imagen nueva con 77 pistas."""
    img=bytearray(b'\xe5'*(77*26*128))
    def wsec(lsec, data):
        t, s = divmod(lsec, 26); t += 2; ps = SKEW[s]-1
        off=(t*26+ps)*128; img[off:off+128]=data.ljust(128,b'\x1a')
    d=bytearray(b'\xe5'*2048); nb=2; de=0
    for name,data in files:
        n,_,e=name.upper().partition('.')
        recs=(len(data)+127)//128 or 1
        data=data.ljust(recs*128,b'\x1a')
        ext=0; pos=0
        while pos < len(data) or ext==0:
            chunk=data[pos:pos+16384]; crecs=(len(chunk)+127)//128
            blocks=[]
            for i in range(0,len(chunk),1024):
                b=chunk[i:i+1024]
                for j in range(0,len(b),128): wsec(nb*8+j//128, b[j:j+128])
                blocks.append(nb); nb+=1
            if nb>243: raise SystemExit('disco lleno')
            ent=bytes([0])+n.ljust(8).encode()+e.ljust(3).encode()+bytes([ext&31,0,ext>>5,crecs])+bytes(blocks).ljust(16,b'\0')
            d[de*32:de*32+32]=ent; de+=1; ext+=1; pos+=16384
            if pos>=len(data): break
    for i in range(16): wsec(i, bytes(d[i*128:i*128+128]))
    open(path,'wb').write(img)

if __name__=='__main__':
    img=read_img(sys.argv[1]); dst=sys.argv[2] if len(sys.argv)>2 else None
    for (u,n),d in sorted(files(img).items()):
        print(f"{u:2d} {n:12s} {len(d):6d}")
        if dst: open(os.path.join(dst,n),'wb').write(d)
