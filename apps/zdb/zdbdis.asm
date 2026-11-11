; zdbdis.asm - desensamblador Z80 de ZDB (mnemonicos de Zilog)
; DIS: HL = direccion. Deja el texto en DBUF (0 al final), la siguiente
; direccion en DNEXT y en HL, y la longitud en DLEN.
; Decodifica por campos: x = bits 7-6, y = 5-3, z = 2-0, p = y/2, q = y AND 1.
; Las plantillas son cadenas con codigos >= 80h que imprimen operandos.

TRY     EQU     80h             ; r[y]
TRZ     EQU     81h             ; r[z]
TRPP    EQU     82h             ; rp[p]  (HL -> IX/IY)
TRP2    EQU     83h             ; rp2[p] (HL -> IX/IY)
TCCY    EQU     84h             ; cc[y]
TCC4    EQU     85h             ; cc[y-4]
TN8     EQU     86h             ; byte inmediato
TN16    EQU     87h             ; palabra inmediata
TREL    EQU     88h             ; destino de JR/DJNZ
TALU    EQU     89h             ; ADD A, / SUB / ...
TROT    EQU     8Ah             ; RLC / RRC / ...
TYN     EQU     8Bh             ; digito y (BIT)
TRST    EQU     8Ch             ; y*8
TIMY    EQU     8Dh             ; modo IM
THLX    EQU     8Eh             ; HL / IX / IY
TPORT   EQU     8Fh             ; (n)
TNNM    EQU     90h             ; (nn)
TMEMX   EQU     91h             ; (IX+d) con d ya leido (DD CB d op)
TORZ    EQU     92h             ; ",r[z]" si z <> 6 (DD CB no documentadas)
TOPB    EQU     93h             ; el byte OP en hexadecimal

DIS:    LD      (DPC),HL
        LD      (FP),HL
        LD      DE,DBUF
        LD      (DPTR),DE
        XOR     A
        LD      (IXF),A
        LD      (NOSUB),A
        LD      (USED),A
        LD      (DFL),A
        CALL    DDEC
        LD      A,(IXF)         ; prefijo DD/FD que no cambia nada: va solo
        OR      A
        JR      Z,DIS2
        LD      A,(USED)
        OR      A
        JR      NZ,DIS2
        LD      HL,(DPC)
        LD      A,(HL)
        LD      (OP),A
        INC     HL
        LD      (FP),HL
        LD      HL,DBUF
        LD      (DPTR),HL
        XOR     A
        LD      (IXF),A
        LD      HL,T_DBOP
        CALL    TPL
DIS2:   XOR     A
        CALL    PUT
        LD      HL,(FP)
        LD      (DNEXT),HL
        LD      DE,(DPC)
        PUSH    HL
        OR      A
        SBC     HL,DE
        LD      A,L
        LD      (DLEN),A
        POP     HL
        RET

; FB: siguiente byte de la instruccion
FB:     PUSH    HL
        LD      HL,(FP)
        LD      A,(HL)
        INC     HL
        LD      (FP),HL
        POP     HL
        RET

; PUT: un caracter al texto
PUT:    PUSH    HL
        LD      HL,(DPTR)
        LD      (HL),A
        INC     HL
        LD      (DPTR),HL
        POP     HL
        RET

; SPLIT: A -> OP, X, Y, Z, P, Q
SPLIT:  LD      (OP),A
        LD      B,A
        AND     7
        LD      (VZ),A
        LD      A,B
        RRCA
        RRCA
        RRCA
        AND     7
        LD      (VY),A
        LD      C,A
        AND     1
        LD      (VQ),A
        LD      A,C
        RRCA
        AND     3
        LD      (VP),A
        LD      A,B
        RLCA
        RLCA
        AND     3
        LD      (VX),A
        RET

; TSEL: HL = tabla de plantillas, A = indice
TSEL:   ADD     A,A
        LD      E,A
        LD      D,0
        ADD     HL,DE
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        JP      TPL

; JTAB: HL = tabla de rutinas, A = indice
JTAB:   ADD     A,A
        LD      E,A
        LD      D,0
        ADD     HL,DE
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        JP      (HL)

