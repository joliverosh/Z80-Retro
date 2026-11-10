;; unzip_a.s - la lectura de bits y la decodificacion de Huffman de UNZIP
;; (como tinf: un bit cada vez, pero sin llamadas). sdcccall(0).
	.module	unzipa
	.globl	_bit
	.globl	_bits
	.globl	_decode
	.globl	_getb
	.globl	_bitbuf
	.globl	_bitn
	.globl	_zerr
	.area	_CODE
; el siguiente bit al acarreo (no toca BC DE IX)
nbit:	ld	a,(_bitn)
	or	a
	jr	nz,00001$
	push	bc
	push	de
	push	ix
	call	_getb
	pop	ix
	pop	de
	pop	bc
	ld	a,l
	ld	(_bitbuf),a
	ld	a,#8
00001$:	dec	a
	ld	(_bitn),a
	ld	hl,#_bitbuf
	srl	(hl)
	ret
; uint8_t bit(void)
_bit::	call	nbit
	ld	a,#0
	rla
	ld	l,a
	ret
; uint16_t bits(uint8_t n): n bits, el primero el bajo
_bits::	ld	hl,#2
	add	hl,sp
	ld	a,(hl)
	ld	de,#0
	ld	bc,#1
	or	a
	jr	z,00012$
00011$:	push	af
	call	nbit
	jr	nc,00013$
	ld	a,e
	or	c
	ld	e,a
	ld	a,d
	or	b
	ld	d,a
00013$:	sla	c
	rl	b
	pop	af
	dec	a
	jr	nz,00011$
00012$:	ex	de,hl
	ret
; uint16_t decode(TREE *t): t->cnt[16] y despues t->sym[288]
_decode::
	ld	hl,#2
	add	hl,sp
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	push	ix
	push	hl
	pop	ix
	push	hl		; t, para el final
	ld	de,#0		; sum
	ld	bc,#0		; cur
	ld	a,#15
	ld	(dcnt),a
00021$:	call	nbit
	rl	c
	rl	b		; cur = 2 cur + bit
	inc	ix
	inc	ix		; ix -> cnt[len]
	ld	l,0(ix)
	ld	h,1(ix)
	ex	de,hl
	add	hl,de		; sum += cnt[len]
	ex	de,hl
	ld	a,c
	sub	l
	ld	c,a
	ld	a,b
	sbc	a,h
	ld	b,a		; cur -= cnt[len]
	jp	m,00022$
	ld	hl,#dcnt
	dec	(hl)
	jr	nz,00021$
	ld	a,#1		; mas de 15 bits: datos malos
	ld	(_zerr),a
	pop	hl
	pop	ix
	ld	hl,#0
	ret
00022$:	ld	l,e
	ld	h,d
	add	hl,bc		; sum + cur
	add	hl,hl
	pop	de
	add	hl,de
	ld	de,#32
	add	hl,de
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	pop	ix
	ret
	.area	_DATA
dcnt:	.ds	1
