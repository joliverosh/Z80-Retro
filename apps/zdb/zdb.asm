; zdb.asm - ZDB, depurador Z80 para CP/M 2.2 y MP/M II (Z80-Retro)
; Se ensambla dos veces (RBASE = 0 y 100h); mkzdb.py saca de la diferencia
; el mapa de reubicacion y arma ZDB.COM con el cargador (zdbldr.asm), que
; copia esta parte justo debajo del BDOS y la reubica.
; Puntos de parada con RST 38h (la Z80-Retro trabaja en IM 2, 0038h esta libre).
; Mensajes en ingles; comentarios en espanol.

        ORG     RBASE

BDOS    EQU     5
M_GO    EQU     0               ; MODE: G corriendo
M_STEP  EQU     1               ; T o N
M_GOS   EQU     2               ; G con un punto de parada en PC: un paso y luego G
NPERM   EQU     8               ; puntos de parada permanentes
NBPT    EQU     12              ; puntos puestos a la vez (temporales + permanentes)

; (6) apunta aqui: el BDOS del programa pasa por ZDB
STUB:   JP      BDOSI
        JP      INIT
SYSBD:  JP      0               ; el BDOS de verdad

; las funciones 0 y 143 (terminar) vuelven a ZDB
BDOSI:  PUSH    AF
        LD      A,C
        OR      A
        JR      Z,BDT
        CP      143
        JR      Z,BDT
        POP     AF
        JP      SYSBD
BDT:    POP     AF
; TERM: el programa termino (BDOS 0, JP 0 o RET al principio)
TERM:   DI
        LD      SP,STACK
        EI
        LD      A,(RUNNING)
        OR      A
        JP      Z,QUIT          ; ^C de CP/M en el indicador de ZDB
        XOR     A
        LD      (RUNNING),A
        CALL    REMBP
        CALL    INITPC
        LD      HL,M_END
        JP      PERR

INIT:   LD      HL,(BDOS+1)
        LD      (SYSBD+1),HL
        LD      SP,STACK
        LD      HL,(1)
        LD      (OLD0),HL
        LD      HL,38h
        LD      DE,OLD38
        LD      BC,3
        LDIR
        LD      HL,STUB
        LD      (BDOS+1),HL
        LD      HL,TERM
        LD      (1),HL
        LD      A,0C3h
        LD      (38h),A
        LD      HL,BRK
        LD      (39h),HL
        CALL    INITPC
        LD      HL,M_BAN
        CALL    PSTR
        LD      HL,STUB-1
        CALL    PH4
        LD      HL,M_BAN2
        CALL    PSTR
        LD      A,(80h)         ; ZDB ARCHIVO [argumentos]
        OR      A
        JP      Z,CMDL
        LD      C,A
        LD      B,0
        LD      HL,81h
        LD      DE,IBUF+2
        LDIR
        XOR     A
        LD      (DE),A
        LD      HL,IBUF+2
        LD      DE,LFCB
        CALL    PFN
        CALL    SKSP
        CALL    SETTAIL
        LD      HL,0
        LD      (ROFF),HL
        JP      LOADF

; INITPC: PC = 100h y SP en el tope con 0000 encima (RET = terminar)
INITPC: LD      HL,100h
        LD      (R_PC),HL
        LD      HL,STUB-2
        LD      (R_SP),HL
        LD      (HL),0
        INC     HL
        LD      (HL),0
        RET

; ---------------------------------------------------------------- ordenes
CMDL:   LD      SP,STACK
        LD      A,'#'
        CALL    COUT
        CALL    READL
        LD      HL,(CPTR)
        CALL    SKSP
        OR      A
        JR      Z,CMDL
        INC     HL
        LD      (CPTR),HL
        LD      B,A
        LD      HL,CMDT
CM1:    LD      A,(HL)
        OR      A
        JP      Z,ERR
        CP      B
        JR      Z,CM2
        INC     HL
        INC     HL
        INC     HL
        JR      CM1
CM2:    INC     HL
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        JP      (HL)

CMDT:   DB      'D'
        DW      C_D
        DB      'L'
        DW      C_L
        DB      'G'
        DW      C_G
        DB      'T'
        DW      C_T
        DB      'N'
        DW      C_N
        DB      'B'
        DW      C_B
        DB      'K'
        DW      C_K
        DB      'X'
        DW      C_X
        DB      'S'
        DW      C_S
        DB      'F'
        DW      C_F
        DB      'M'
        DW      C_M
        DB      'H'
        DW      C_H
        DB      'I'
        DW      C_I
        DB      'R'
        DW      C_R
        DB      'W'
        DW      C_W
        DB      'Q'
        DW      QUIT
        DB      '?'
        DW      C_HLP
        DB      0

ERR:    LD      HL,M_ERR
; PERR: mensaje, fin de linea y al indicador
PERR:   CALL    PSTR
        CALL    CRLF
        JP      CMDL

C_HLP:  LD      HL,M_HELP
        CALL    PSTR
        JP      CMDL

QUIT:   LD      HL,(OLD0)
        LD      (1),HL
        LD      HL,(SYSBD+1)
        LD      (BDOS+1),HL
        LD      HL,OLD38
        LD      DE,38h
        LD      BC,3
        LDIR
        LD      C,0
        JP      SYSBD

; D[ini][,fin]: volcado
C_D:    CALL    NUMS
        BIT     0,A
        JR      Z,D1
        LD      HL,(ARGV)
        LD      (DADR),HL
D1:     LD      HL,(DADR)
        LD      DE,127
        ADD     HL,DE
        JR      NC,D1A
        LD      HL,0FFFFh
D1A:    LD      A,(ARGP)
        BIT     1,A
        JR      Z,D1B
        LD      HL,(ARGV+2)
