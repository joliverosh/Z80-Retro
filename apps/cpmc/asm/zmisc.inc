; zmisc.inc - azar, tics y flechas (va despues de zcon.inc)

; RND: HL = el siguiente numero al azar (xorshift de 16 bits, como el de cpm.c)
RND:    LD      HL,(RS)
        LD      A,H             ; rs ^= rs << 7
        RRA
        LD      A,L
        RRA
        LD      C,A
        LD      A,0
        RRA
        XOR     L
        LD      L,A
        LD      A,H
        XOR     C
        LD      H,A
        LD      A,H             ; rs ^= rs >> 9
        SRL     A
        XOR     L
        LD      L,A
        XOR     H               ; rs ^= rs << 8
        LD      H,A
        LD      (RS),HL
        RET
; SRND: la semilla en HL (0 no sirve: queda 1)
SRND:   LD      A,H
        OR      L
        JR      NZ,SRND1
        INC     L
SRND1:  LD      (RS),HL
        RET
; RNDN: A = un numero al azar de 0 a C-1 (C de 1 a 128)
RNDN:   PUSH    BC
        CALL    RND
        POP     BC
        JP      DIVC

; TICKS: HL = los tics de ZIOS (servicio 31), A = tics por segundo
TICKS:  LD      C,31
        LD      B,0
        JP      ZIOS

; KEY: la tecla que haya (0 si no hay), con las flechas y WASD/IJKL como
; K_UP, K_DOWN, K_RIGHT y K_LEFT (como keys.h). Z si no hay tecla.
K_UP    EQU     81h
K_DOWN  EQU     82h
K_RIGHT EQU     83h
K_LEFT  EQU     84h
KEY:    CALL    GETKEY
        RET     Z
        CP      ESC
        JR      Z,KEYESC
        LD      C,A
        OR      20h
        CP      'w'
        JR      Z,KUP
        CP      'i'
        JR      Z,KUP
        CP      's'
        JR      Z,KDN
        CP      'k'
        JR      Z,KDN
        CP      'a'
        JR      Z,KLF
        CP      'j'
        JR      Z,KLF
        CP      'd'
        JR      Z,KRT
        CP      'l'
        JR      Z,KRT
        LD      A,C
        OR      A
        RET
KUP:    LD      A,K_UP
        OR      A
        RET
KDN:    LD      A,K_DOWN
        OR      A
        RET
KLF:    LD      A,K_LEFT
        OR      A
        RET
KRT:    LD      A,K_RIGHT
        OR      A
        RET
KEYESC: LD      B,200           ; ESC [ A..D
        CALL    KESPERA
        CP      '['
        JR      Z,KE1
        CP      'O'
        LD      A,ESC
        RET     NZ
KE1:    LD      B,200
        CALL    KESPERA
        CP      'A'
        JR      C,KE0
        CP      'D'+1
        JR      NC,KE0
        ADD     A,K_UP-'A'
        RET
KE0:    XOR     A
        RET
; KESPERA: hasta B veces GETKEY; A = la tecla o 0
KESPERA:PUSH    BC
        CALL    GETKEY
        POP     BC
        RET     NZ
        DJNZ    KESPERA
        XOR     A
        RET

RS:     DW      12345
