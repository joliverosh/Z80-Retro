; zcon.inc - consola, BDOS, ZIOS y numeros para los programas en ensamblador
; (CP/M 2.2, CP/M 3 y MP/M II en la ZEPHYRUS / Z80-Retro). Mensajes en ingles.
;
; Convenciones: PUTC guarda todo menos las banderas; PSTR, PRI y CRLF guardan BC, DE y HL (PSTR deja HL
; despues del 0). Las demas pueden cambiar cualquier registro salvo IX e IY,
; que guardan siempre. Acarreo = error o "no hay".
;
; La salida se junta en OB y sale de una vez con el servicio 46 del XIOS de
; ZEPHYRUS cuando lo hay (MP/M de noviembre de 2026 en adelante): la mitad de
; ciclos por caracter. Si no, cada caracter va por el BDOS 6. SYS vacia OB
; antes de cada llamada al BDOS, asi que el orden de la salida no se altera.

BDOS    EQU     5
ESC     EQU     27
OBSZ    EQU     128

; INIT: ver el sistema y el modo de salida. Va al principio de cada programa.
INIT:   LD      C,12
        CALL    BDOS
        LD      (VERS),HL
        LD      A,H
        CP      1
        RET     NZ
        LD      (MPM),A
        LD      C,46            ; hay servicio 46? (con 0 bytes no escribe)
        LD      B,0
        LD      DE,0
        CALL    ZIOS
        OR      A
        RET     NZ
        LD      A,1
        LD      (OMODE),A
        RET

; SYS: BDOS con C y DE, despues de vaciar la salida. Devuelve A y HL.
SYS:    CALL    FLUSH
        PUSH    IX
        PUSH    IY
        CALL    BDOS
        POP     IY
        POP     IX
        RET

; ZIOS: RST 30h con C, B, DE y HL. Devuelve A, DE y HL.
ZIOS:   PUSH    IX
        PUSH    IY
        RST     30h
        POP     IY
        POP     IX
        RET

EXIT:   CALL    FLUSH
        JP      0

; PUTC: el caracter en A, sin traducir (guarda tambien A)
PUTC:   PUSH    AF
        PUSH    HL
        PUSH    DE
        PUSH    BC
        LD      E,A
        LD      A,(OMODE)
        DEC     A
        JR      NZ,PUTB
        LD      A,(OBN)
        LD      C,A
        LD      B,0
        LD      HL,OB
        ADD     HL,BC
        LD      (HL),E
        INC     A
        LD      (OBN),A
        CP      OBSZ
        CALL    Z,FLUSH
        JR      PUTX
PUTB:   LD      C,6
        LD      A,E
        CP      0FEh            ; FE y FF no pasan por el BDOS 6
        JR      C,PUTB1
        LD      C,2
PUTB1:  PUSH    IX
        PUSH    IY
        CALL    BDOS
        POP     IY
        POP     IX
PUTX:   POP     BC
        POP     DE
        POP     HL
        POP     AF
        RET

FLUSH:  LD      A,(OBN)
        OR      A
        RET     Z
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      E,A
        LD      D,0
        XOR     A
        LD      (OBN),A
        LD      B,A
        LD      C,46
        LD      HL,OB
        CALL    ZIOS
        POP     HL
        POP     DE
        POP     BC
        RET

; PSTR: texto en HL terminado en 0
PSTR:   LD      A,(HL)
        INC     HL
        OR      A
        RET     Z
        CALL    PUTC
        JR      PSTR

; PRI: el texto que sigue a la llamada (CALL PRI / DB '...',0)
PRI:    EX      (SP),HL
        CALL    PSTR
        EX      (SP),HL
        RET

CRLF:   CALL    PRI
        DB      13,10,0
        RET

SPACE:  LD      A,' '
        JP      PUTC

; GOTOXY: D fila (1-24), E columna (1-80)
GOTOXY: PUSH    DE
        LD      A,ESC
        CALL    PUTC
        LD      A,'['
        CALL    PUTC
        LD      L,D
        LD      H,0
        CALL    PDEC
        LD      A,';'
        CALL    PUTC
        POP     DE
        LD      L,E
        LD      H,0
        CALL    PDEC
        LD      A,'H'
        JP      PUTC

; ---------------------------------------------------------------- numeros
; PDEC: HL en decimal. PDECW: HL con ancho A (relleno en PADC: ' ' o '0').
; P32W: el numero de 32 bits en (HL) con ancho A.
PDEC:   XOR     A
PDECW:  LD      (NUMT),HL
        LD      HL,0
        LD      (NUMT+2),HL
        JR      PNUM
