; cpmz.as - bdos() y zios() de cpm.c para HI-TECH C 3.09 (ZAS).
; En un modulo aparte: el optimizador de HI-TECH no sabe lo que hace un #asm
; y lo quita. Los argumentos van en la pila, de a 2 bytes; se devuelve en HL.
psect	text
global	_bdos, _zios, _obn, _oflush, _zde, _zhl

; uint16_t bdos(uint8_t c, uint16_t de)
_bdos:
ld	a,(_obn)	; lo que espera en el bufer de la consola
or	a
call	nz,_oflush
pop	hl	; vuelta
pop	bc	; C
pop	de	; DE
push	de
push	bc
push	hl
push	ix
push	iy
call	5
pop	iy
pop	ix
ld	l,a	; (A = L y B = H, como en SDCC)
ret

; uint8_t zios(uint8_t c, uint8_t b, uint16_t de, uint16_t hl): RST 30h
_zios:
push	ix
push	iy
ld	ix,0
add	ix,sp
ld	c,(ix+6)
ld	b,(ix+8)
ld	e,(ix+10)
ld	d,(ix+11)
ld	l,(ix+12)
ld	h,(ix+13)
rst	30h
ld	(_zde),de
ld	(_zhl),hl
pop	iy
pop	ix
ld	l,a
ret


; lrelop y arelop: comparan dos long, uno en HL:DE (HL la parte alta) y otro
; en la pila (lo saca); dejan S = 1 si el de HL:DE es menor y Z = 1 si son
; iguales (y C = S, que es lo que mira el compilador con unsigned long).
; La de la biblioteca de HI-TECH C 3.09 es una sola para los dos y
; compara siempre con signo: con unsigned long sale mal cuando uno de los dos
; pasa de 7FFFFFFFh. lrelop es la de unsigned long; arelop, la de long.
global	lrelop, arelop
lrelop:
exx
pop	hl	; vuelta
exx
pop	bc	; el de la pila: parte baja
ex	de,hl
ex	(sp),hl	; HL = el de la pila, parte alta; queda la baja del otro
ex	de,hl	; DE = parte alta del de la pila, HL = la del otro
or	a
sbc	hl,de
pop	hl
jr	nz,lrdif
sbc	hl,bc
jr	z,lrfin
lrdif:
sbc	a,a	; A = FF si el de HL:DE es menor (acarreo)
or	1	; S = acarreo, Z = 0
rla		; y el acarreo otra vez (unsigned mira C; long, S)
lrfin:
exx
jp	(hl)

arelop:
exx
pop	hl
exx
pop	bc
ex	de,hl
ex	(sp),hl
ex	de,hl
ld	a,h
xor	d
jp	p,arigu	; el mismo signo: como sin signo
ld	a,h
or	1	; signos distintos: S = el signo del de HL:DE
pop	hl
exx
jp	(hl)
arigu:
or	a
sbc	hl,de
pop	hl
jr	nz,lrdif
sbc	hl,bc
jr	z,lrfin
jr	lrdif
