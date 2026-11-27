; benchz.as - spin() de bench.c para HI-TECH C (ZAS): n vueltas de 3356 ciclos
; (B=0: DJNZ 256 veces = 3323, mas 33 de la vuelta), como la de SDCC
psect	text
global	_spin
_spin:
pop	hl
pop	de
push	de
push	hl
spin1:
ld	b,0
spin2:
djnz	spin2
dec	de
ld	a,d
or	e
jr	nz,spin1
ret
