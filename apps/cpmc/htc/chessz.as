; chessz.as - de chess_a.s (sdas2zas.py) y sus puentes (puentes.py); no se edita
global	_amask, _astep, _b, _np, _pbit, _pl
; chess_a.s - lo que mas usa la busqueda de CHESS, en ensamblador
; uint8_t attacked(uint8_t s, uint8_t by): 1 si alguna pieza de by (0 blancas, 8 negras)
; ataca la casilla s. Recorre las piezas de by (pl, np) y mira con amask si desde su
; casilla se puede llegar a s; las que se deslizan siguen astep hasta s o hasta topar.
; (C) OLIVEROS 2026
global	S_attacked
psect	text
S_attacked:
push	iy
ld	c, a	; c = s
ld	a, l
or	a
ld	iy, _pl
ld	hl, _np
jr	z, CHE1_1
ld	iy, _pl+16
inc	hl
CHE1_1:
ld	b, (hl)
inc	b
jr	CHE1_3
CHE1_2:
ld	a, (iy+0)	; f: la casilla de la pieza
inc	iy
ld	(at_f), a
ld	hl, _b	; la pieza
add	a, l
ld	l, a
adc	a, h
sub	l
ld	h, a
ld	e, (hl)
ld	hl, _pbit	; su bit
ld	a, e
add	a, l
ld	l, a
adc	a, h
sub	l
ld	h, a
ld	d, (hl)
ld	a, (at_f)	; la distancia: s - f + 119
ld	l, a
ld	a, c
sub	l
add	a, 119
ld	(at_d), a
ld	hl, _amask
add	a, l
ld	l, a
adc	a, h
sub	l
ld	h, a
ld	a, (hl)
and	d
jr	z, CHE1_3
ld	a, d	; peon, caballo o rey: ataca
and	047h
jr	nz, CHE1_5
ld	a, (at_d)	; las que se deslizan: el paso
ld	hl, _astep
add	a, l
ld	l, a
adc	a, h
sub	l
ld	h, a
ld	d, (hl)
ld	a, (at_f)
CHE1_4:
add	a, d
cp	c
jr	z, CHE1_5
ld	e, a
ld	hl, _b
add	a, l
ld	l, a
adc	a, h
sub	l
ld	h, a
ld	a, (hl)
or	a
ld	a, e
jr	z, CHE1_4
CHE1_3:
djnz	CHE1_2
xor	a
pop	iy
ret
CHE1_5:
ld	a, 1
pop	iy
ret
psect	data
at_f:
defs	1	
at_d:
defs	1	

; z2.21293 - puentes de convencion (los hace htc/puentes.py)
psect	text
; uint8_t attacked(uint8_t s, uint8_t by) (sdcccall 1)
global	_attacked, S_attacked
_attacked:
push	ix
push	iy
ld	ix,0
add	ix,sp
ld	a,(ix+6)
ld	l,(ix+8)
call	S_attacked
ld	l,a
pop	iy
pop	ix
ret
