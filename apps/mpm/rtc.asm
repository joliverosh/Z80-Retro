; =============================================================================
;  RTC.COM - lee el DS1307 de la Z80-Retro y, bajo MP/M II, pone en hora el
;  sistema (funcion 104). Bajo CP/M solo muestra la fecha y la hora.
;  I2C por software en los puertos 64h/65h (rutinas de zlib/libi2c.asm de
;  Peter Wilson, MIT). Se lee con las interrupciones apagadas: el XIOS tambien
;  escribe el puerto 64h (seleccion de la SD) y no debe cruzarse.
;  OLIVEROS 2026
; =============================================================================
BDOS    EQU     5
I2CP    EQU     64h
I2CDATA EQU     02h

        ORG     100h
        LD      SP,STACK
        CALL    MAIN
        JP      0
MAIN:   DI
        CALL    RDRTC
        EI
        JR      NC,OK
        LD      DE,M_NORTC
        JP      PSTR
OK:
        LD      DE,M_DATE
        CALL    PSTR
        LD      A,'2'
        CALL    PCH
        LD      A,'0'
        CALL    PCH
        LD      A,(RG+6)
        CALL    PBCD
        LD      A,'-'
        CALL    PCH
        LD      A,(RG+5)
        CALL    PBCD
        LD      A,'-'
        CALL    PCH
        LD      A,(RG+4)
        CALL    PBCD
        LD      A,' '
        CALL    PCH
        LD      A,(RG+2)
        AND     3Fh
        CALL    PBCD
        LD      A,':'
        CALL    PCH
        LD      A,(RG+1)
        CALL    PBCD
        LD      A,':'
        CALL    PCH
        LD      A,(RG+0)
        AND     7Fh
        CALL    PBCD
        CALL    CRLF
        LD      C,12            ; version: H = 1 en MP/M
        CALL    BDOS
        LD      A,H
        DEC     A
        RET     NZ
        CALL    DAYS            ; TOD: dia (desde el 1/1/1978 = 1), hora, minuto, segundo
        LD      (TOD),HL
        LD      A,(RG+2)
        AND     3Fh
        LD      (TOD+2),A
        LD      A,(RG+1)
        LD      (TOD+3),A
        LD      A,(RG+0)
        AND     7Fh
        LD      (TOD+4),A
        LD      C,104
        LD      DE,TOD
        CALL    BDOS
        LD      DE,M_SET
        JP      PSTR

; DAYS: HL = dias desde el 31/12/1977 hasta la fecha del reloj (anio 20YY)
DAYS:   LD      A,(RG+6)
        CALL    BIN
        ADD     A,22            ; anios completos desde 1978
        LD      B,A
        LD      HL,0
        LD      C,78            ; anio actual (mod 100 desde 1900): 78..
DY1:    LD      A,B
        OR      A
        JR      Z,DY3
        LD      DE,365
        LD      A,C
        AND     3
        JR      NZ,DY2
        INC     DE              ; bisiesto (1980..2096: cada 4)
DY2:    ADD     HL,DE
        INC     C
        DJNZ    DY1
DY3:    PUSH    HL              ; dias de los meses ya pasados
        LD      A,(RG+5)
        CALL    BIN
        DEC     A
        LD      B,A
        LD      HL,MES
        LD      DE,0
DY4:    LD      A,B
        OR      A
        JR      Z,DY5
        LD      A,(HL)
        ADD     A,E
        LD      E,A
        JR      NC,DY4B
        INC     D
DY4B:   INC     HL
        DEC     B
        JR      DY4
DY5:    LD      A,(RG+5)         ; febrero bisiesto ya pasado
        CALL    BIN
        CP      3
        JR      C,DY6
        LD      A,(RG+6)
        CALL    BIN
        AND     3
        JR      NZ,DY6
        INC     DE
DY6:    POP     HL
        ADD     HL,DE
        LD      A,(RG+4)
        CALL    BIN
        LD      E,A
        LD      D,0
        ADD     HL,DE
        RET
MES:    DEFB    31,28,31,30,31,30,31,31,30,31,30,31

BIN:    PUSH    BC              ; BCD -> binario
        LD      B,A
        AND     0F0h
        RRCA
        LD      C,A
        RRCA
        RRCA
        ADD     A,C
        LD      C,A
        LD      A,B
        AND     0Fh
        ADD     A,C
        POP     BC
        RET