D1B:    LD      (DEND),HL
D2:     LD      HL,(DADR)
        CALL    PH4
        CALL    SP2
        PUSH    HL
        LD      B,16
D3:     LD      A,(HL)
        CALL    PH2
        CALL    SPC
        INC     HL
        DJNZ    D3
        CALL    SPC
        POP     HL
        LD      B,16
D4:     LD      A,(HL)
        CP      ' '
        JR      C,D5
        CP      7Fh
        JR      C,D6
D5:     LD      A,'.'
D6:     CALL    COUT
        INC     HL
        DJNZ    D4
        CALL    CRLF
        LD      DE,(DADR)
        LD      (DADR),HL
        PUSH    HL
        OR      A
        SBC     HL,DE
        POP     DE
        JP      C,CMDL          ; dio la vuelta
        LD      HL,(DEND)
        OR      A
        SBC     HL,DE
        JP      C,CMDL
        CALL    KEYHIT
        JP      NZ,CMDL
        JR      D2

; L[ini][,fin]: desensamblado (12 instrucciones si no hay fin)
C_L:    CALL    NUMS
        BIT     0,A
        JR      Z,L1
        LD      HL,(ARGV)
        LD      (LADR),HL
L1:     LD      A,(ARGP)
        BIT     1,A
        JR      NZ,LR
        LD      B,12
L2:     PUSH    BC
        LD      HL,(LADR)
        CALL    PLINE
        LD      (LADR),HL
        POP     BC
        DJNZ    L2
        JP      CMDL
LR:     LD      HL,(LADR)
        PUSH    HL
        CALL    PLINE
        LD      (LADR),HL
        POP     DE
        PUSH    HL
        OR      A
        SBC     HL,DE
        POP     DE
        JP      C,CMDL
        LD      HL,(ARGV+2)
        OR      A
        SBC     HL,DE
        JP      C,CMDL
        CALL    KEYHIT
        JP      NZ,CMDL
        JR      LR

; PLINE: una linea "dir  bytes  instruccion"; HL = siguiente
PLINE:  PUSH    HL
        CALL    PH4
        CALL    SP2
        POP     HL
        PUSH    HL
        CALL    DIS
        POP     HL
        LD      A,(DLEN)
        LD      B,A
        LD      C,4
PL1:    LD      A,(HL)
        CALL    PH2
        CALL    SPC
        INC     HL
        DEC     C
        DJNZ    PL1
PL2:    LD      A,C
        OR      A
        JR      Z,PL3
        CALL    SP2
        CALL    SPC
        DEC     C
        JR      PL2
PL3:    CALL    SPC
        LD      HL,DBUF
        CALL    PSTR
        CALL    CRLF
        LD      HL,(DNEXT)
        RET

; G[dir][,p1[,p2]]: ejecutar
C_G:    CALL    NUMS
        LD      (GTF),A
        BIT     0,A
        JR      Z,G1
        LD      HL,(ARGV)
        LD      (R_PC),HL
G1:     LD      HL,(ARGV+2)
        LD      (GT1),HL
        LD      HL,(ARGV+4)
        LD      (GT2),HL
        LD      DE,(R_PC)
        CALL    INPBP
        JR      NC,G2
        LD      A,M_GOS         ; hay un punto en PC: primero un paso
        LD      (MODE),A
        XOR     A
        LD      (SOVER),A
        CALL    STEP1
        JP      RESUME
G2:     XOR     A
        LD      (MODE),A
        CALL    INSTG
        JP      RESUME

; INSTG: los temporales de G y los permanentes
INSTG:  LD      A,(GTF)
        BIT     1,A
        JR      Z,IG1
        LD      DE,(GT1)
        CALL    SETBP
IG1:    LD      A,(GTF)
        BIT     2,A
        JR      Z,INSPB
        LD      DE,(GT2)
        CALL    SETBP
; INSPB: los permanentes, menos el de PC
INSPB:  LD      A,(NPB)
        OR      A
        RET     Z
        LD      B,A
        LD      HL,PBP
IP3:    LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        PUSH    HL
        PUSH    BC
        LD      HL,(R_PC)
        OR      A
        SBC     HL,DE
        CALL    NZ,SETBP
        POP     BC
        POP     HL
        DJNZ    IP3
        RET

; T[n] / N[n]: n pasos (N pasa por encima de CALL y RST)
C_T:    XOR     A
CTN:    LD      (SOVER),A
        CALL    NUMS
        LD      HL,1
        BIT     0,A
        JR      Z,T1
        LD      HL,(ARGV)
T1:     LD      A,H
        OR      L
        JP      Z,CMDL
        LD      (TCNT),HL
        LD      A,M_STEP
        LD      (MODE),A
        CALL    STEP1
        JP      RESUME
C_N:    LD      A,1
        JR      CTN

; STEP1: pone los puntos para ejecutar la instruccion en PC
STEP1:  LD      HL,(R_PC)
        CALL    DIS
        LD      HL,(DNEXT)
        LD      (SFALL),HL
        LD      A,1
        LD      (FALLF),A
        XOR     A
        LD      (TGTF),A
        LD      HL,(R_PC)
        LD      A,(HL)
        INC     HL
        CP      0DDh
        JR      Z,SIX
        CP      0FDh
        JR      Z,SIY
        CP      0EDh
        JR      Z,SED
        CP      0C3h
        JR      Z,SJP
        CP      0CDh
        JR      Z,SCALL
        CP      0C9h
        JR      Z,SRET
        CP      0E9h
        JR      Z,SJPHL
        CP      18h
        JR      Z,SJR
        CP      10h
        JR      Z,SJRC
        LD      B,A
        AND     0E7h
        CP      20h
        JR      Z,SJRC
        LD      A,B
        AND     0C7h
        CP      0C2h
        JR      Z,SJPC
        CP      0C4h
        JR      Z,SCALLC
        CP      0C0h
        JR      Z,SRETC
        JP      SPUT
