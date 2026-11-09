; VC.COM - MP/M II ZEPHYRUS: muestra la consola virtual n en el terminal de la
; SIO A, como Ctrl-F1..F5.   VC 2   (1-4, o 5 con CONSOLE4=VIRTUAL)
; Usa el servicio 40 del XIOS (RST 30h, C = 40, E = consola 0-4).
; (C) OLIVEROS 2026
BDOS    EQU     5
TAIL    EQU     80h
        ORG     100h
        LD      C,12            ; MP/M? (BDOS 12: H = 1)
        CALL    BDOS
        LD      A,H
        DEC     A
        JR      NZ,ENOMPM
        LD      HL,TAIL
        LD      B,(HL)
VC1:    INC     HL
        LD      A,B
        OR      A
        JR      Z,EUSO
        DEC     B
        LD      A,(HL)
        CP      ' '
        JR      Z,VC1
        SUB     '1'
        CP      5
        JR      NC,EUSO
        LD      E,A
        LD      C,40
        RST     30h
        OR      A
        RET     Z
EUSO:   LD      DE,MUSO
        JR      MSG
ENOMPM: LD      DE,MNOMPM
MSG:    LD      C,9
        JP      BDOS
MUSO:   DEFB    'Usage: VC n  (shows virtual console n, 1-4 or 5)',13,10,'$'
MNOMPM: DEFB    'VC needs MP/M II ZEPHYRUS',13,10,'$'