DDEC:   CALL    FB
        CP      0DDh
        JR      Z,DIX
        CP      0FDh
        JR      Z,DIY
        CP      0EDh
        JP      Z,DED
        CP      0CBh
        JP      Z,DCB
        JP      DMAIN
DIX:    LD      B,1
        JR      DIXY
DIY:    LD      B,2
DIXY:   LD      (OP),A
        LD      HL,(FP)         ; DD/FD seguido de otro prefijo: va solo
        LD      A,(HL)
        CP      0DDh
        JR      Z,DLONE
        CP      0FDh
        JR      Z,DLONE
        CP      0EDh
        JR      Z,DLONE
        LD      A,B
        LD      (IXF),A
        CALL    FB
        CP      0CBh
        JP      Z,DXCB
        JP      DMAIN
DLONE:  LD      HL,T_DBOP
        JP      TPL

DMAIN:  CALL    SPLIT
        LD      A,(VX)
        LD      HL,XTAB
        JP      JTAB
XTAB:   DW      DX0,DX1,DX2,DX3

DX1:    LD      A,(OP)
        CP      76h
        LD      HL,T_HALT
        JP      Z,TPL
        LD      A,(VY)
        CP      6
        JR      Z,DX1M
        LD      A,(VZ)
        CP      6
        JR      NZ,DX1R
DX1M:   LD      A,1             ; LD r,(IX+d): el otro registro es el normal
        LD      (NOSUB),A
DX1R:   LD      HL,T_LDRR
        JP      TPL
DX2:    LD      HL,T_ALUR
        JP      TPL

DX0:    LD      A,(VZ)
        LD      HL,X0TAB
        JP      JTAB
X0TAB:  DW      X0Z0,X0Z1,X0Z2,X0Z3,X0Z4,X0Z5,X0Z6,X0Z7
X0Z0:   LD      A,(VY)
        LD      HL,X0Z0T
        JP      TSEL
X0Z1:   LD      A,(VQ)
        LD      HL,X0Z1T
        JP      TSEL
X0Z2:   LD      A,(VY)
        LD      HL,X0Z2T
        JP      TSEL
X0Z3:   LD      A,(VQ)
        LD      HL,X0Z3T
        JP      TSEL
X0Z4:   LD      HL,T_INCR
        JP      TPL
X0Z5:   LD      HL,T_DECR
        JP      TPL
X0Z6:   LD      HL,T_LDRN
        JP      TPL
X0Z7:   LD      A,(VY)
        LD      HL,X0Z7T
        JP      TSEL

DX3:    LD      A,(VZ)
        LD      HL,X3TAB
        JP      JTAB
X3TAB:  DW      X3Z0,X3Z1,X3Z2,X3Z3,X3Z4,X3Z5,X3Z6,X3Z7
X3Z0:   LD      HL,T_RETCC
        JP      TPL
X3Z1:   LD      A,(VQ)
        OR      A
        LD      HL,T_POP
        JP      Z,TPL
        LD      A,(VP)
        LD      HL,X3Z1T
        JP      TSEL
X3Z2:   LD      HL,T_JPCC
        JP      TPL
X3Z3:   LD      A,(VY)
        LD      HL,X3Z3T
        JP      TSEL
X3Z4:   LD      HL,T_CALLCC
        JP      TPL
X3Z5:   LD      A,(VQ)
        OR      A
        LD      HL,T_PUSH
        JP      Z,TPL
        LD      HL,T_CALL       ; CD (DD, ED y FD no llegan aqui)
        JP      TPL
X3Z6:   LD      HL,T_ALUN
        JP      TPL
X3Z7:   LD      HL,T_RST
        JP      TPL

; CB sin prefijo
DCB:    CALL    FB
        CALL    SPLIT
        LD      A,(VX)
        LD      HL,CBTAB
        JP      TSEL