SJP:    XOR     A
        LD      (FALLF),A
SJPC:   CALL    GW
        JR      STGTJ
SCALL:  XOR     A
        LD      (FALLF),A
SCALLC: CALL    GW
        JR      STGTC
SRET:   XOR     A
        LD      (FALLF),A
SRETC:  LD      HL,(R_SP)
        CALL    GW
        JR      STG
SJPHL:  XOR     A
        LD      (FALLF),A
        LD      DE,(R_HL)
        JR      STGTJ
SJR:    XOR     A
        LD      (FALLF),A
SJRC:   LD      A,(HL)
        INC     HL
        LD      E,A
        ADD     A,A
        SBC     A,A
        LD      D,A
        ADD     HL,DE
        EX      DE,HL
        JR      STGTJ
SIX:    LD      DE,(R_IX)
        JR      SIXY
SIY:    LD      DE,(R_IY)
SIXY:   LD      A,(HL)
        CP      0E9h
        JR      NZ,SPUT
        XOR     A
        LD      (FALLF),A
        JR      STGTJ
SED:    LD      A,(HL)
        AND     0C7h
        CP      45h             ; RETN, RETI
        JR      NZ,SPUT
        XOR     A
        LD      (FALLF),A
        JR      SRETC
; CALL: con N o hacia el sistema, solo la siguiente instruccion
STGTC:  LD      A,(SOVER)
        OR      A
        JR      NZ,SOVR
        CALL    ISSYS
        JR      NC,STG
SOVR:   LD      A,1
        LD      (FALLF),A
        JR      SPUT
; salto hacia el sistema (JP 5): el punto va en la direccion de retorno
STGTJ:  CALL    ISSYS
        JR      NC,STG
        LD      HL,(R_SP)
        CALL    GW
STG:    LD      (TGT),DE
        LD      A,1
        LD      (TGTF),A
SPUT:   LD      A,(FALLF)
        OR      A
        JR      Z,SPT1
        LD      DE,(SFALL)
        CALL    SETBP
SPT1:   LD      A,(TGTF)
        OR      A
        JR      Z,SPT2
        LD      DE,(TGT)        ; destino dentro de la instruccion (DJNZ $):
        LD      HL,(R_PC)       ; sin punto ahi; el paso termina al salir
        EX      DE,HL
        OR      A
        SBC     HL,DE
        JR      C,SPT3
        LD      HL,(SFALL)
        LD      DE,(TGT)
        OR      A
        SBC     HL,DE
        JR      C,SPT3
        JR      NZ,SPT2
SPT3:   LD      DE,(TGT)
        CALL    SETBP
SPT2:   JP      INSPB

; GW: DE = palabra en (HL)
GW:     LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        RET

; ISTMP: carry si PC es uno de los puntos del paso
ISTMP:  LD      DE,(R_PC)
        LD      A,(FALLF)
        OR      A
        JR      Z,IT1
        LD      HL,(SFALL)
        OR      A
        SBC     HL,DE
        SCF
        RET     Z
IT1:    LD      A,(TGTF)
        OR      A
        RET     Z
        LD      HL,(TGT)
        OR      A
        SBC     HL,DE
        SCF
        RET     Z
        OR      A
        RET

; ISSYS: carry si DE no es memoria del programa (pagina 0, ZDB, BDOS)
ISSYS:  LD      A,D
        OR      A
        SCF
        RET     Z
        PUSH    HL
        LD      HL,STUB-1
        OR      A
        SBC     HL,DE
        POP     HL
        RET

; SETBP: RST 38h en DE (si es del programa y no esta ya puesto)
SETBP:  CALL    ISSYS
        RET     C
        LD      A,(NBP)
        OR      A
        JR      Z,SB2
        LD      B,A
        LD      HL,BPT
SB1:    LD      A,(HL)
        CP      E
        JR      NZ,SB1N
        INC     HL
        LD      A,(HL)
        DEC     HL
        CP      D
        RET     Z
SB1N:   INC     HL
        INC     HL
        INC     HL
        DJNZ    SB1
SB2:    LD      A,(NBP)
        CP      NBPT
        RET     NC
        LD      L,A
        ADD     A,A
        ADD     A,L
        LD      L,A
        LD      H,0
        LD      BC,BPT
        ADD     HL,BC
        LD      (HL),E
        INC     HL
        LD      (HL),D
        INC     HL
        LD      A,(DE)
        LD      (HL),A
        LD      A,0FFh
        LD      (DE),A
        LD      HL,NBP
        INC     (HL)
        RET

; REMBP: devuelve los bytes de todos los puntos puestos
REMBP:  LD      A,(NBP)
        OR      A
        RET     Z
        LD      B,A
        DEC     A
        LD      L,A
        ADD     A,A
        ADD     A,L
        LD      L,A
        LD      H,0
        LD      DE,BPT
        ADD     HL,DE
RB1:    PUSH    HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        LD      A,(HL)
        LD      (DE),A
        POP     HL
        DEC     HL
        DEC     HL
        DEC     HL
        DJNZ    RB1
        XOR     A
        LD      (NBP),A
        RET

; RESUME: vuelve al programa con sus registros
RESUME: DI
        LD      A,1
        LD      (RUNNING),A
        LD      HL,(R_SP)
        LD      DE,(R_PC)
        DEC     HL
        LD      (HL),D
        DEC     HL
        LD      (HL),E
        LD      (TMPSP),HL
        LD      SP,R_IY
        POP     IY
        POP     IX
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        EXX
        EX      AF,AF'
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        LD      SP,(TMPSP)
        EI
        RET