; RDRTC: los 7 registros del DS1307 en R. CY si no responde.
RDRTC:  LD      A,3
        LD      (IVAL),A
        OUT     (I2CP+1),A
        CALL    ISTART
        LD      A,0D0h
        CALL    IWBY
        OR      A
        SCF
        JR      NZ,RD9
        XOR     A
        CALL    IWBY
        CALL    ISTART
        LD      A,0D1h
        CALL    IWBY
        LD      HL,RG
        LD      B,7
RD1:    LD      A,B
        DEC     A               ; ACK salvo en el ultimo
        LD      A,0
        JR      NZ,RD2
        INC     A
RD2:    CALL    IRBY
        LD      (HL),A
        INC     HL
        DJNZ    RD1
        OR      A
RD9:    PUSH    AF
        CALL    ISTOP
        POP     AF
        RET

IDLY:   PUSH    BC
        LD      B,3
IDL1:   DJNZ    IDL1
        POP     BC
        RET
ISTART: LD      A,1
        CALL    ICLK
        LD      A,1
        CALL    IDAT
        CALL    IDLY
        XOR     A
        CALL    IDAT
        CALL    IDLY
        XOR     A
        CALL    ICLK
        JP      IDLY
ISTOP:  XOR     A
        CALL    IDAT
        CALL    IDLY
        LD      A,1
        CALL    ICLK
        CALL    IDLY
        LD      A,1
        CALL    IDAT
        CALL    IDLY
        XOR     A
        CALL    ICLK
        JP      IDLY
IWBI:   CALL    IDAT
        CALL    IDLY
        LD      A,1
        CALL    ICLK
        CALL    IDLY
        XOR     A
        CALL    ICLK
        JP      IDLY
IWBY:   PUSH    BC              ; manda A; devuelve el bit ACK (0 = reconocido)
        LD      B,8
        LD      C,A
IW1:    RLC     C
        LD      A,C
        CALL    IWBI
        DJNZ    IW1
        CALL    IRBI
        POP     BC
        RET
IRBI:   LD      A,1
        CALL    IDAT
        CALL    IDLY
        LD      A,1
        CALL    ICLK
        CALL    IDLY
        IN      A,(I2CP)
        AND     I2CDATA
        PUSH    AF
        XOR     A
        CALL    ICLK
        CALL    IDLY
        POP     AF
        SRA     A
        RET
IRBY:   PUSH    BC              ; A = bit a mandar despues (0 ACK, 1 NACK)
        PUSH    AF
        LD      C,0
        LD      B,8
IR1:    LD      A,C
        ADD     A,A
        LD      C,A
        CALL    IRBI
        OR      C
        LD      C,A
        DJNZ    IR1
        POP     AF
        CALL    IWBI
        LD      A,C
        POP     BC
        RET
IDAT:   PUSH    BC
        AND     1
        LD      A,(ICLKP)
        LD      C,A
        LD      A,(IVAL)
        JR      Z,ID1
        OR      I2CDATA
        JR      ID2
ID1:    AND     NOT I2CDATA
ID2:    LD      (IVAL),A
        OUT     (C),A
        POP     BC
        RET
ICLK:   PUSH    BC
        RRCA
        LD      A,I2CP
        ADC     A,0
        LD      (ICLKP),A
        LD      C,A
        LD      A,(IVAL)
        OUT     (C),A
        POP     BC
        RET

PBCD:   PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    PDIG
        POP     AF
PDIG:   AND     0Fh
        ADD     A,'0'
PCH:    PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      E,A
        LD      C,2
        CALL    BDOS
        POP     HL
        POP     DE
        POP     BC
        RET
PSTR:   LD      C,9
        JP      BDOS
CRLF:   LD      A,13
        CALL    PCH
        LD      A,10
        JP      PCH

M_DATE: DEFB    'DS1307: $'
M_SET:  DEFB    'MP/M time set from the DS1307.',13,10,'$'
M_NORTC: DEFB   'The DS1307 does not answer.',13,10,'$'
IVAL:   DEFB    3
ICLKP:  DEFB    I2CP
RG:     DEFS    7
TOD:    DEFS    5
        DEFS    64
STACK:
        END
