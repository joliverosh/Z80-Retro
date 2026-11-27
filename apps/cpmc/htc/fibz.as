; fibz.as - de fib_a.s (sdas2zas.py) y sus puentes (puentes.py); no se edita
; fib_a.s - la suma de FIB en BCD empacado: dos cifras por byte, ADC + DAA
psect	text
global	S_addbcd
; uint8_t addbcd(uint8_t *a, const uint8_t *b, uint16_t n) __sdcccall(0)
; a += b (n bytes, el de abajo primero); devuelve el acarreo
S_addbcd:
ld	hl,2
add	hl,sp
ld	e,(hl)
inc	hl
ld	d,(hl)	; DE = a
inc	hl
ld	c,(hl)
inc	hl
ld	b,(hl)
push	bc	; b
inc	hl
ld	a,(hl)
inc	hl
ld	h,(hl)
ld	l,a	; HL = n
ld	a,l
or	h
jr	z,ab0
ld	b,l	; vueltas de B (0 = 256) y de C
dec	hl
inc	h
ld	c,h
pop	hl	; HL = b
or	a
ab1:
ld	a,(de)
adc	a,(hl)
daa
ld	(de),a
inc	de
inc	hl
djnz	ab1
dec	c
jr	nz,ab1
ld	a,0
rla
ld	l,a
ret
ab0:
pop	hl
ld	l,0
ret

; z2.21293 - puentes de convencion (los hace htc/puentes.py)
psect	text
; uint8_t addbcd(uint8_t *a, const uint8_t *b, uint16_t n)
global	_addbcd, S_addbcd
_addbcd:
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
call	S_addbcd
exx
ld	hl,6
add	hl,sp
ld	sp,hl
exx
pop	iy
pop	ix
ret