; DD CB d op / FD CB d op
DXCB:   CALL    FB
        LD      (DISP),A
        LD      A,1
        LD      (DFL),A
        LD      (NOSUB),A
        LD      (USED),A
        CALL    FB
        CALL    SPLIT
        LD      A,(VX)
        LD      HL,XCBTAB
        JP      TSEL

; ED
DED:    CALL    FB
        CALL    SPLIT
        LD      A,(VX)
        CP      1
        JR      Z,DE1
        CP      2
        JR      NZ,DEBAD
        LD      A,(VZ)          ; x = 2: instrucciones de bloque
        CP      4
        JR      NC,DEBAD
        LD      B,A
        LD      A,(VY)
        SUB     4
        JR      C,DEBAD
        ADD     A,A
        ADD     A,A
        ADD     A,B
        LD      HL,BLKT
        JP      TSEL
DEBAD:  LD      HL,T_DBED
        JP      TPL
DE1:    LD      A,(VZ)
        LD      HL,E1TAB
        JP      JTAB
E1TAB:  DW      E1Z0,E1Z1,E1Z2,E1Z3,E1Z4,E1Z5,E1Z6,E1Z7
E1Z0:   LD      A,(VY)
        CP      6
        LD      HL,T_INF
        JP      Z,TPL
        LD      HL,T_INRC
        JP      TPL
E1Z1:   LD      A,(VY)
        CP      6
        LD      HL,T_OUT0
        JP      Z,TPL
        LD      HL,T_OUTCR
        JP      TPL
E1Z2:   LD      A,(VQ)
        LD      HL,E1Z2T
        JP      TSEL
E1Z3:   LD      A,(VQ)
        LD      HL,E1Z3T
        JP      TSEL
E1Z4:   LD      HL,T_NEG
        JP      TPL
E1Z5:   LD      A,(VY)
        CP      1
        LD      HL,T_RETI
        JP      Z,TPL
        LD      HL,T_RETN
        JP      TPL
E1Z6:   LD      HL,T_IM
        JP      TPL
E1Z7:   LD      A,(VY)
        CP      6
        JR      NC,DEBAD
        LD      HL,E1Z7T
        JP      TSEL

; TPL: interpreta la plantilla en HL
TPL:    LD      A,(HL)
        INC     HL
        OR      A
        RET     Z
        JP      M,TPL1
        CALL    PUT
        JR      TPL
TPL1:   PUSH    HL
        AND     7Fh
        LD      HL,TCODE
        CALL    JTABC
        POP     HL
        JR      TPL
JTABC:  JP      JTAB
TCODE:  DW      H_RY,H_RZ,H_RPP,H_RP2,H_CCY,H_CC4,H_N8,H_N16
        DW      H_REL,H_ALU,H_ROT,H_YN,H_RST,H_IMY,H_HLX,H_PORT
        DW      H_NNM,H_MEMX,H_ORZ,H_OPB

H_RY:   LD      A,(VY)
        JR      PREG
H_RZ:   LD      A,(VZ)
PREG:   CP      6
        JR      Z,PMEM
        LD      C,A
        CP      4
        JR      C,PREG1
        CP      6
        JR      NC,PREG1
        LD      A,(IXF)         ; H o L con DD/FD: IXH, IXL, IYH, IYL
        OR      A
        JR      Z,PREG1
        LD      A,(NOSUB)
        OR      A
        JR      NZ,PREG1
        CALL    PIXY
        LD      A,C
        CP      4
        LD      A,'H'
        JP      Z,PUT
        LD      A,'L'
        JP      PUT
PREG1:  LD      HL,RNAMES
        LD      B,0
        ADD     HL,BC
        LD      A,(HL)
        JP      PUT
RNAMES: DB      'BCDEHL?A'

; PMEM: (HL) o (IX+d)
PMEM:   LD      A,(IXF)
        OR      A
        JR      NZ,PMEM1
        LD      HL,S_MHL
        JP      PSTRB
PMEM1:  LD      A,'('
        CALL    PUT
        CALL    PIXY
        LD      A,(DFL)
        OR      A
        LD      A,(DISP)
        CALL    Z,FB
        LD      C,'+'
        OR      A
        JP      P,PMEM2
        NEG
        LD      C,'-'
