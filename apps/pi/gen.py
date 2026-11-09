# Genera pi.asm: pi con NDIG decimales, formula de Machin en base 256, CP/M .COM
import sys
BARE = len(sys.argv)>2 and sys.argv[2]=='bare'
o=[]
CPM_IO = '''PCH:    PUSH HL
        PUSH DE
        PUSH BC
        LD E,A
        LD C,2
        CALL BDOS
        POP BC
        POP DE
        POP HL
        RET
PSTR:   LD C,9
        JP BDOS
'''
# Sin sistema operativo: el SIO A (datos 81h, control 83h) por sondeo, con las
# interrupciones apagadas. ZIOS solo se usa para leer el reloj (RST 30h, C=28).
BARE_IO = '''PCH:    PUSH AF
PCH1:   IN A,(83h)
        BIT 2,A         ; RR0 bit 2: transmisor vacio
        JR Z,PCH1
        POP AF
        OUT (81h),A
        RET
PSTR:   LD A,(DE)
        CP '$'
        RET Z
        CALL PCH
        INC DE
        JR PSTR
'''
def e(s): o.append(s)
e("""; PI.COM / PI10K.COM - pi con NDIG decimales para la Z80-Retro (CP/M 2.2 o 3)
; pi = 16 atan(1/5) - 4 atan(1/239), punto fijo en base 256 (byte 0 = parte entera).
; La conversion a decimal multiplica la fraccion por 10000 con una tabla.
; La hora de inicio y fin sale del DS1307 por el API de ZIOS (RST 30h, C=28).
; Generado por gen.py.
BDOS    EQU 5
NFRAC   EQU NDIG*10/24+8        ; bytes de fraccion (0,4167 > log256(10) = 0,4152) + guarda
LEN     EQU NFRAC+1
NGRP    EQU NDIG/4
        ORG 100h
        LD SP,STACK
        LD DE,M_HDR
        CALL PSTR
        LD HL,T0
        CALL GETT
        LD DE,M_START
        CALL PSTR
        LD HL,T0
        CALL PTIME
        CALL CRLF
""")
e("""; --- ARS = 0
        LD HL,ARS
        LD BC,LEN
        CALL ZERO
        ; --- 16 atan(1/5)
        LD A,16
        LD DE,5
        LD BC,25
        CALL ATAN
        ; --- -4 atan(1/239)
        LD A,0FFh
        LD (NEG),A
        LD A,4
        LD DE,239
        LD BC,57121
        CALL ATAN
        LD HL,T1
        CALL GETT
        LD DE,M_COMP
        CALL PSTR
        LD HL,T1
        CALL PTIME
        CALL CRLF
        CALL CRLF
        ; --- imprimir "3."
        LD A,(ARS)
        ADD A,'0'
        CALL PCH
        LD A,'.'
        CALL PCH
        CALL CRLF
        CALL TODEC
        CALL CRLF
        LD HL,T2
        CALL GETT
        LD DE,M_END
        CALL PSTR
        LD HL,T2
        CALL PTIME
        LD DE,M_CALC
        CALL PSTR
        LD HL,T0
        LD DE,T1
        CALL ELAPS
        LD DE,M_TOT
        CALL PSTR
        LD HL,T0
        LD DE,T2
        CALL ELAPS
        CALL CRLF
""" + ("        EI\n        LD C,0\n        RST 30h\n" if BARE else "        JP 0\n") + """
; ===== ATAN: ARS += signo * A * atan(1/DE), BC = DE^2
ATAN:   LD (DIVX),DE
        LD (DIVX2),BC
        PUSH AF
        LD HL,ART
        LD BC,LEN
        CALL ZERO
        POP AF
        LD (ART),A
        LD HL,0
        LD (TST),HL
        LD HL,1
        LD (KK),HL
        ; ART = ART / x
        LD DE,(DIVX)
        LD HL,ART
        LD (DSRC),HL
        LD (DDST),HL
        CALL DIVT
        ; ARS +/- ART
        LD HL,ART
        CALL ADDS
AT_LP:  ; ART = ART / x^2
        LD DE,(DIVX2)
        LD HL,(TST)
        LD BC,ART
        ADD HL,BC
        LD (DSRC),HL
        LD (DDST),HL
        CALL DIVT
        ; saltar ceros iniciales de ART
        LD HL,(TST)
        LD BC,ART
        ADD HL,BC
SKZ:    LD A,(HL)
        OR A
        JR NZ,SKZ2
        INC HL
        PUSH HL
        LD BC,ART+LEN
        OR A
        SBC HL,BC
        POP HL
        RET Z           ; ART = 0: termino
        JR SKZ
SKZ2:   LD BC,ART
        OR A
        SBC HL,BC
        LD (TST),HL
        ; k += 2
        LD HL,(KK)
        INC HL
        INC HL
        LD (KK),HL
        ; ARW = ART / k
        EX DE,HL
        LD HL,(TST)
        LD BC,ART
        ADD HL,BC
        LD (DSRC),HL
        LD HL,(TST)
        LD BC,ARW
        ADD HL,BC
        LD (DDST),HL
        CALL DIVT
        ; cambiar el signo y sumar
        LD A,(NEG)
        CPL
        LD (NEG),A
        LD HL,ARW
        CALL ADDS
        JP AT_LP

; ===== DIVT: (DDST..) = (DSRC..) / DE, desde TST hasta el final
; Elige la rutina de 8 bits si DE < 128.
DIVT:   LD HL,(TST)
        EX DE,HL        ; HL = divisor, DE = TST
        PUSH HL
        LD HL,LEN
        OR A
        SBC HL,DE       ; HL = bytes
        LD B,H
        LD C,L
        POP DE          ; divisor
        LD A,D
        OR A
        JR NZ,DIV16
        LD A,E
        CP 128
        JR NC,DIV16
        JP DIV8
""")
# DIV16: alt regs: HL' src, DE' dst, BC' count ; main: HL rem, DE divisor, A byte
e("""DIV16:  PUSH BC
        LD HL,(DSRC)
        PUSH HL
        LD HL,(DDST)
        PUSH HL
        EXX
        POP DE
        POP HL
        POP BC
        EXX
        LD HL,0
D16LP:  EXX
        LD A,(HL)
        INC HL
        EXX""")