; BRK: RST 38h, un punto de parada
BRK:    DI
        LD      (TMPSP),SP
        LD      SP,R_SP
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        EXX
        EX      AF,AF'
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        PUSH    IX
        PUSH    IY
        LD      SP,STACK
        LD      HL,(TMPSP)
        CALL    GW
        LD      (R_SP),HL
        DEC     DE
        LD      (R_PC),DE
        EI
        XOR     A
        LD      (RUNNING),A
        CALL    REMBP
        LD      A,(MODE)
        CP      M_GO
        JR      Z,BKSHOW
        CALL    ISTMP
        JR      NC,BKSHOW       ; otro punto (permanente o un FF del programa)
        LD      A,(MODE)
        CP      M_GOS
        JR      NZ,BKSTEP
        CALL    INSTG
        XOR     A
        LD      (MODE),A
        JP      RESUME
BKSTEP: XOR     A
        CALL    SHOWR
        LD      HL,(TCNT)
        DEC     HL
        LD      (TCNT),HL
        LD      A,H
        OR      L
        JP      Z,CMDL
        CALL    KEYHIT
        JP      NZ,CMDL
        CALL    STEP1
        JP      RESUME
BKSHOW: LD      HL,M_BRK
        CALL    PSTR
        LD      HL,(R_PC)
        CALL    PH4
        CALL    CRLF
        XOR     A
        CALL    SHOWR
        JP      CMDL

; SHOWR: registros (A <> 0: tambien los alternos) y la instruccion en PC
SHOWR:  PUSH    AF
        LD      HL,REGT1
        CALL    PREGS
        POP     AF
        OR      A
        LD      HL,REGT2
        CALL    NZ,PREGS
        LD      HL,(R_PC)
        JP      PLINE
; PREGS: tabla de (texto, direccion, tipo); tipo 1 = byte, 2 = palabra, 3 = banderas
PREGS:  LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        LD      A,D
        OR      E
        JP      Z,CRLF
        PUSH    HL
        EX      DE,HL
        CALL    PSTR
        POP     HL
        CALL    GW
        LD      A,(HL)
        INC     HL
        PUSH    HL
        EX      DE,HL
        CP      2
        JR      Z,PRW
        LD      C,A
        LD      A,(HL)
        DEC     C
        JR      Z,PRB
        CALL    PFL
        JR      PRN
PRB:    CALL    PH2
        JR      PRN
PRW:    LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        CALL    PH4
PRN:    POP     HL
        JR      PREGS
REGT1:  DW      S_A,R_AF+1
        DB      1
        DW      S_F,R_AF
        DB      3
        DW      S_BC,R_BC
        DB      2
        DW      S_DE,R_DE
        DB      2
        DW      S_HL,R_HL
        DB      2
        DW      S_IX,R_IX
        DB      2
        DW      S_IY,R_IY
        DB      2
        DW      S_SP,R_SP
        DB      2
        DW      0
REGT2:  DW      S_A2,R_AF2+1
        DB      1
        DW      S_F2,R_AF2
        DB      3
        DW      S_BC2,R_BC2
        DB      2
        DW      S_DE2,R_DE2
        DB      2
        DW      S_HL2,R_HL2
        DB      2
        DW      0
S_A:    DB      'A=',0
S_F:    DB      ' F=',0
S_BC:   DB      ' BC=',0
S_DE:   DB      ' DE=',0
S_HL:   DB      ' HL=',0
S_IX:   DB      ' IX=',0
S_IY:   DB      ' IY=',0
S_SP:   DB      ' SP=',0
S_A2:   DB      'A',27h,'=',0
S_F2:   DB      ' F',27h,'=',0
S_BC2:  DB      ' BC',27h,'=',0
S_DE2:  DB      ' DE',27h,'=',0
S_HL2:  DB      ' HL',27h,'=',0

; PFL: banderas de A como SZHPNC ('-' si estan apagadas)
PFL:    LD      C,A
        LD      HL,FLT
        LD      B,6
PF1:    LD      A,(HL)
        INC     HL
        AND     C
        LD      A,(HL)
        INC     HL
        JR      NZ,PF2
        LD      A,'-'
PF2:    CALL    COUT
        DJNZ    PF1
        RET
FLT:    DB      80h,'S',40h,'Z',10h,'H',04h,'P',02h,'N',01h,'C'

; X / Xr valor: registros
C_X:    LD      HL,(CPTR)
        CALL    SKSP
        OR      A
        JR      NZ,X1
        LD      A,1
        CALL    SHOWR
        JP      CMDL
X1:     LD      DE,XNM
        LD      A,' '
        LD      (DE),A
        INC     DE
        LD      (DE),A
        INC     DE
        LD      (DE),A
        LD      DE,XNM
        LD      B,3
X2:     LD      A,(HL)
        CP      27h
        JR      Z,X3
        CP      'A'
        JR      C,X4
        CP      'Z'+1
        JR      NC,X4
X3:     LD      C,A
        LD      A,B
        OR      A
        JP      Z,ERR
        LD      A,C
        LD      (DE),A
        INC     DE
        DEC     B
        INC     HL
        JR      X2
X4:     LD      IX,XRT
X5:     LD      A,(IX+0)
        OR      A
        JP      Z,ERR
        LD      DE,XNM
        LD      A,(DE)
        CP      (IX+0)
        JR      NZ,X6
        INC     DE
        LD      A,(DE)
        CP      (IX+1)
        JR      NZ,X6
        INC     DE
        LD      A,(DE)
        CP      (IX+2)
        JR      Z,X7
X6:     LD      DE,6
        ADD     IX,DE
        JR      X5
X7:     CALL    SKSP
        CP      '='
        JR      NZ,X8
        INC     HL
        CALL    SKSP
