; zdbldr.asm - cargador de ZDB.COM: copia ZDB justo debajo del BDOS,
; lo reubica con el mapa de bits (un bit por byte, el mas alto primero)
; y salta a su inicio. ISZ y NPG los pone mkzdb.py en zdbsz.inc.
        INCLUDE zdbsz.inc
        ORG     100h
        LD      A,(7)           ; pagina del BDOS
        SUB     NPG
        LD      D,A             ; D = pagina de destino
        LD      E,0
        PUSH    DE
        LD      HL,IMG
        LD      BC,ISZ
        LDIR
        POP     HL              ; LDIR movio DE
        PUSH    HL
        LD      D,H
        LD      IX,BMAP
        LD      BC,ISZ
R1:     LD      A,(IX+0)
        INC     IX
        SCF
        ADC     A,A             ; carry = bit 7; un 1 de centinela en el bit 0
R2:     JR      NC,R3
        LD      E,A
        LD      A,(HL)
        ADD     A,D
        LD      (HL),A
        LD      A,E
R3:     INC     HL
        DEC     BC
        LD      E,A
        LD      A,B
        OR      C
        JR      Z,R4
        LD      A,E
        ADD     A,A
        JR      Z,R1            ; solo quedaba el centinela
        JR      R2
R4:     POP     HL
        LD      L,3
        JP      (HL)
IMG     EQU     $
BMAP    EQU     IMG+ISZ
