; fib_a.s - la suma de FIB en BCD empacado: dos cifras por byte, ADC + DAA
	.module fib_a
	.area _CODE
	.globl _addbcd
; uint8_t addbcd(uint8_t *a, const uint8_t *b, uint16_t n) __sdcccall(0)
; a += b (n bytes, el de abajo primero); devuelve el acarreo
_addbcd:
	ld hl,#2
	add hl,sp
	ld e,(hl)
	inc hl
	ld d,(hl)		; DE = a
	inc hl
	ld c,(hl)
	inc hl
	ld b,(hl)
	push bc			; b
	inc hl
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a			; HL = n
	ld a,l
	or h
	jr z,ab0
	ld b,l			; vueltas de B (0 = 256) y de C
	dec hl
	inc h
	ld c,h
	pop hl			; HL = b
	or a
ab1:	ld a,(de)
	adc a,(hl)
	daa
	ld (de),a
	inc de
	inc hl
	djnz ab1
	dec c
	jr nz,ab1
	ld a,#0
	rla
	ld l,a
	ret
ab0:	pop hl
	ld l,#0
	ret
