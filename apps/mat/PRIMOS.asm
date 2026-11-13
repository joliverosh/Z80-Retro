N EQU 1000000
NLO EQU 16960
NHI EQU 15
SQ EQU 1000
SEGS EQU 31
LASTLEN EQU 8480
; PRIMOS - cuenta los primos hasta N con una criba segmentada de impares.
; Un byte por impar (1 = posible primo, 0 = compuesto); segmentos de 16 KB en
; 4000h-7FFFh (32.768 numeros cada uno). Los primos chicos (hasta raiz de N)
; salen de una criba previa y guardan su proximo multiplo en 32 bits.
; Constantes que pone mk.sh: N, SQ (raiz entera), SEGS, LASTLEN, NHI/NLO.
        ORG 100h
        LD SP,STACK
        LD DE,M_HDR
        CALL PSTR
        LD HL,NLO
        LD (N32),HL
        LD HL,NHI
        LD (N32+2),HL
        CALL P32
        CALL CRLF
        CALL INICIO
        ; ---- criba chica: impares hasta SQ en SBUF (indice i = numero 2i+1)
        LD HL,SBUF
        LD BC,SQI+1
        CALL FILL1
        LD HL,1         ; i
SC1:    PUSH HL
        ADD HL,HL
        INC HL          ; p = 2i+1
        LD E,L
        LD D,H
        PUSH HL
        CALL MUL16      ; DEHL = p*p
        POP BC          ; BC = p
        LD A,D
        OR E
        JR NZ,SCEND
        PUSH HL
        LD DE,SQ+1
        OR A
        SBC HL,DE
        POP HL
        JR NC,SCEND     ; p*p > SQ
        POP DE          ; DE = i
        PUSH DE
        PUSH HL
        LD HL,SBUF
        ADD HL,DE
        LD A,(HL)
        POP HL
        OR A
        JR Z,SCN
        SRL H           ; (p*p-1)/2
        RR L
SC2:    PUSH HL
        LD DE,SQI+1
        OR A
        SBC HL,DE
        POP HL
        JR NC,SCN
        PUSH HL
        LD DE,SBUF
        ADD HL,DE
        LD (HL),0
        POP HL
        ADD HL,BC
        JR SC2
SCN:    POP HL
        INC HL
        JR SC1
SCEND:  POP HL
        ; ---- tabla de primos: p (2 bytes) y proximo indice (4 bytes) = (p*p-1)/2
        LD IX,PT
        LD HL,1
        LD BC,0         ; cuantos
PTL:    PUSH HL
        LD DE,SQI+1
        OR A
        SBC HL,DE
        POP HL
        JR NC,PTEND
        PUSH HL
        LD DE,SBUF
        ADD HL,DE
        LD A,(HL)
        POP HL
        OR A
        JR Z,PTN
        PUSH HL
        PUSH BC
        ADD HL,HL
        INC HL          ; p
        LD (IX+0),L
        LD (IX+1),H
        LD E,L
        LD D,H
        CALL MUL16      ; DEHL = p*p (impar)
        SRL D
        RR E
        RR H
        RR L
        LD (IX+2),L
        LD (IX+3),H
        LD (IX+4),E
        LD (IX+5),D
        LD DE,6
        ADD IX,DE
        POP BC
        INC BC
        POP HL
PTN:    INC HL
        JR PTL
PTEND:  LD (NPR),BC
        ; ---- segmentos
        LD HL,4000h
        LD BC,4000h
        CALL FILL1
        XOR A
        LD (4000h),A    ; el 1 no es primo
        LD HL,0
        LD (SEG),HL
SEGL:   CALL SIEVE
        LD HL,(SEG)
        LD DE,SEGS-1
        OR A
        SBC HL,DE
        JR Z,LAST
        CALL CNTF
        LD HL,(SEG)
        INC HL
        LD (SEG),HL
        JR SEGL
LAST:   ; mayor primo: buscar hacia atras en el ultimo segmento
        LD HL,4000h+LASTLEN-1
LS1:    LD A,(HL)
        OR A
        JR NZ,LS2
        DEC HL
        JR LS1
