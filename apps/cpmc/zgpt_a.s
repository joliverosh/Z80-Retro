; zgpt_a.s - el producto escalar de ZGPT: suma de w[i] * x[i] con bytes con signo,
; por cuartos de cuadrado: a*b = T[a+b] - T[a-b], T[k] = piso(k*k/4).
; Los pesos van como byte + 80h (ua); x se prepara en dos paginas: xs = x + 80h y
; xd = 256 - xs (x de -127 a 127), asi que ua + xs = a + b + 256 y ua + xd = a - b + 256:
; los dos son indices de 9 bits en la misma tabla (bytes bajos en 2 paginas, altos en
; las 2 siguientes). Unos 245 ciclos por termino. (C) OLIVEROS 2026
	.module zgpt_a
	.area _CODE
	.globl _dotinit, _dot8, _dotk

; void dotinit(uint8_t pagina) __sdcccall(0): pagina = TL, +2 = TH, +4 = xs, +5 = xd
_dotinit:
	ld hl,#2
	add hl,sp
	ld a,(hl)
	ld (tl1+1),a
	ld (tl2+1),a
	add a,#4
	ld (xs1+1),a
	inc a
	ld (xd1+1),a
	ret

; int32_t dot8(uint8_t *w, uint8_t n, uint8_t x0) __sdcccall(0)
; suma de w[i] * x[x0 + i], i = 0..n-1
_dot8:
	push ix
	push iy
	ld hl,#6
	add hl,sp
	ld e,(hl)
	inc hl
	ld d,(hl)		; DE = w
	inc hl
	ld b,(hl)		; n
	inc hl
	ld c,(hl)		; x0
	push de
	exx
	pop hl			; HL' = w
	exx
	call core
	pop iy
	pop ix
	ret

; el nucleo: HL' = w, B = n, C = x0 -> DEHL (usa IX, IY, BC', HL' avanza)
core:
	exx
	ld bc,#0		; C' = byte alto de la suma de T[a+b], B' = de T[a-b]
	exx
	ld ix,#0
	ld iy,#0
	ld a,b
	or a
	jr z,dfin
dlp:
	exx
	ld a,(hl)		; ua
	inc hl
	exx
	ld l,c
xs1:	ld h,#0			; (pagina xs)
	ld d,a
	add a,(hl)		; a + b + 256 (9 bits)
	ld l,a
tl1:	ld a,#0			; (pagina TL)
	adc a,#0
	ld h,a
	ld e,(hl)
	inc h
	inc h
	ld a,(hl)
	ld h,d			; (ua)
	ld d,a
	add ix,de
	jr nc,1$
	exx
	inc c
	exx
1$:	ld a,h
	ld l,c
xd1:	ld h,#0			; (pagina xd)
	add a,(hl)		; a - b + 256
	ld l,a
tl2:	ld a,#0
	adc a,#0
	ld h,a
	ld e,(hl)
	inc h
	inc h
	ld d,(hl)
	add iy,de
	jr nc,2$
	exx
	inc b
	exx
2$:	inc c
	djnz dlp
dfin:
	push iy
	pop de
	push ix
	pop hl
	or a
	sbc hl,de		; los 16 bits bajos
	exx
	ld a,c
	sbc a,b			; el byte alto (24 bits con signo)
	exx
	ld e,a
	rla
	sbc a,a
	ld d,a			; DEHL
	ret

; void dotk(const uint8_t *k, int32_t *out, uint8_t npos, uint8_t x0) __sdcccall(0)
; out[j] = suma de k[j*32 + i] * x[x0 + i], i = 0..7 (una cabeza de 8, posiciones 0..npos-1)
_dotk:
	push ix
	push iy
	ld hl,#6
	add hl,sp
	ld e,(hl)
	inc hl
	ld d,(hl)		; DE = k
	inc hl
	ld c,(hl)
	inc hl
	ld b,(hl)		; BC = out
	inc hl
	ld a,(hl)		; npos
	inc hl
	ld (dkx+1),a
	ld a,(hl)
	ld (dkx0+1),a		; x0
	ld (dkout),bc
	push de
	exx
	pop hl			; HL' = k
	exx
dkx:	ld a,#0
	or a
	jr z,dkfin
dklp:	ld (dkn),a
	exx
	push hl			; el comienzo de esta posicion
	exx
	ld b,#8
dkx0:	ld c,#0
	call core		; DEHL
	push de
	ld b,h
	ld c,l
	ld hl,(dkout)
	ld (hl),c
	inc hl
	ld (hl),b
	inc hl
	pop de
	ld (hl),e
	inc hl
	ld (hl),d
	inc hl
	ld (dkout),hl
	exx
	pop hl
	ld bc,#32
	add hl,bc		; la posicion siguiente
	exx
	ld a,(dkn)
	dec a
	jr nz,dklp
dkfin:	pop iy
	pop ix
	ret

	.area _DATA
dkout:	.ds 2
dkn:	.ds 1
	.area _CODE

; uint32_t umul16(uint16_t a, uint16_t b) __sdcccall(0): a * b sin signo, en DEHL
; int32_t smul16(int16_t a, int16_t b) __sdcccall(0): con signo
	.globl _umul16, _smul16
_umul16:
	ld hl,#2
	add hl,sp
	ld c,(hl)
	inc hl
	ld b,(hl)		; BC = a
	inc hl
	ld e,(hl)
	inc hl
	ld d,(hl)		; DE = b
umul:				; DEHL = BC * DE
	ld a,d			; el menor como multiplicador (DE)
	cp b
	jr c,um0
	jr nz,umsw
	ld a,e
	cp c
	jr c,um0
umsw:	ld h,b
	ld l,c
	ld b,d
	ld c,e
	ex de,hl
um0:	ld hl,#0
	ld a,#16
	inc d
	dec d
	jr nz,um1
	ld d,e			; byte alto en cero: 8 vueltas
	ld e,#0
	ld a,#8
um1:	add hl,hl
	rl e
	rl d
	jr nc,um2
	add hl,bc
	jr nc,um2
	inc de
um2:	dec a
	jr nz,um1
	ret

_smul16:
	ld hl,#2
	add hl,sp
	ld c,(hl)
	inc hl
	ld b,(hl)		; BC = a
	inc hl
	ld e,(hl)
	inc hl
	ld d,(hl)		; DE = b
	ld a,b
	xor d
	push af			; el signo del resultado
	bit 7,b
	jr z,sm1
	xor a
	sub c
	ld c,a
	sbc a,a
	sub b
	ld b,a
sm1:	bit 7,d
	jr z,sm2
	xor a
	sub e
	ld e,a
	sbc a,a
	sub d
	ld d,a
sm2:	call umul
	pop af
	ret p
	xor a			; DEHL = -DEHL
	sub l
	ld l,a
	ld a,#0
	sbc a,h
	ld h,a
	ld a,#0
	sbc a,e
	ld e,a
	ld a,#0
	sbc a,d
	ld d,a
	ret