X8:     CALL    GHEX
        JP      C,ERR
        LD      L,(IX+3)
        LD      H,(IX+4)
        LD      (HL),E
        LD      A,(IX+5)
        CP      2
        JR      NZ,X9
        INC     HL
        LD      (HL),D
X9:     XOR     A
        CALL    SHOWR
        JP      CMDL
XRT:    DB      'A  '
        DW      R_AF+1
        DB      1
        DB      'F  '
        DW      R_AF
        DB      1
        DB      'B  '
        DW      R_BC+1
        DB      1
        DB      'C  '
        DW      R_BC
        DB      1
        DB      'D  '
        DW      R_DE+1
        DB      1
        DB      'E  '
        DW      R_DE
        DB      1
        DB      'H  '
        DW      R_HL+1
        DB      1
        DB      'L  '
        DW      R_HL
        DB      1
        DB      'AF '
        DW      R_AF
        DB      2
        DB      'BC '
        DW      R_BC
        DB      2
        DB      'DE '
        DW      R_DE
        DB      2
        DB      'HL '
        DW      R_HL
        DB      2
        DB      'IX '
        DW      R_IX
        DB      2
        DB      'IY '
        DW      R_IY
        DB      2
        DB      'SP '
        DW      R_SP
        DB      2
        DB      'PC '
        DW      R_PC
        DB      2
        DB      'AF',27h
        DW      R_AF2
        DB      2
        DB      'BC',27h
        DW      R_BC2
        DB      2
        DB      'DE',27h
        DW      R_DE2
        DB      2
        DB      'HL',27h
        DW      R_HL2
        DB      2
        DB      0

; B / B dir[,dir...]: puntos de parada permanentes
C_B:    CALL    NUMS
        OR      A
        JR      NZ,B1
        LD      A,(NPB)
        OR      A
        LD      HL,M_NOBP
        JP      Z,PERR
        LD      B,A
        LD      HL,M_BPS
        CALL    PSTR
        LD      HL,PBP
B0:     CALL    SPC
        CALL    GW
        PUSH    HL
        EX      DE,HL
        CALL    PH4
        POP     HL
        DJNZ    B0
        CALL    CRLF
        JP      CMDL
B1:     LD      HL,ARGV
        LD      C,A
        LD      B,3
B2:     CALL    GW
        SRL     C
        PUSH    BC
        PUSH    HL
        CALL    C,ADDPB
        POP     HL
        POP     BC
        DJNZ    B2
        JP      CMDL
ADDPB:  CALL    ISSYS
        JP      C,ERR
        CALL    INPBP
        RET     C
        LD      A,(NPB)
        CP      NPERM
        LD      HL,M_FULL
        JP      NC,PERR
        ADD     A,A
        LD      L,A
        LD      H,0
        LD      BC,PBP
        ADD     HL,BC
        LD      (HL),E
        INC     HL
        LD      (HL),D
        LD      HL,NPB
        INC     (HL)
        RET

; INPBP: carry si DE es un punto permanente (HL en su byte alto)
INPBP:  LD      A,(NPB)
        OR      A
        RET     Z
        LD      B,A
        LD      HL,PBP
IP1:    LD      A,(HL)
        INC     HL
        CP      E
        JR      NZ,IP2
        LD      A,(HL)
        CP      D
        JR      NZ,IP2
        SCF
        RET
IP2:    INC     HL
        DJNZ    IP1
        OR      A
        RET

; K / K dir: quitar puntos permanentes
C_K:    CALL    NUMS
        OR      A
        JR      NZ,K1
        LD      (NPB),A
        JP      CMDL
K1:     LD      DE,(ARGV)
        CALL    INPBP
        JP      NC,ERR
        INC     HL              ; HL = el siguiente
        PUSH    HL
        LD      A,(NPB)
        ADD     A,A
        LD      E,A
        LD      D,0
        LD      HL,PBP
        ADD     HL,DE
        POP     DE
        OR      A
        SBC     HL,DE           ; bytes que quedan despues
        LD      B,H
        LD      C,L
        LD      H,D
        LD      L,E
        DEC     DE
        DEC     DE
        LD      A,B
        OR      C
        JR      Z,K2
        LDIR
K2:     LD      HL,NPB
        DEC     (HL)
        JP      CMDL

; S dir: cambiar memoria (hex, 'texto', vacio = siguiente, - = anterior, . = fin)
C_S:    CALL    NUMS
        BIT     0,A
        JP      Z,ERR
        LD      HL,(ARGV)
        LD      (SADR),HL
S1:     LD      HL,(SADR)
        CALL    PH4
        CALL    SP2
        LD      A,(HL)
        CALL    PH2
        CALL    SPC
        CALL    READL
        LD      HL,(CPTR)
        CALL    SKSP
        OR      A
        JR      NZ,S2
        LD      HL,(SADR)
        INC     HL
        LD      (SADR),HL
        JR      S1
S2:     CP      '.'
        JP      Z,CMDL
        CP      '-'
        JR      NZ,SI
        LD      HL,(SADR)
        DEC     HL
        LD      (SADR),HL
        JR      S1
SI:     CALL    SKSP
        OR      A
        JR      Z,S1
        CP      27h
        JR      Z,SQ
        CALL    GHEX
        JR      C,SERR
        LD      A,E
        CALL    SPUTB
        JR      SI
SQ:     INC     HL
SQ1:    LD      A,(HL)
        OR      A
        JR      Z,S1
        INC     HL
        CP      27h
        JR      Z,SI
        CALL    SPUTB
        JR      SQ1
SPUTB:  PUSH    HL
        LD      HL,(SADR)
        LD      (HL),A
        INC     HL
        LD      (SADR),HL
        POP     HL
        RET
SERR:   LD      HL,M_ERR
        CALL    PSTR
        CALL    CRLF
        JR      S1

