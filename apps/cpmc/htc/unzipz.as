; unzipz.as - de unzip_a.s (sdas2zas.py) y sus puentes (puentes.py); no se edita
global	_bitbuf, _bitn, _zerr
;; unzip_a.s - la lectura de bits y la decodificacion de Huffman de UNZIP
;; (como tinf: un bit cada vez, pero sin llamadas). sdcccall(0).
global	S_bit
global	S_bits
global	S_decode
global	S_getb
global	_bitbuf
global	_bitn
global	_zerr
psect	text
; el siguiente bit al acarreo (no toca BC DE IX)
nbit:
ld	a,(_bitn)
or	a
jr	nz,UNZ1_00001
push	bc
push	de
push	ix
call	S_getb
pop	ix
pop	de
pop	bc
ld	a,l
ld	(_bitbuf),a
ld	a,8
UNZ1_00001:
dec	a
ld	(_bitn),a
ld	hl,_bitbuf
srl	(hl)
ret
; uint8_t bit(void)
global	S_bit
S_bit:
call	nbit
ld	a,0
rla
ld	l,a
ret
; uint16_t bits(uint8_t n): n bits, el primero el bajo
global	S_bits
S_bits:
ld	hl,2
add	hl,sp
ld	a,(hl)
ld	de,0
ld	bc,1
or	a
jr	z,UNZ3_00012
UNZ3_00011:
push	af
call	nbit
jr	nc,UNZ3_00013
ld	a,e
or	c
ld	e,a
ld	a,d
or	b
ld	d,a
UNZ3_00013:
sla	c
rl	b
pop	af
dec	a
jr	nz,UNZ3_00011
UNZ3_00012:
ex	de,hl
ret
; uint16_t decode(TREE *t): t->cnt[16] y despues t->sym[288]
global	S_decode
S_decode:
ld	hl,2
add	hl,sp
ld	a,(hl)
inc	hl
ld	h,(hl)
ld	l,a
push	ix
push	hl
pop	ix
push	hl	; t, para el final
ld	de,0	; sum
ld	bc,0	; cur
ld	a,15
ld	(dcnt),a
UNZ4_00021:
call	nbit
rl	c
rl	b	; cur = 2 cur + bit
inc	ix
inc	ix	; ix -> cnt[len]
ld	l,(ix+0)
ld	h,(ix+1)
ex	de,hl
add	hl,de	; sum += cnt[len]
ex	de,hl
ld	a,c
sub	l
ld	c,a
ld	a,b
sbc	a,h
ld	b,a	; cur -= cnt[len]
jp	m,UNZ4_00022
ld	hl,dcnt
dec	(hl)
jr	nz,UNZ4_00021
ld	a,1	; mas de 15 bits: datos malos
ld	(_zerr),a
pop	hl
pop	ix
ld	hl,0
ret
UNZ4_00022:
ld	l,e
ld	h,d
add	hl,bc	; sum + cur
add	hl,hl
pop	de
add	hl,de
ld	de,32
add	hl,de
ld	a,(hl)
inc	hl
ld	h,(hl)
ld	l,a
pop	ix
ret
psect	data
dcnt:
defs	1	

; z2.21293 - puentes de convencion (los hace htc/puentes.py)
psect	text
; uint8_t bit(void)
global	_bit, S_bit
_bit:
push	ix
push	iy
ld	ix,0
add	ix,sp
call	S_bit
pop	iy
pop	ix
ret
; uint16_t bits(uint8_t n)
global	_bits, S_bits
_bits:
push	ix
push	iy
ld	ix,0
add	ix,sp
ld	a,(ix+6)
push	af
inc	sp
call	S_bits
exx
ld	hl,1
add	hl,sp
ld	sp,hl
exx
pop	iy
pop	ix
ret
; uint16_t decode(TREE *t)
global	_decode, S_decode
_decode:
push	ix
push	iy
ld	ix,0
add	ix,sp
ld	l,(ix+6)
ld	h,(ix+7)
push	hl
call	S_decode
exx
ld	hl,2
add	hl,sp
ld	sp,hl
exx
pop	iy
pop	ix
ret
; uint8_t getb(void)
global	_getb, S_getb
S_getb:
push	ix
push	iy
ld	ix,0
add	ix,sp
call	_getb
pop	iy
pop	ix
ret
global	_crctab
;; crc32_a.s - crcbuf(crc, p, n) para crc32.h, en ensamblador (unos 150 ciclos
;; por byte en vez de 600). sdcccall(0); el CRC va en B C D E (E el byte bajo)
;; y vuelve en DEHL. No usa los registros alternativos.
global	S_crcbuf
global	_crctab
psect	text
global	S_crcbuf
S_crcbuf:
push	ix
ld	ix,0
add	ix,sp
ld	e,(ix+4)
ld	d,(ix+5)
ld	c,(ix+6)
ld	b,(ix+7)
ld	l,(ix+10)
ld	h,(ix+11)
ld	(cnt),hl
ld	a,(ix+8)
ld	h,(ix+9)
ld	l,a
push	hl
pop	ix
ld	hl,(cnt)
ld	a,h
or	l
jr	z,CRC1_00002
CRC1_00001:
ld	a,(ix+0)
inc	ix
xor	e
ld	l,a
ld	h,0
add	hl,hl
add	hl,hl
push	bc	; (HL += _crctab)
ld	bc,_crctab
add	hl,bc
pop	bc
ld	a,(hl)
xor	d
ld	e,a
inc	hl
ld	a,(hl)
xor	c
ld	d,a
inc	hl
ld	a,(hl)
xor	b
ld	c,a
inc	hl
ld	b,(hl)
ld	hl,(cnt)
dec	hl
ld	(cnt),hl
ld	a,h
or	l
jr	nz,CRC1_00001
CRC1_00002:
ld	l,e
ld	h,d
ld	e,c
ld	d,b
pop	ix
ret
psect	data
cnt:
defs	2	

; c2.21293 - puentes de convencion (los hace htc/puentes.py)
psect	text
; uint32_t crcbuf(uint32_t c, const uint8_t *p, uint16_t n)
global	_crcbuf, S_crcbuf
_crcbuf:
push	ix
push	iy
ld	ix,0
add	ix,sp
ld	l,(ix+12)
ld	h,(ix+13)
push	hl
ld	l,(ix+10)
ld	h,(ix+11)
push	hl
ld	l,(ix+8)
ld	h,(ix+9)
push	hl
ld	l,(ix+6)
ld	h,(ix+7)
push	hl
call	S_crcbuf
exx
ld	hl,8
add	hl,sp
ld	sp,hl
exx
pop	iy
pop	ix
ex	de,hl
ret
