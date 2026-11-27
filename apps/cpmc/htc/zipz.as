; zipz.as - de zip_a.s (sdas2zas.py) y sus puentes (puentes.py); no se edita
global	_bacc, _bcnt, _putbacc
;; zip_a.s - lo que mas tarda de ZIP: los bits de salida y correr las tablas
;; de hash al mover la ventana. sdcccall(0).
global	S_pbits
global	S_slidetab
global	_bacc
global	_bcnt
global	_putbacc
psect	text
; void pbits(uint16_t v, uint8_t n): n bits de v, el bajo primero. Los bits
; entran por arriba de bacc; con 8, el byte sale por putbacc (C).
global	S_pbits
S_pbits:
ld	hl,2
add	hl,sp
ld	e,(hl)
inc	hl
ld	d,(hl)
inc	hl
ld	b,(hl)
ld	a,b
or	a
ret	z
ld	a,(_bacc)
ld	c,a
ZIP1_00001:
srl	d
rr	e
rr	c
ld	hl,_bcnt
inc	(hl)
bit	3,(hl)
jr	z,ZIP1_00002
ld	(hl),0
ld	a,c
ld	(_bacc),a
push	bc
push	de
push	ix
call	_putbacc
pop	ix
pop	de
pop	bc
ZIP1_00002:
djnz	ZIP1_00001
ld	a,c
ld	(_bacc),a
ret
; void slidetab(uint16_t *p, uint16_t n): cada entrada: FFFF sigue FFFF,
; >= 1000h baja 1000h, < 1000h pasa a FFFF (quedo fuera de la ventana)
global	S_slidetab
S_slidetab:
ld	hl,2
add	hl,sp
ld	e,(hl)
inc	hl
ld	d,(hl)
inc	hl
ld	c,(hl)
inc	hl
ld	b,(hl)
ex	de,hl
ZIP2_00011:
inc	hl
ld	a,(hl)	; byte alto
inc	a
jr	z,ZIP2_00013	; FF: nada
dec	a
sub	010h
jr	nc,ZIP2_00012
ld	(hl),0FFh
dec	hl
ld	(hl),0FFh
inc	hl
jr	ZIP2_00013
ZIP2_00012:
ld	(hl),a
ZIP2_00013:
inc	hl
dec	bc
ld	a,b
or	c
jr	nz,ZIP2_00011
ret
; uint16_t mlen(uint8_t *a, uint8_t *b, uint16_t lim): cuantos bytes iguales
; al principio (lim > 0)
global	S_mlen
global	S_mlen
S_mlen:
push	ix
ld	ix,4
add	ix,sp
ld	l,(ix+0)
ld	h,(ix+1)
ld	e,(ix+2)
ld	d,(ix+3)
ld	c,(ix+4)
ld	b,(ix+5)
push	bc
ZIP3_00021:
ld	a,(de)
cp	(hl)
jr	nz,ZIP3_00022
inc	hl
inc	de
dec	bc
ld	a,b
or	c
jr	nz,ZIP3_00021
ZIP3_00022:
pop	hl	; lim - lo que falto = iguales
or	a
sbc	hl,bc
pop	ix
ret

; z2.21293 - puentes de convencion (los hace htc/puentes.py)
psect	text
; void pbits(uint16_t v, uint8_t n)
global	_pbits, S_pbits
_pbits:
push	ix
push	iy
ld	ix,0
add	ix,sp
ld	a,(ix+8)
push	af
inc	sp
ld	l,(ix+6)
ld	h,(ix+7)
push	hl
call	S_pbits
exx
ld	hl,3
add	hl,sp
ld	sp,hl
exx
pop	iy
pop	ix
ret
; void slidetab(uint16_t *p, uint16_t n)
global	_slidetab, S_slidetab
_slidetab:
push	ix
push	iy
ld	ix,0
add	ix,sp
ld	l,(ix+8)
ld	h,(ix+9)
push	hl
ld	l,(ix+6)
ld	h,(ix+7)
push	hl
call	S_slidetab
exx
ld	hl,4
add	hl,sp
ld	sp,hl
exx
pop	iy
pop	ix
ret
; uint16_t mlen(uint8_t *a, uint8_t *b, uint16_t lim)
global	_mlen, S_mlen
_mlen:
push	ix
push	iy
ld	ix,0
add	ix,sp
ld	l,(ix+10)
ld	h,(ix+11)
push	hl
ld	l,(ix+8)
ld	h,(ix+9)
push	hl
ld	l,(ix+6)
ld	h,(ix+7)
push	hl
call	S_mlen
exx
ld	hl,6
add	hl,sp
ld	sp,hl
exx
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
