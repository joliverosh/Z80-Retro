;; crc32_a.s - crcbuf(crc, p, n) para crc32.h, en ensamblador (unos 150 ciclos
;; por byte en vez de 600). sdcccall(0); el CRC va en B C D E (E el byte bajo)
;; y vuelve en DEHL. No usa los registros alternativos.
	.module	crc32a
	.globl	_crcbuf
	.globl	_crctab
	.area	_CODE
_crcbuf::
	push	ix
	ld	ix,#0
	add	ix,sp
	ld	e,4(ix)
	ld	d,5(ix)
	ld	c,6(ix)
	ld	b,7(ix)
	ld	l,10(ix)
	ld	h,11(ix)
	ld	(cnt),hl
	ld	a,8(ix)
	ld	h,9(ix)
	ld	l,a
	push	hl
	pop	ix
	ld	hl,(cnt)
	ld	a,h
	or	l
	jr	z,00002$
00001$:	ld	a,0(ix)
	inc	ix
	xor	e
	ld	l,a
	ld	h,#0
	add	hl,hl
	add	hl,hl
	ld	a,l
	add	a,#<_crctab
	ld	l,a
	ld	a,h
	adc	a,#>_crctab
	ld	h,a
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
	jr	nz,00001$
00002$:	ld	l,e
	ld	h,d
	ld	e,c
	ld	d,b
	pop	ix
	ret
	.area	_DATA
cnt:	.ds	2