for i in range(8):
    e(f"""        SLA A
        ADC HL,HL
        JR C,D16O{i}
        SBC HL,DE
        JR NC,D16S{i}
        ADD HL,DE
        JR D16N{i}
D16O{i}: OR A
        SBC HL,DE
D16S{i}: INC A
D16N{i}:""")
e("""        EXX
        LD (DE),A
        INC DE
        DEC BC
        LD A,B
        OR C
        EXX
        JP NZ,D16LP
        RET
; DIV8: divisor E < 128. HL src, DE dst (se usan IX para el destino), resto en A
DIV8:   LD D,E          ; D = divisor
        LD HL,(DSRC)
        LD IX,(DDST)
        LD A,C          ; contador: E = vueltas de 256, B = resto
        OR A
        JR Z,D8A
        INC B
D8A:    LD E,B
        LD B,C
        XOR A           ; resto
D8LP:   LD C,(HL)
        INC HL""")
for i in range(8):
    e(f"""        SLA C
        RLA
        CP D
        JR C,D8N{i}
        SUB D
        INC C
D8N{i}:""")
e("""        LD (IX+0),C
        INC IX
        DJNZ D8LP
        DEC E
        JR NZ,D8LP
        RET

; ===== ADDS: ARS +/- (HL..) desde TST hasta el final (NEG = FF resta)
ADDS:   LD BC,LEN-1
        ADD HL,BC
        EX DE,HL        ; DE = fin de la fuente
        LD HL,ARS+LEN-1
        PUSH HL
        LD HL,LEN
        LD BC,(TST)
        OR A
        SBC HL,BC       ; bytes
        LD B,L
        LD C,H
        LD A,B
        OR A
        JR Z,AD1
        INC C
AD1:    POP HL
        LD A,(NEG)
        OR A
        JR NZ,SUBL
        OR A            ; acarreo 0
ADDL:   LD A,(DE)
        ADC A,(HL)
        LD (HL),A
        DEC HL
        DEC DE
        DJNZ ADDL
        DEC C
        JR NZ,ADDL
ADDP:   RET NC
        LD A,(HL)
        ADD A,1
        LD (HL),A
        DEC HL
        JR ADDP
SUBL:   OR A
SUBL1:  LD A,(HL)
        EX DE,HL
        SBC A,(HL)
        EX DE,HL
        LD (HL),A
        DEC HL
        DEC DE
        DJNZ SUBL1
        DEC C
        JR NZ,SUBL1
SUBP:   RET NC
        LD A,(HL)
        SUB 1
        LD (HL),A
        DEC HL
        JR SUBP

; ===== TODEC: NGRP pasadas de x10000 sobre la fraccion; imprime 4 cifras cada una
TODEC:  LD HL,ARS+LEN-1
        LD (CEND),HL
        LD HL,NGRP
        LD (GCNT),HL
        XOR A
        LD (GLIN),A
        LD (DACC),A
TDLP:   LD DE,(CEND)
        LD BC,0         ; acarreo
TDB:    LD A,(DE)
        LD L,A
        LD H,TB0/256
        LD A,(HL)
        ADD A,C
        LD (DE),A
        INC H
        LD A,(HL)
        ADC A,B
        LD C,A
        INC H
        LD A,(HL)
        ADC A,0
        LD B,A
        DEC DE
        LD A,E
        CP ARS & 255
        JR NZ,TDB
        LD A,D
        CP ARS / 256
        JR NZ,TDB
        ; BC = grupo de 4 cifras
        LD H,B
        LD L,C
        CALL P4D
        LD A,(GLIN)
        INC A
        CP 16
        JR NZ,TDL2
        CALL CRLF
        XOR A
TDL2:   LD (GLIN),A
        ; bajar el final: 33 bytes cada 20 pasadas (1,65 < log256(10000) = 1,661)
        LD A,(DACC)
        ADD A,33
TDD:    CP 20
        JR C,TDD2
        SUB 20
        LD HL,(CEND)
        DEC HL
        LD (CEND),HL
        JR TDD
TDD2:   LD (DACC),A
        LD HL,(GCNT)
        DEC HL
        LD (GCNT),HL
        LD A,H
        OR L
        JR NZ,TDLP
        RET

; ===== utilidades
ZERO:   LD (HL),0
        INC HL
        DEC BC
        LD A,B
        OR C
        JR NZ,ZERO
        RET
""" + (BARE_IO if BARE else CPM_IO) + """CRLF:   LD A,13
        CALL PCH
        LD A,10
        JP PCH
; P4D: HL (0-9999) con 4 cifras
P4D:    LD DE,1000
        CALL PDG
        LD DE,100
        CALL PDG
        LD DE,10
        CALL PDG
        LD A,L
        ADD A,'0'
        JP PCH
PDG:    LD A,'0'-1
PDG1:   INC A
        OR A
        SBC HL,DE
        JR NC,PDG1
        ADD HL,DE
        JP PCH
; PNUM: HL sin ceros a la izquierda
PNUM:   LD DE,10000
        LD B,0
        CALL PNG
        LD DE,1000
        CALL PNG
        LD DE,100
        CALL PNG
        LD DE,10
        CALL PNG
        LD A,L
        ADD A,'0'
        JP PCH
PNG:    LD A,'0'-1
PNG1:   INC A
        OR A
        SBC HL,DE
        JR NC,PNG1
        ADD HL,DE
        CP '0'
        JR NZ,PNG2
        INC B
        DEC B
        RET Z
PNG2:   LD B,1
        JP PCH
; GETT: HL = buffer de 6 bytes (seg, min, hora, dia, mes, ano en BCD)
GETT:   LD C,28
        RST 30h
""" + ("        DI\n" if BARE else "") + """        RET
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
BCD2B:  ; A (BCD) -> A binario
        PUSH BC
        LD B,A
        AND 0F0h
        RRCA
        LD C,A          ; decenas*8
        RRCA
        RRCA            ; decenas*2
        ADD A,C         ; decenas*10
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
        ADD HL,HL       ; x2
        ADD HL,HL       ; x4
        PUSH HL
        ADD HL,HL       ; x8
        ADD HL,HL       ; x16
        ADD HL,HL       ; x32
        ADD HL,HL       ; x64
        POP BC
        OR A
        SBC HL,BC       ; x60
        LD D,0
        ADD HL,DE
        LD A,(TSEC)
        RET
; ELAPS: tiempo de (HL) a (DE): imprime "N min ARS s"
ELAPS:  PUSH DE
        CALL TMIN
        LD (EM0),HL
        LD (ES0),A
        POP HL
        CALL TMIN
        LD B,A          ; segundos fin
        LD DE,(EM0)
        OR A
        SBC HL,DE       ; minutos
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
""")
e(f"""M_HDR:  DEFB 13,10,'PI, {sys.argv[1]} decimals (Machin, base 256){', no OS' if BARE else ''}',13,10,'$'
M_START: DEFB 'Start:    $'
M_COMP: DEFB 'Computed: $'
M_END:  DEFB 'End:      $'
M_CALC: DEFB 13,10,'Computing: $'
M_TOT:  DEFB 13,10,'Total:     $'
M_MIN:  DEFB ' min $'
M_SEC:  DEFB ' s$'
NEG:    DEFB 0
DIVX:   DEFW 0
DIVX2:  DEFW 0
TST:    DEFW 0
KK:     DEFW 0
DSRC:   DEFW 0
DDST:   DEFW 0
CEND:   DEFW 0
GCNT:   DEFW 0
GLIN:   DEFB 0
DACC:   DEFB 0
TSEC:   DEFB 0
EM0:    DEFW 0
ES0:    DEFB 0
T0:     DEFS 8
T1:     DEFS 8
T2:     DEFS 8
        DEFS 128
STACK:
        ORG ($+255)/256*256
TB0:""")
for k in range(3):
    vals=[((b*10000)>>(8*k))&255 for b in range(256)]
    for i in range(0,256,16):
        e("        DEFB "+",".join(str(v) for v in vals[i:i+16]))
e("""ARS       EQU TB0+768
ART       EQU ARS+LEN
ARW       EQU ART+LEN
        END""")
print("\n".join(o))