; F ini,fin,byte
C_F:    CALL    NUMS
        CP      7
        JP      NZ,ERR
        LD      HL,(ARGV)
        LD      DE,(ARGV+2)
        CALL    CHKORD
        LD      A,(ARGV+4)
F1:     LD      (HL),A
        PUSH    HL
        OR      A
        SBC     HL,DE
        POP     HL
        INC     HL
        JR      C,F1
        JP      CMDL
; CHKORD: error si DE < HL
CHKORD: PUSH    HL
        PUSH    DE
        EX      DE,HL
        OR      A
        SBC     HL,DE
        POP     DE
        POP     HL
        JP      C,ERR
        RET

; M ini,fin,destino
C_M:    CALL    NUMS
        CP      7
        JP      NZ,ERR
        LD      HL,(ARGV)
        LD      DE,(ARGV+2)
        CALL    CHKORD
        EX      DE,HL
        OR      A
        SBC     HL,DE
        INC     HL
        LD      B,H
        LD      C,L             ; BC = longitud
        LD      HL,(ARGV)
        LD      DE,(ARGV+4)
        PUSH    HL
        OR      A
        SBC     HL,DE
        POP     HL
        JR      C,M1            ; destino arriba: de atras hacia adelante
        LDIR
        JP      CMDL
M1:     ADD     HL,BC
        DEC     HL
        EX      DE,HL
        ADD     HL,BC
        DEC     HL
        EX      DE,HL
        LDDR
        JP      CMDL

; H a,b: suma y resta; H a: a en decimal
C_H:    CALL    NUMS
        BIT     0,A
        JP      Z,ERR
        BIT     1,A
        LD      HL,(ARGV)
        JR      NZ,H1
        CALL    PH4
        LD      A,' '
        CALL    COUT
        LD      A,'='
        CALL    COUT
        CALL    SPC
        LD      HL,(ARGV)
        CALL    PDEC
        CALL    CRLF
        JP      CMDL
H1:     LD      DE,(ARGV+2)
        ADD     HL,DE
        CALL    PH4
        CALL    SP2
        LD      HL,(ARGV)
        OR      A
        SBC     HL,DE
        CALL    PH4
        CALL    CRLF
        JP      CMDL

; I texto: linea de ordenes del programa (80h, FCB en 5Ch y 6Ch)
C_I:    LD      HL,(CPTR)
        CALL    SKSP
        CALL    SETTAIL
        JP      CMDL
SETTAIL: PUSH   HL
        LD      HL,5Ch
        CALL    CLRF
        LD      HL,6Ch
        CALL    CLRF
        XOR     A
        LD      (7Ch),A
        LD      (7Dh),A
        LD      (7Eh),A
        LD      (7Fh),A
        POP     HL
        PUSH    HL
        LD      DE,5Ch
        CALL    PFN
        CALL    SKSP
        OR      A
        JR      Z,ST0
        LD      DE,6Ch
        CALL    PFN
ST0:    POP     HL
        LD      DE,81h
        LD      B,0
        LD      A,(HL)
        OR      A
        JR      Z,ST3
        LD      A,' '
        LD      (DE),A
        INC     DE
        INC     B
ST2:    LD      A,(HL)
        LD      (DE),A
        OR      A
        JR      Z,ST3
        INC     HL
        INC     DE
        INC     B
        LD      A,B
        CP      126
        JR      C,ST2
        XOR     A
        LD      (DE),A
ST3:    LD      A,B
        LD      (80h),A
        RET

; CLRF: los 16 primeros bytes de un FCB (unidad 0, nombre en blanco)
CLRF:   LD      (HL),0
        INC     HL
        LD      B,11
CF1:    LD      (HL),' '
        INC     HL
        DJNZ    CF1
        LD      B,4
CF2:    LD      (HL),0
        INC     HL
        DJNZ    CF2
        RET

; PFN: nombre de archivo en HL al FCB en DE (HL queda despues del nombre)
PFN:    CALL    SKSP
        PUSH    DE
        PUSH    HL
        EX      DE,HL
        CALL    CLRF
        POP     HL
        POP     DE
        PUSH    DE
        INC     HL
        LD      A,(HL)
        DEC     HL
        CP      ':'
        JR      NZ,PN1
        LD      A,(HL)
        SUB     '@'
        LD      (DE),A
        INC     HL
        INC     HL
PN1:    INC     DE
        LD      B,8
        CALL    PFLD
        POP     DE
        LD      A,(HL)
        CP      '.'
        RET     NZ
        INC     HL
        PUSH    DE
        PUSH    HL
        LD      HL,9
        ADD     HL,DE
        EX      DE,HL
        POP     HL
        LD      B,3
        CALL    PFLD
        POP     DE
        RET
PFLD:   LD      A,(HL)
        CALL    ISDEL
        RET     Z
        INC     HL
        CP      '*'
        JR      Z,PFST
        LD      C,A
        LD      A,B
        OR      A
        JR      Z,PFLD
        LD      A,C
        LD      (DE),A
        INC     DE
        DEC     B
        JR      PFLD
PFST:   LD      A,B
        OR      A
        JR      Z,PFLD
        LD      A,'?'
        LD      (DE),A
        INC     DE
        DEC     B
        JR      PFST
ISDEL:  OR      A
        RET     Z
        CP      ' '
        RET     Z
        CP      ','
        RET     Z
        CP      '.'
        RET

; R[desplazamiento]: lee el archivo de I (5Ch) en 100h
C_R:    CALL    NUMS
        LD      HL,0
        BIT     0,A
        JR      Z,R1
        LD      HL,(ARGV)
R1:     LD      (ROFF),HL
        LD      A,(5Dh)         ; sin nombre en I: el ultimo archivo leido
        CP      ' '
        JR      Z,LOADF
        LD      HL,5Ch
        LD      DE,LFCB
        LD      BC,12
        LDIR