LS2:    LD DE,4000h
        OR A
        SBC HL,DE       ; i
        ADD HL,HL
        INC HL          ; 2i+1
        LD (BIG),HL
        LD HL,(SEG)     ; SEG << 15 en 32 bits
        LD DE,0
        LD B,15
LS3:    ADD HL,HL
        RL E
        RL D
        DJNZ LS3
        LD BC,(BIG)
        ADD HL,BC
        JR NC,LS4
        INC DE
LS4:    LD (BIG),HL
        LD (BIG+2),DE
        ; contar el ultimo segmento
        LD HL,4000h
        LD BC,LASTLEN
LC1:    LD A,(HL)
        CALL ADDT
        INC HL
        DEC BC
        LD A,B
        OR C
        JR NZ,LC1
        ; ---- resultado
        LD DE,M_CNT
        CALL PSTR
        LD HL,(TOT)
        LD (N32),HL
        LD HL,(TOT+2)
        LD (N32+2),HL
        CALL P32
        CALL CRLF
        LD DE,M_BIG
        CALL PSTR
        LD HL,(BIG)
        LD (N32),HL
        LD HL,(BIG+2)
        LD (N32+2),HL
        CALL P32
        CALL CRLF
        CALL FIN
        JP 0

; SIEVE: tacha en el segmento actual los multiplos de cada primo chico
SIEVE:  LD IX,PT
        LD BC,(NPR)
SVL:    PUSH BC
        LD A,(IX+4)
        OR (IX+5)
        JR NZ,SVFAR
        LD L,(IX+2)
        LD H,(IX+3)
        LD A,H
        CP 40h
        JR NC,SVFAR
        SET 6,H         ; + 4000h
        LD E,(IX+0)
        LD D,(IX+1)
        LD C,0
MK:     LD (HL),C
        ADD HL,DE
        BIT 7,H
        JR Z,MK
        RES 7,H         ; indice en el segmento siguiente
        LD (IX+2),L
        LD (IX+3),H
        JR SVN
SVFAR:  LD A,(IX+3)     ; proximo -= 4000h
        SUB 40h
        LD (IX+3),A
        JR NC,SVN
        LD A,(IX+4)
        SUB 1
        LD (IX+4),A
        JR NC,SVN
        DEC (IX+5)
SVN:    LD DE,6
        ADD IX,DE
        POP BC
        DEC BC
        LD A,B
        OR C
        JR NZ,SVL
        RET

; CNTF: cuenta un segmento entero y lo deja otra vez en 1
CNTF:   LD HL,4000h
        LD B,128
        LD C,1
CF1:    XOR A
        REPT 128
        ADD A,(HL)
        LD (HL),C
        INC HL
        ENDM
        CALL ADDT
        DEC B
        JP NZ,CF1
        RET
; ADDT: TOT += A
ADDT:   PUSH HL
        PUSH DE
        LD HL,(TOT)
        LD E,A
        LD D,0
        ADD HL,DE
        LD (TOT),HL
        JR NC,ADT1
        LD HL,(TOT+2)
        INC HL
        LD (TOT+2),HL
ADT1:   POP DE
        POP HL
        RET
; FILL1: BC bytes en 1 desde HL
FILL1:  LD (HL),1
        DEC BC
        LD A,B
        OR C
        RET Z
        LD D,H
        LD E,L
        INC DE
        LDIR
        RET
; MUL16: DEHL = HL * DE
MUL16:  LD B,H
        LD C,L
        LD HL,0
        LD A,16
MU1:    ADD HL,HL
        RL E
        RL D
        JR NC,MU2
        ADD HL,BC
        JR NC,MU2
        INC DE
MU2:    DEC A
        JR NZ,MU1
        RET

INCLUDE comun.inc

M_HDR:  DEFB 13,10,'PRIMOS: counting the primes up to $'
M_CNT:  DEFB 'Primes: $'
M_BIG:  DEFB 'Largest: $'
TOT:    DEFW 1,0        ; el 2
BIG:    DEFW 0,0
SEG:    DEFW 0
NPR:    DEFW 0
        DEFS 128
STACK:
SQI     EQU (SQ-1)/2
SBUF    EQU 1000h
PT      EQU SBUF+SQI+16
        IF PT+6*1300 GT 4000h
        ERROR 'tabla de primos demasiado grande'
        ENDIF
        END