P32W:   LD      DE,NUMT
        LD      BC,4
        LDIR
PNUM:   LD      (PW),A
        LD      HL,DBUF
PN1:    PUSH    HL
        CALL    D32
        POP     HL
        ADD     A,'0'
        LD      (HL),A
        INC     HL
        LD      DE,(NUMT)
        LD      A,D
        OR      E
        LD      DE,(NUMT+2)
        OR      D
        OR      E
        JR      NZ,PN1
        LD      DE,DBUF         ; cifras = HL - DBUF
        PUSH    HL
        OR      A
        SBC     HL,DE
        LD      B,L
        POP     HL
        LD      A,(PW)
        SUB     B
        JR      C,PN3
        JR      Z,PN3
        LD      C,A
        LD      A,(PADC)
PN2:    CALL    PUTC
        DEC     C
        JR      NZ,PN2
PN3:    DEC     HL
        LD      A,(HL)
        CALL    PUTC
        DJNZ    PN3
        LD      A,' '
        LD      (PADC),A
        RET

; D32: NUMT = NUMT / 10, A = el resto
D32:    LD      HL,NUMT+3
        XOR     A
        LD      D,4
D32A:   LD      C,(HL)
        LD      B,8
D32B:   SLA     C
        RLA
        CP      10
        JR      C,D32C
        SUB     10
        INC     C
D32C:   DJNZ    D32B
        LD      (HL),C
        DEC     HL
        DEC     D
        JR      NZ,D32A
        RET

; PHEX2: A en hexadecimal (2 cifras). PHEX4: HL (4 cifras).
PHEX4:  LD      A,H
        CALL    PHEX2
        LD      A,L
PHEX2:  PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    PHEX1
        POP     AF
PHEX1:  AND     0Fh
        ADD     A,90h
        DAA
        ADC     A,40h
        DAA
        JP      PUTC

; INC32: (HL) += 1. ADD32: (HL) += (DE).
INC32:  INC     (HL)
        RET     NZ
        INC     HL
        INC     (HL)
        RET     NZ
        INC     HL
        INC     (HL)
        RET     NZ
        INC     HL
        INC     (HL)
        RET
ADD32:  LD      B,4
        OR      A
ADD32A: LD      A,(DE)
        ADC     A,(HL)
        LD      (HL),A
        INC     HL
        INC     DE
        DJNZ    ADD32A
        RET

; DIVC: HL = HL / C, A = el resto (C de 1 a 128)
DIVC:   XOR     A
        LD      B,16
DIVC1:  ADD     HL,HL
        RLA
        CP      C
        JR      C,DIVC2
        SUB     C
        INC     L
DIVC2:  DJNZ    DIVC1
        RET

; ---------------------------------------------------------------- teclado
; GETKEY: la tecla que haya, o 0 (Z). WAITKEY: espera una.
GETKEY: LD      C,6
        LD      E,0FFh
        CALL    SYS
        OR      A
        RET
WAITKEY:CALL    GETKEY
        RET     NZ
        LD      DE,1
        CALL    DELAY
        JR      WAITKEY

; BRK: acarreo si se pulso ^C, ESC o Q
BRK:    CALL    GETKEY
        RET     Z
ISBRK:  CP      3
        JR      Z,SIBRK
        CP      ESC
        JR      Z,SIBRK
        PUSH    AF
        OR      20h
        CP      'q'
        JR      Z,SIBRK2
        POP     AF              ; A queda como estaba
        OR      A
        RET
SIBRK2: POP     AF
SIBRK:  SCF
        RET

; DELAY: DE tics, en MP/M (BDOS 141); en CP/M no espera
DELAY:  LD      A,(MPM)
        OR      A
        RET     Z
        LD      C,141
        JP      SYS

; "-- More --": acarreo si hay que salir; si no, A = la tecla
MORE:   CALL    PRI
        DB      ESC,'[7m-- More -- (SPACE page, RETURN line, Q quit)',ESC,'[0m',0
        CALL    WAITKEY
        PUSH    AF
        CALL    PRI
        DB      13,ESC,'[K',0
        POP     AF
        JR      ISBRK

VERS:   DW      0               ; BDOS 12
MPM:    DB      0               ; 1 en MP/M
OMODE:  DB      2               ; 1 servicio 46, 2 BDOS
OBN:    DB      0
PADC:   DB      ' '
PW:     DB      0

; lo que no tiene valor inicial (NUMT, DBUF, OB) esta en zcon.bss