LOADF:  LD      A,(LFCB+1)
        CP      ' '
        JP      Z,ERR
        LD      A,(LFCB+9)
        CP      ' '
        JR      NZ,LF1
        LD      HL,S_COM
        LD      DE,LFCB+9
        LD      BC,3
        LDIR
LF1:    LD      HL,LFCB+12
        CALL    ZF24
        LD      DE,LFCB
        LD      C,15
        CALL    SYSBD
        INC     A
        LD      HL,M_NOF
        JP      Z,PERR
        LD      HL,(ROFF)
        LD      DE,100h
        ADD     HL,DE
        LD      (LBEG),HL
LF2:    PUSH    HL
        LD      DE,128
        ADD     HL,DE
        EX      DE,HL
        LD      HL,STUB-64
        OR      A
        SBC     HL,DE
        POP     HL
        JR      C,LFBIG
        PUSH    HL
        EX      DE,HL
        LD      C,26
        CALL    SYSBD
        LD      DE,LFCB
        LD      C,20
        CALL    SYSBD
        POP     HL
        OR      A
        JR      NZ,LF3
        LD      DE,128
        ADD     HL,DE
        JR      LF2
LFBIG:  CALL    DMA80
        LD      HL,M_BIG
        JP      PERR
LF3:    CALL    DMA80
        DEC     HL
        LD      (LEND),HL
        CALL    INITPC
        LD      HL,M_LOAD
        CALL    PSTR
        LD      HL,(LBEG)
        CALL    PH4
        LD      A,'-'
        CALL    COUT
        LD      HL,(LEND)
        CALL    PH4
        CALL    CRLF
        JP      CMDL
DMA80:  PUSH    HL
        LD      DE,80h
        LD      C,26
        CALL    SYSBD
        POP     HL
        RET
ZF24:   LD      B,24
ZF1:    LD      (HL),0
        INC     HL
        DJNZ    ZF1
        RET

; W archivo[,ini,fin]: graba memoria (por omision 100h hasta el fin de lo leido)
C_W:    LD      HL,(CPTR)
        LD      DE,WFCB
        CALL    PFN
        LD      (CPTR),HL
        LD      A,(WFCB+1)
        CP      ' '
        JP      Z,ERR
        CALL    NUMS
        LD      HL,100h
        BIT     0,A
        JR      Z,W1
        LD      HL,(ARGV)
W1:     LD      (WS),HL
        LD      HL,(LEND)
        BIT     1,A
        JR      Z,W2
        LD      HL,(ARGV+2)
W2:     LD      (WE),HL
        EX      DE,HL
        LD      HL,(WS)
        CALL    CHKORD
        LD      HL,WFCB+12
        CALL    ZF24
        LD      DE,WFCB
        LD      C,19
        CALL    SYSBD
        LD      DE,WFCB
        LD      C,22
        CALL    SYSBD
        INC     A
        LD      HL,M_DIRF
        JP      Z,PERR
        LD      HL,0
        LD      (WCNT),HL
W3:     LD      DE,(WS)
        LD      C,26
        CALL    SYSBD
        LD      DE,WFCB
        LD      C,21
        CALL    SYSBD
        OR      A
        JR      NZ,WFULL
        LD      HL,(WCNT)
        INC     HL
        LD      (WCNT),HL
        LD      HL,(WS)
        LD      DE,128
        ADD     HL,DE
        JR      C,W4
        LD      (WS),HL
        EX      DE,HL
        LD      HL,(WE)
        OR      A
        SBC     HL,DE
        JR      NC,W3
W4:     CALL    WCLOSE
        LD      HL,M_WR
        CALL    PSTR
        LD      HL,(WCNT)
        CALL    PDEC
        LD      HL,M_WR2
        JP      PERR
WFULL:  CALL    WCLOSE
        LD      HL,M_DSKF
        JP      PERR
WCLOSE: CALL    DMA80
        LD      DE,WFCB
        LD      C,16
        JP      SYSBD

; ---------------------------------------------------------------- entrada
; READL: lee una linea (BDOS 10) en mayusculas salvo entre comillas; CP al inicio
READL:  LD      DE,IBUF
        LD      A,80
        LD      (DE),A
        LD      C,10
        CALL    SYSBD
        CALL    CRLF
        LD      HL,IBUF+1
        LD      B,(HL)
        INC     HL
        LD      (CPTR),HL
        LD      C,0
RL1:    LD      A,B
        OR      A
        JR      Z,RL3
        LD      A,(HL)
        CP      27h
        JR      NZ,RL2
        LD      A,C
        XOR     1
        LD      C,A
        JR      RL2B
RL2:    BIT     0,C
        JR      NZ,RL2B
        CP      'a'
        JR      C,RL2B
        CP      'z'+1
        JR      NC,RL2B
        SUB     20h
        LD      (HL),A
RL2B:   INC     HL
        DEC     B
        JR      RL1
RL3:    LD      (HL),0
        RET

; SKSP: salta espacios; A = caracter siguiente
SKSP:   LD      A,(HL)
        CP      ' '
        JR      Z,SK1
        CP      9
        RET     NZ
SK1:    INC     HL
        JR      SKSP

; GHEX: numero hexadecimal en HL -> DE; carry si no hay digitos
GHEX:   LD      DE,0
        LD      B,0
GH1:    LD      A,(HL)
        CALL    ISHEX
        JR      C,GH2
        EX      DE,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        OR      L
        LD      L,A
        EX      DE,HL
        INC     HL
        INC     B
        JR      GH1
GH2:    LD      A,B
        OR      A
        SCF
        RET     Z
        OR      A
        RET