PMEM2:  LD      B,A
        LD      A,C
        CALL    PUT
        LD      A,B
        CALL    BH2
        LD      A,')'
        JP      PUT
H_MEMX: JR      PMEM1

; PIXY: "IX" o "IY", y marca el prefijo como usado
PIXY:   LD      A,1
        LD      (USED),A
        LD      A,'I'
        CALL    PUT
        LD      A,(IXF)
        CP      1
        LD      A,'X'
        JP      Z,PUT
        LD      A,'Y'
        JP      PUT

H_HLX:  LD      A,(IXF)
        OR      A
        JR      NZ,PIXY
        LD      A,'H'
        CALL    PUT
        LD      A,'L'
        JP      PUT

H_RPP:  LD      A,(VP)
        CP      2
        JR      Z,H_HLX
PRP:    ADD     A,A
        LD      E,A
        LD      D,0
        LD      HL,RPN
        ADD     HL,DE
        LD      A,(HL)
        CALL    PUT
        INC     HL
        LD      A,(HL)
        JP      PUT
RPN:    DB      'BCDEHLSPAF'
H_RP2:  LD      A,(VP)
        CP      2
        JR      Z,H_HLX
        CP      3
        JR      NZ,PRP
        LD      A,4
        JR      PRP

H_CCY:  LD      A,(VY)
PCC:    ADD     A,A
        LD      E,A
        LD      D,0
        LD      HL,CCN
        ADD     HL,DE
        LD      B,2
        JP      PFIX
CCN:    DB      'NZZ NCC POPEP M '
H_CC4:  LD      A,(VY)
        AND     3
        JR      PCC

H_N8:   CALL    FB
        JP      BH2
H_N16:  CALL    FB
        LD      L,A
        CALL    FB
        LD      H,A
        JP      BH4
H_REL:  CALL    FB
        LD      E,A
        ADD     A,A
        SBC     A,A
        LD      D,A
        LD      HL,(FP)
        ADD     HL,DE
        JP      BH4
H_PORT: LD      A,'('
        CALL    PUT
        CALL    H_N8
PCLOSE: LD      A,')'
        JP      PUT
H_NNM:  LD      A,'('
        CALL    PUT
        CALL    H_N16
        JR      PCLOSE

H_ALU:  LD      A,(VY)
        LD      HL,ALUN
        CALL    P3N
        LD      A,(VY)          ; ADD, ADC y SBC llevan "A,"
        CP      2
        RET     Z
        CP      4
        RET     NC
        LD      HL,S_AC
        JP      PSTRB
ALUN:   DB      'ADDADCSUBSBCANDXOROR CP '
H_ROT:  LD      A,(VY)
        LD      HL,ROTN
        JP      P3N
ROTN:   DB      'RLCRRCRL RR SLASRASLLSRL'
; P3N: nombre de 3 letras numero A de la tabla HL, y un espacio
P3N:    LD      E,A
        ADD     A,A
        ADD     A,E
        LD      E,A
        LD      D,0
        ADD     HL,DE
        LD      B,3
        CALL    PFIX
        LD      A,' '
        JP      PUT
; PFIX: B caracteres de HL sin los espacios
PFIX:   LD      A,(HL)
        INC     HL
        CP      ' '
        CALL    NZ,PUT
        DJNZ    PFIX
        RET

H_YN:   LD      A,(VY)
        ADD     A,'0'
        JP      PUT
H_RST:  LD      A,(VY)
        ADD     A,A
        ADD     A,A
        ADD     A,A
        JP      BH2
H_IMY:  LD      A,(VY)
        AND     3
        LD      E,A
        LD      D,0
        LD      HL,IMN
        ADD     HL,DE
        LD      A,(HL)
        JP      PUT
IMN:    DB      '0012'
H_ORZ:  LD      A,(VZ)
        CP      6
        RET     Z
        LD      A,','
        CALL    PUT
        LD      A,(VZ)
        LD      C,A
        JP      PREG1
H_OPB:  LD      A,(OP)
        JP      BH2

; PSTRB: cadena con 0 al final al texto
PSTRB:  LD      A,(HL)
        OR      A
        RET     Z
        CALL    PUT
        INC     HL
        JR      PSTRB

; BH2: A en hexadecimal con H (y un 0 delante si empieza por letra)
BH2:    CP      0A0h
        JR      C,BH2A
        PUSH    AF
        LD      A,'0'
        CALL    PUT
        POP     AF
BH2A:   CALL    BHB
        LD      A,'H'
        JP      PUT
BH4:    LD      A,H
        CP      0A0h
        JR      C,BH4A
        LD      A,'0'
        CALL    PUT
BH4A:   LD      A,H
        CALL    BHB
        LD      A,L
        JR      BH2A
BHB:    PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    BHN
        POP     AF
BHN:    CALL    HEXC
        JP      PUT
HEXC:   AND     0Fh
        ADD     A,90h
        DAA
        ADC     A,40h
        DAA
        RET

S_MHL:  DB      '(HL)',0
S_AC:   DB      'A,',0

; plantillas
T_DBOP: DB      'DB ',TOPB,0
T_DBED: DB      'DB 0EDH,',TOPB,0
T_HALT: DB      'HALT',0
T_LDRR: DB      'LD ',TRY,',',TRZ,0
T_ALUR: DB      TALU,TRZ,0
T_ALUN: DB      TALU,TN8,0
T_INCR: DB      'INC ',TRY,0
T_DECR: DB      'DEC ',TRY,0
T_LDRN: DB      'LD ',TRY,',',TN8,0
X0Z0T:  DW      T_NOP,T_EXAF,T_DJNZ,T_JR,T_JRC,T_JRC,T_JRC,T_JRC
T_NOP:  DB      'NOP',0
T_EXAF: DB      'EX AF,AF',27h,0
T_DJNZ: DB      'DJNZ ',TREL,0
T_JR:   DB      'JR ',TREL,0
T_JRC:  DB      'JR ',TCC4,',',TREL,0
X0Z1T:  DW      T_LDRPN,T_ADDHL
T_LDRPN: DB     'LD ',TRPP,',',TN16,0
T_ADDHL: DB     'ADD ',THLX,',',TRPP,0
X0Z2T:  DW      T_STBC,T_LDBC,T_STDE,T_LDDE,T_SHLD,T_LHLD,T_STA,T_LDA
T_STBC: DB      'LD (BC),A',0
T_LDBC: DB      'LD A,(BC)',0
T_STDE: DB      'LD (DE),A',0
T_LDDE: DB      'LD A,(DE)',0
T_SHLD: DB      'LD ',TNNM,',',THLX,0
T_LHLD: DB      'LD ',THLX,',',TNNM,0
T_STA:  DB      'LD ',TNNM,',A',0
T_LDA:  DB      'LD A,',TNNM,0
X0Z3T:  DW      T_INCRP,T_DECRP
T_INCRP: DB     'INC ',TRPP,0
T_DECRP: DB     'DEC ',TRPP,0
X0Z7T:  DW      T_RLCA,T_RRCA,T_RLA,T_RRA,T_DAA,T_CPL,T_SCF,T_CCF
T_RLCA: DB      'RLCA',0
T_RRCA: DB      'RRCA',0
T_RLA:  DB      'RLA',0
T_RRA:  DB      'RRA',0
T_DAA:  DB      'DAA',0
T_CPL:  DB      'CPL',0
T_SCF:  DB      'SCF',0
T_CCF:  DB      'CCF',0
T_RETCC: DB     'RET ',TCCY,0
T_POP:  DB      'POP ',TRP2,0
X3Z1T:  DW      T_RET,T_EXX,T_JPHL,T_LDSP
T_RET:  DB      'RET',0
T_EXX:  DB      'EXX',0
T_JPHL: DB      'JP (',THLX,')',0
T_LDSP: DB      'LD SP,',THLX,0
T_JPCC: DB      'JP ',TCCY,',',TN16,0
X3Z3T:  DW      T_JP,T_DBOP,T_OUTN,T_INN,T_EXSP,T_EXDE,T_DI,T_EI
T_JP:   DB      'JP ',TN16,0
T_OUTN: DB      'OUT ',TPORT,',A',0
T_INN:  DB      'IN A,',TPORT,0
T_EXSP: DB      'EX (SP),',THLX,0
T_EXDE: DB      'EX DE,HL',0
T_DI:   DB      'DI',0
T_EI:   DB      'EI',0
T_CALLCC: DB    'CALL ',TCCY,',',TN16,0
T_PUSH: DB      'PUSH ',TRP2,0
T_CALL: DB      'CALL ',TN16,0
T_RST:  DB      'RST ',TRST,0
CBTAB:  DW      T_ROT,T_BIT,T_RES,T_SET
T_ROT:  DB      TROT,TRZ,0
T_BIT:  DB      'BIT ',TYN,',',TRZ,0
T_RES:  DB      'RES ',TYN,',',TRZ,0
T_SET:  DB      'SET ',TYN,',',TRZ,0
XCBTAB: DW      T_XROT,T_XBIT,T_XRES,T_XSET
T_XROT: DB      TROT,TMEMX,TORZ,0
T_XBIT: DB      'BIT ',TYN,',',TMEMX,0
T_XRES: DB      'RES ',TYN,',',TMEMX,TORZ,0
T_XSET: DB      'SET ',TYN,',',TMEMX,TORZ,0
T_INF:  DB      'IN F,(C)',0
T_INRC: DB      'IN ',TRY,',(C)',0
T_OUT0: DB      'OUT (C),0',0
T_OUTCR: DB     'OUT (C),',TRY,0
E1Z2T:  DW      T_SBC,T_ADC
T_SBC:  DB      'SBC HL,',TRPP,0
T_ADC:  DB      'ADC HL,',TRPP,0
E1Z3T:  DW      T_LDNNR,T_LDRNN
T_LDNNR: DB     'LD ',TNNM,',',TRPP,0
T_LDRNN: DB     'LD ',TRPP,',',TNNM,0
T_NEG:  DB      'NEG',0
T_RETI: DB      'RETI',0
T_RETN: DB      'RETN',0
T_IM:   DB      'IM ',TIMY,0
E1Z7T:  DW      T_LDIA,T_LDRA,T_LDAI,T_LDAR,T_RRD,T_RLD
T_LDIA: DB      'LD I,A',0
T_LDRA: DB      'LD R,A',0
T_LDAI: DB      'LD A,I',0
T_LDAR: DB      'LD A,R',0
T_RRD:  DB      'RRD',0
T_RLD:  DB      'RLD',0
BLKT:   DW      T_LDI,T_CPI,T_INI,T_OUTI,T_LDD,T_CPD,T_IND,T_OUTD
        DW      T_LDIR,T_CPIR,T_INIR,T_OTIR,T_LDDR,T_CPDR,T_INDR,T_OTDR
T_LDI:  DB      'LDI',0
T_CPI:  DB      'CPI',0
T_INI:  DB      'INI',0
T_OUTI: DB      'OUTI',0
T_LDD:  DB      'LDD',0
T_CPD:  DB      'CPD',0
T_IND:  DB      'IND',0
T_OUTD: DB      'OUTD',0
T_LDIR: DB      'LDIR',0
T_CPIR: DB      'CPIR',0
T_INIR: DB      'INIR',0
T_OTIR: DB      'OTIR',0
T_LDDR: DB      'LDDR',0
T_CPDR: DB      'CPDR',0
T_INDR: DB      'INDR',0
T_OTDR: DB      'OTDR',0

; variables del desensamblador
DPC:    DW      0
FP:     DW      0
DPTR:   DW      0
DNEXT:  DW      0
DLEN:   DB      0
OP:     DB      0
VX:     DB      0
VY:     DB      0
VZ:     DB      0
VP:     DB      0
VQ:     DB      0
IXF:    DB      0
NOSUB:  DB      0
USED:   DB      0
DFL:    DB      0
DISP:   DB      0
DBUF:   DS      32
