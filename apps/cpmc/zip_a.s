;; zip_a.s - lo que mas tarda de ZIP: los bits de salida y correr las tablas
;; de hash al mover la ventana. sdcccall(0).
	.module	zipa
	.globl	_pbits
	.globl	_slidetab
	.globl	_bacc
	.globl	_bcnt
	.globl	_putbacc
	.area	_CODE
; void pbits(uint16_t v, uint8_t n): n bits de v, el bajo primero. Los bits
; entran por arriba de bacc; con 8, el byte sale por putbacc (C).
_pbits::
	ld	hl,#2
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
00001$:	srl	d
	rr	e
	rr	c
	ld	hl,#_bcnt
	inc	(hl)
	bit	3,(hl)
	jr	z,00002$
	ld	(hl),#0
	ld	a,c
	ld	(_bacc),a
	push	bc
	push	de
	push	ix
	call	_putbacc
	pop	ix
	pop	de
	pop	bc
00002$:	djnz	00001$
	ld	a,c
	ld	(_bacc),a
	ret
; void slidetab(uint16_t *p, uint16_t n): cada entrada: FFFF sigue FFFF,
; >= 1000h baja 1000h, < 1000h pasa a FFFF (quedo fuera de la ventana)
_slidetab::
	ld	hl,#2
	add	hl,sp
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	ex	de,hl
00011$:	inc	hl
	ld	a,(hl)		; byte alto
	inc	a
	jr	z,00013$	; FF: nada
	dec	a
	sub	#0x10
	jr	nc,00012$
	ld	(hl),#0xFF
	dec	hl
	ld	(hl),#0xFF
	inc	hl
	jr	00013$
00012$:	ld	(hl),a
00013$:	inc	hl
	dec	bc
	ld	a,b
	or	c
	jr	nz,00011$
	ret
; uint16_t mlen(uint8_t *a, uint8_t *b, uint16_t lim): cuantos bytes iguales
; al principio (lim > 0)
	.globl	_mlen
_mlen::
	push	ix
	ld	ix,#4
	add	ix,sp
	ld	l,0(ix)
	ld	h,1(ix)
	ld	e,2(ix)
	ld	d,3(ix)
	ld	c,4(ix)
	ld	b,5(ix)
	push	bc
00021$:	ld	a,(de)
	cp	(hl)
	jr	nz,00022$
	inc	hl
	inc	de
	dec	bc
	ld	a,b
	or	c
	jr	nz,00021$
00022$:	pop	hl		; lim - lo que falto = iguales
	or	a
	sbc	hl,bc
	pop	ix
	ret