ISHEX:  SUB     '0'
        RET     C
        CP      10
        CCF
        RET     NC
        SUB     7
        CP      10
        RET     C
        CP      16
        CCF
        RET

; NUMS: hasta 3 numeros separados por coma o espacio en ARGV;
; A = ARGP, bit n = el numero n esta
NUMS:   XOR     A
        LD      (ARGP),A
        LD      HL,(CPTR)
        LD      C,1
        LD      IX,ARGV
NM1:    CALL    SKSP
        OR      A
        JR      Z,NMX
        CP      ','
        JR      Z,NMC
        CALL    GHEX
        JP      C,ERR
        LD      (IX+0),E
        LD      (IX+1),D
        LD      A,(ARGP)
        OR      C
        LD      (ARGP),A
        CALL    SKSP
        OR      A
        JR      Z,NMX
        CP      ','
        JR      NZ,NMN
NMC:    INC     HL
NMN:    INC     IX
        INC     IX
        SLA     C
        LD      A,C
        CP      8
        JP      NC,ERR
        JR      NM1
NMX:    LD      (CPTR),HL
        LD      A,(ARGP)
        RET

; KEYHIT: NZ si se oprimio una tecla (y la consume)
KEYHIT: LD      C,11
        CALL    SYSBD
        OR      A
        RET     Z
        LD      E,0FFh
        LD      C,6
        CALL    SYSBD
        LD      A,1
        OR      A
        RET

; ---------------------------------------------------------------- salida
COUT:   PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      E,A
        LD      C,2
        CALL    SYSBD
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        RET
PSTR:   LD      A,(HL)
        OR      A
        RET     Z
        CALL    COUT
        INC     HL
        JR      PSTR
CRLF:   LD      A,13
        CALL    COUT
        LD      A,10
        JP      COUT
SP2:    CALL    SPC
SPC:    LD      A,' '
        JP      COUT
PH4:    LD      A,H
        CALL    PH2
        LD      A,L
PH2:    PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    PHN
        POP     AF
PHN:    CALL    HEXC
        JP      COUT
; PDEC: HL en decimal
PDEC:   XOR     A
        LD      (LZ),A
        LD      BC,-10000
        CALL    PD1
        LD      BC,-1000
        CALL    PD1
        LD      BC,-100
        CALL    PD1
        LD      BC,-10
        CALL    PD1
        LD      A,L
        ADD     A,'0'
        JP      COUT
PD1:    LD      A,'0'-1
PD2:    INC     A
        ADD     HL,BC
        JR      C,PD2
        SBC     HL,BC
        CP      '0'
        JR      NZ,PD3
        LD      A,(LZ)
        OR      A
        RET     Z
        LD      A,'0'
PD3:    LD      (LZ),A
        JP      COUT

        INCLUDE zdbdis.asm

; ---------------------------------------------------------------- textos
M_BAN:  DB      'ZDB 1.0  Z80 debugger, top of memory ',0
M_BAN2: DB      13,10,'Type ? for help.',13,10,0
M_ERR:  DB      '?',0
M_END:  DB      13,10,'Program ended',0
M_BRK:  DB      'Break at ',0
M_NOF:  DB      'File not found',0
M_BIG:  DB      'File too big',0
M_DIRF: DB      'Directory full',0
M_DSKF: DB      'Disk full',0
M_FULL: DB      'Too many breakpoints',0
M_NOBP: DB      'No breakpoints',0
M_BPS:  DB      'Breakpoints:',0
M_LOAD: DB      'Loaded ',0
M_WR:   DB      'Wrote ',0
M_WR2:  DB      ' records',0
S_COM:  DB      'COM'
M_HELP: DB      'ZDB commands (numbers in hex):',13,10
        DB      ' D[s][,e]     dump memory           L[s][,e]     disassemble',13,10
        DB      ' G[a][,b,b]   go [to a] [stop at b] T[n]         trace n steps',13,10
        DB      ' N[n]         trace, over calls     B[a,a,a]     list/set breakpoints',13,10
        DB      ' K[a]         clear breakpoint(s)   X[r v]       show/set registers',13,10
        DB      ' S a          set memory            F s,e,v      fill',13,10
        DB      ' M s,e,d      move                  H a[,b]      hex sum/difference',13,10
        DB      ' I text       set command line      R[o]         read file from I',13,10
        DB      ' W f[,s,e]    write file            Q            quit',13,10,0

; ---------------------------------------------------------------- datos
RUNNING: DB     0
MODE:   DB      0
SOVER:  DB      0
FALLF:  DB      0
TGTF:   DB      0
GTF:    DB      0
NBP:    DB      0
NPB:    DB      0
ARGP:   DB      0
LZ:     DB      0
SFALL:  DW      0
TGT:    DW      0
GT1:    DW      0
GT2:    DW      0
TCNT:   DW      0
TMPSP:  DW      0
OLD0:   DW      0
OLD38:  DS      3
CPTR:   DW      0
ARGV:   DS      6
DADR:   DW      100h
DEND:   DW      0
LADR:   DW      100h
SADR:   DW      0
ROFF:   DW      0
LBEG:   DW      100h
LEND:   DW      100h
WS:     DW      0
WE:     DW      0
WCNT:   DW      0
XNM:    DS      3
PBP:    DS      2*NPERM
BPT:    DS      3*NBPT
LFCB:   DS      36
WFCB:   DS      36
IBUF:   DS      84
        DS      48              ; margen debajo de los registros
R_IY:   DW      0
R_IX:   DW      0
R_HL2:  DW      0
R_DE2:  DW      0
R_BC2:  DW      0
R_AF2:  DW      0
R_HL:   DW      0
R_DE:   DW      0
R_BC:   DW      0
R_AF:   DW      0
R_SP:   DW      0
R_PC:   DW      0
        DS      128
STACK:
ZEND:
