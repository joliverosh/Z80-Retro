; comun.inc - rutinas compartidas de los programas de matematicas (CP/M):
; salida por el BDOS, numeros en decimal (16 y 32 bits) y la hora del DS1307
; por el API de ZIOS (RST 30h, C=28) para medir el tiempo.
BDOS    EQU 5

PCH:    PUSH HL
        PUSH DE
        PUSH BC
        PUSH AF
        LD E,A
        LD C,2
        CALL BDOS
        POP AF
        POP BC
        POP DE
        POP HL
        RET
PSTR:   PUSH HL
        PUSH BC
        LD C,9
        CALL BDOS
        POP BC
        POP HL
        RET
CRLF:   LD A,13
        CALL PCH
        LD A,10
        JP PCH

; PNUM: HL sin signo, sin ceros a la izquierda
PNUM:   PUSH HL
        LD (N32),HL
        LD HL,0
        LD (N32+2),HL
        POP HL
; P32: (N32) de 32 bits en decimal. Destruye N32.
P32:    LD B,0          ; cifras en la pila
P32A:   PUSH BC
        CALL D32X10     ; N32 /= 10, A = resto
        POP BC
        PUSH AF
        INC B
        LD HL,(N32)
        LD A,H
        OR L
        LD HL,(N32+2)
        OR H
        OR L
        JR NZ,P32A
P32B:   POP AF
        ADD A,'0'
        CALL PCH
        DJNZ P32B
        RET
; D32X10: N32 = N32 / 10, A = resto
D32X10: LD HL,N32+3
        LD B,4
        XOR A
D32A:   LD C,(HL)       ; A:C / 10 (A < 10)
        PUSH BC
        LD B,8
D32B:   SLA C
        RLA
        CP 10
        JR C,D32C
        SUB 10
        INC C
D32C:   DJNZ D32B
        LD E,C
        POP BC
        LD (HL),E
        DEC HL
        DJNZ D32A
        RET

; GETT: HL = buffer de 6 bytes (seg, min, hora, dia, mes, ano en BCD).
; En CP/M se lee el DS1307 con ZIOS (RST 30h, C=28). En MP/M II ZIOS ya no
; esta (RST 30h es un RET): se lee la hora de XDOS (dia, hora, min, seg en
; BCD), cuya direccion esta en SYSDAT+252 (SYSDAT con la funcion 154). La
; funcion 105 no sirve: en MP/M II no devuelve los segundos. Solo se llenan
; seg, min y hora, que es lo que usan PTIME y ELAPS.
GETT:   PUSH HL
        LD C,12
        CALL BDOS               ; H = 1 en MP/M
        DEC H
        JR Z,GTMPM
        POP HL
        LD C,28
        RST 30h
        RET
GTMPM:  LD C,154
        CALL BDOS               ; HL = SYSDAT
        LD L,252
        LD E,(HL)
        INC HL
        LD D,(HL)               ; DE = TOD de XDOS
        POP HL
GTM1:   LD A,(DE)               ; dia (bajo): para ver si el tic la cambio
        PUSH DE
        INC DE
        INC DE
        INC DE
        INC DE
        LD A,(DE)               ; seg
        LD B,A
        LD (HL),A
        INC HL
        DEC DE
        LD A,(DE)               ; min
        LD (HL),A
        INC HL
        DEC DE
        LD A,(DE)               ; hora
        LD (HL),A
        DEC HL
        DEC HL
        INC DE
        INC DE
        LD A,(DE)               ; seg otra vez: si cambio, leer de nuevo
        POP DE
        CP B
        JR NZ,GTM1
        RET
; PTIME: hh:mm:ss de (HL)
PTIME:  PUSH HL
        INC HL
        INC HL
        LD A,(HL)
        CALL PBCD
        LD A,':'
        CALL PCH
        POP HL
        PUSH HL
        INC HL
        LD A,(HL)
        CALL PBCD
        LD A,':'
        CALL PCH
        POP HL
        LD A,(HL)
PBCD:   PUSH AF
        RRCA
        RRCA
        RRCA
        RRCA
        AND 0Fh
        ADD A,'0'
        CALL PCH
        POP AF
        AND 0Fh
        ADD A,'0'
        JP PCH
BCD2B:  PUSH BC
        LD B,A
        AND 0F0h
        RRCA
        LD C,A
        RRCA
        RRCA
        ADD A,C
        LD C,A
        LD A,B
        AND 0Fh
        ADD A,C
        POP BC
        RET
; TMIN: (HL) -> HL = minutos del dia, A = segundos
TMIN:   LD A,(HL)
        CALL BCD2B
        LD (TSEC),A
        INC HL
        LD A,(HL)
        CALL BCD2B
        LD E,A
        INC HL
        LD A,(HL)
        CALL BCD2B
        LD L,A
        LD H,0
        ADD HL,HL
        ADD HL,HL
        PUSH HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        POP BC
        OR A
        SBC HL,BC
        LD D,0
        ADD HL,DE
        LD A,(TSEC)
        RET
; ELAPS: tiempo de (HL) a (DE): imprime "N min S s"
ELAPS:  PUSH DE
        CALL TMIN
        LD (EM0),HL
        LD (ES0),A
        POP HL
        CALL TMIN
        LD B,A
        LD DE,(EM0)
        OR A
        SBC HL,DE
        JR NC,EL1
        LD DE,1440
        ADD HL,DE
EL1:    LD A,(ES0)
        LD C,A
        LD A,B
        SUB C
        JR NC,EL2
        ADD A,60
        DEC HL
EL2:    PUSH AF
        CALL PNUM
        LD DE,M_MIN
        CALL PSTR
        POP AF
        LD L,A
        LD H,0
        CALL PNUM
        LD DE,M_SEC
        JP PSTR
; INICIO / FIN: hora de inicio y tiempo total
INICIO: LD HL,TM0
        CALL GETT
        LD DE,M_START
        CALL PSTR
        LD HL,TM0
        CALL PTIME
        JP CRLF
FIN:    LD HL,TM1
        CALL GETT
        LD DE,M_END
        CALL PSTR
        LD HL,TM1
        CALL PTIME
        LD DE,M_TIME
        CALL PSTR
        LD HL,TM0
        LD DE,TM1
        CALL ELAPS
        JP CRLF

M_START: DEFB 'Start: $'
M_END:  DEFB 'End:   $'
M_TIME: DEFB '  ($'
M_MIN:  DEFB ' min $'
M_SEC:  DEFB ' s)$'
N32:    DEFS 4
TSEC:   DEFB 0
EM0:    DEFW 0
ES0:    DEFB 0
TM0:    DEFS 8
TM1:    DEFS 8
