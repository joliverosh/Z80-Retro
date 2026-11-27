; zfile.inc - la linea de ordenes y los archivos (va despues de zcon.inc)
;
; ARGS / NEXTARG    las palabras de la linea de ordenes
; MKFCB             un nombre (con unidad, * y ?) a un FCB
; GLOB              los archivos que casan con un nombre
; NM2FCB / FNAME    nombre de GLOB -> FCB, FCB -> "A:NOMBRE.EXT"
; FOPEN FCLOSE FREADN FMAKE FWRITE RREAD
; RDOPEN / RGETC    lectura de a un byte con un bufer de 1 KB (un solo lector)

; ARGS: copia la linea (80h) a LINEA, terminada en 0
ARGS:   LD      HL,80h
        LD      C,(HL)
        LD      B,0
        INC     HL
        LD      DE,LINEA
        LD      (APTR),DE
        LD      A,C
        OR      A
        JR      Z,ARGS1
        LDIR
ARGS1:  XOR     A
        LD      (DE),A
        RET

; NEXTARG: HL = la siguiente palabra (terminada en 0); acarreo si no hay
NEXTARG:LD      HL,(APTR)
NA1:    LD      A,(HL)
        CP      ' '
        JR      NZ,NA2
        INC     HL
        JR      NA1
NA2:    OR      A
        JR      NZ,NA3
        LD      (APTR),HL
        SCF
        RET
NA3:    PUSH    HL
NA4:    INC     HL
        LD      A,(HL)
        OR      A
        JR      Z,NA5
        CP      ' '
        JR      NZ,NA4
        LD      (HL),0
        INC     HL
NA5:    LD      (APTR),HL
        POP     HL
        OR      A
        RET

; RESTO: Z si ya no quedan palabras
RESTO:  LD      HL,(APTR)
RS1:    LD      A,(HL)
        CP      ' '
        JR      NZ,RS2
        INC     HL
        JR      RS1
RS2:    OR      A
        RET

UPPER:  CP      'a'
        RET     C
        CP      'z'+1
        RET     NC
        SUB     20h
        RET

; MKFCB: HL nombre, DE FCB (36 bytes). Acarreo si el nombre no sirve.
MKFCB:  PUSH    DE
        LD      B,36
        XOR     A
MK0:    LD      (DE),A
        INC     DE
        DJNZ    MK0
        POP     DE
        PUSH    DE
        INC     DE
        LD      B,11
        LD      A,' '
MK1:    LD      (DE),A
        INC     DE
        DJNZ    MK1
        POP     DE
MK2:    LD      A,(HL)
        CP      ' '
        JR      NZ,MK3
        INC     HL
        JR      MK2
MK3:    OR      A
        SCF
        RET     Z
        INC     HL
        LD      A,(HL)
        DEC     HL
        CP      ':'
        JR      NZ,MK4
        LD      A,(HL)
        CALL    UPPER
        SUB     'A'-1
        JR      C,MKMAL
        JR      Z,MKMAL
        CP      17
        CCF
        RET     C
        LD      (DE),A
        INC     HL
        INC     HL
MK4:    PUSH    DE
        INC     DE
        LD      B,8
MK5:    LD      A,(HL)
        OR      A
        JR      Z,MK7
        CP      '.'
        JR      Z,MK7
        CP      '*'
        JR      NZ,MK6
        LD      A,'?'
MK5F:   LD      (DE),A
        INC     DE
        DJNZ    MK5F
        INC     HL
        JR      MK7
MK6:    CALL    UPPER
        LD      (DE),A
        INC     DE
        INC     HL
        DJNZ    MK5
MK7:    LD      A,(HL)          ; hasta el punto
        OR      A
        JR      Z,MKFIN
        CP      '.'
        JR      Z,MKEXT
        INC     HL
        JR      MK7
MKEXT:  INC     HL
        POP     DE
        PUSH    DE
        EX      DE,HL
        LD      BC,9
        ADD     HL,BC
        EX      DE,HL
        LD      B,3
MK8:    LD      A,(HL)
        OR      A
        JR      Z,MKFIN
        CP      '*'
        JR      NZ,MK9
        LD      A,'?'
MK8F:   LD      (DE),A
        INC     DE
        DJNZ    MK8F
        JR      MKFIN
MK9:    CALL    UPPER
        LD      (DE),A
        INC     DE
        INC     HL
        DJNZ    MK8
MKFIN:  POP     DE
        INC     DE
        LD      A,(DE)
        DEC     DE
        CP      ' '
        JR      Z,MKMAL
        OR      A
        RET
MKMAL:  SCF
        RET

; GLOB: HL nombre, DE donde van (12 bytes cada uno: unidad y los 11 del
; nombre), B cuantos caben. Devuelve A = cuantos.
GLOB:   LD      (GOUT),DE
        LD      A,B
        LD      (GMAX),A
        XOR     A
        LD      (GN),A
        LD      DE,GFCB
        CALL    MKFCB
        LD      A,0
        RET     C
        LD      C,26
        LD      DE,GDMA
        CALL    SYS
        LD      C,17
        LD      DE,GFCB
        CALL    SYS
GL1:    CP      0FFh
        JR      Z,GLFIN
        LD      C,A
        LD      A,(GMAX)
        LD      B,A
        LD      A,(GN)
        CP      B
        JR      NC,GLFIN
        LD      A,C
        AND     3
        RRCA
        RRCA
        RRCA
        LD      E,A
        LD      D,0
        LD      HL,GDMA+1
        ADD     HL,DE
        LD      DE,(GOUT)
        LD      A,(GFCB)
        LD      (DE),A
        INC     DE
        LD      B,11
GL2:    LD      A,(HL)
        AND     7Fh
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    GL2
        LD      (GOUT),DE
        LD      HL,GN
        INC     (HL)
        LD      C,18
        CALL    SYS
        JR      GL1
GLFIN:  LD      A,(GN)
        RET

; NM2FCB: HL nombre de GLOB, DE FCB
NM2FCB: PUSH    DE
        LD      B,36
        XOR     A
N2F1:   LD      (DE),A
        INC     DE
        DJNZ    N2F1
        POP     DE
        LD      BC,12
        LDIR
        RET

; FNAME: HL FCB, DE salida ("A:NOMBRE.EXT", terminado en 0)
FNAME:  PUSH    HL
        LD      A,(HL)
        OR      A
        JR      Z,FN1
        ADD     A,'A'-1
        LD      (DE),A
        INC     DE
        LD      A,':'
        LD      (DE),A
        INC     DE
FN1:    INC     HL
        LD      B,8
FN2:    LD      A,(HL)
        AND     7Fh
        CP      ' '
        JR      Z,FN3
        LD      (DE),A
        INC     DE
        INC     HL
        DJNZ    FN2
FN3:    POP     HL
        LD      BC,9
        ADD     HL,BC
        LD      A,(HL)
        AND     7Fh
        CP      ' '
        JR      Z,FN5
        LD      A,'.'
        LD      (DE),A
        INC     DE
        LD      B,3
FN4:    LD      A,(HL)
        AND     7Fh
        CP      ' '
        JR      Z,FN5
        LD      (DE),A
        INC     DE
        INC     HL
        DJNZ    FN4
FN5:    XOR     A
        LD      (DE),A
        RET

; FOPEN: DE FCB; acarreo si no se pudo
FOPEN:  LD      HL,12
        ADD     HL,DE
        LD      (HL),0          ; ex
        INC     HL
        INC     HL
        LD      (HL),0          ; s2
        LD      HL,32
        ADD     HL,DE
        LD      (HL),0          ; cr
        LD      C,15
FOP1:   CALL    SYS
        INC     A
        SCF
        RET     Z
        OR      A
        RET

FCLOSE: LD      C,16
        JP      SYS

; FMAKE: DE FCB; borra y crea. Acarreo si no se pudo.
FMAKE:  PUSH    DE
        LD      C,19
        CALL    SYS
        POP     DE
        PUSH    DE
        CALL    FOPEN0
        POP     DE
        LD      C,22
        JR      FOP1
FOPEN0: LD      HL,12
        ADD     HL,DE
        LD      (HL),0
        INC     HL
        INC     HL
        LD      (HL),0
        LD      HL,32
        ADD     HL,DE
        LD      (HL),0
        RET

; FWRITE: DE FCB, HL registro de 128. A = 0 bien.
FWRITE: PUSH    DE
        EX      DE,HL
        LD      C,26
        CALL    SYS
        POP     DE
        LD      C,21
        JP      SYS

; FREADN: DE FCB, HL bufer, B registros (hasta 16). A = cuantos leyo.
; En MP/M, de una sola llamada (BDOS 44); en CP/M, de a uno.
FREADN: LD      A,(MPM)
        OR      A
        JR      NZ,FRM
        LD      C,0
FRC1:   PUSH    BC
        PUSH    DE
        PUSH    HL
        EX      DE,HL
        LD      C,26
        CALL    SYS
        POP     HL
        POP     DE
        PUSH    DE
        PUSH    HL
        LD      C,20
        CALL    SYS
        POP     HL
        POP     DE
        POP     BC
        OR      A
        JR      NZ,FRC2
        INC     C
        PUSH    DE
        LD      DE,128
        ADD     HL,DE
        POP     DE
        DJNZ    FRC1
FRC2:   LD      A,C
        RET
FRM:    PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      E,B
        LD      D,0
        LD      C,44
        CALL    SYS
        POP     DE
        LD      C,26
        CALL    SYS
        POP     DE
        LD      C,20
        CALL    SYS
        PUSH    AF
        PUSH    HL
        LD      C,44
        LD      DE,1
        CALL    SYS
        POP     HL
        POP     AF
        POP     BC
        OR      A
        LD      A,B
        RET     Z
        LD      A,H             ; los que alcanzo a leer: la mitad alta de H
        RRCA
        RRCA
        RRCA
        RRCA
        AND     0Fh
        RET

; RREAD: DE FCB, HL numero de registro, BC bufer. A = 0 bien.
RREAD:  PUSH    BC
        PUSH    DE
        EX      DE,HL
        LD      BC,33
        ADD     HL,BC
        LD      (HL),E
        INC     HL
        LD      (HL),D
        INC     HL
        LD      (HL),0
        POP     HL              ; el FCB
        POP     DE              ; el bufer
        PUSH    HL
        LD      C,26
        CALL    SYS
        POP     DE
        LD      C,33
        JP      SYS

; RDOPEN: abre RFCB para RGETC; acarreo si no se pudo
RDOPEN: LD      HL,RBUF
        LD      (RQ),HL
        LD      (RE),HL
        XOR     A
        LD      (REOF),A
        LD      DE,RFCB
        JP      FOPEN

; RGETC: A = el byte que sigue; acarreo al final (no mira el ^Z)
RGETC:  LD      HL,(RQ)
        LD      DE,(RE)
        OR      A
        SBC     HL,DE
        JR      NC,RLLENA
        ADD     HL,DE
        LD      A,(HL)
        INC     HL
        LD      (RQ),HL
        OR      A
        RET
RLLENA: LD      A,(REOF)
        OR      A
        SCF
        RET     NZ
        LD      DE,RFCB
        LD      HL,RBUF
        LD      B,8
        CALL    FREADN
        OR      A
        JR      Z,RFIN
        LD      H,A
        LD      L,0
        SRL     H
        RR      L
        LD      DE,RBUF
        ADD     HL,DE
        LD      (RE),HL
        LD      (RQ),DE
        JR      RGETC
RFIN:   INC     A
        LD      (REOF),A
        SCF
        RET

; NOTFND: "nombre: not found". CANTOP: "nombre: cannot open". HL el nombre.
NOTFND: CALL    PSTR
        CALL    PRI
        DB      ': not found',13,10,0
        RET
CANTOP: CALL    PSTR
        CALL    PRI
        DB      ': cannot open',13,10,0
        RET

; CADA: para cada palabra que queda en la linea y cada archivo que casa con
; ella (hasta 64), llama a la rutina en HL con el FCB en RFCB y el nombre en
; SNAME (sin abrir). CNG dice cuantos casaron con esa palabra. Si la rutina
; vuelve con acarreo, CADA para y vuelve con acarreo.
CADA:   LD      (CRUT),HL
CA1:    CALL    NEXTARG
        CCF
        RET     NC
        LD      (CARG),HL
        LD      DE,NMS
        LD      B,64
        CALL    GLOB
        LD      (CNF),A
        LD      (CNG),A
        OR      A
        JR      NZ,CA2
        LD      HL,(CARG)
        CALL    NOTFND
        JR      CA1
CA2:    LD      HL,NMS
        LD      (CNP),HL
CA3:    LD      HL,(CNP)
        LD      DE,RFCB
        CALL    NM2FCB
        LD      (CNP),HL
        LD      HL,RFCB
        LD      DE,SNAME
        CALL    FNAME
        LD      HL,(CRUT)
        CALL    JPHL
        RET     C
        LD      HL,CNF
        DEC     (HL)
        JR      NZ,CA3
        JR      CA1
JPHL:   JP      (HL)

APTR:   DW      0
CRUT:   DW      0
CARG:   DW      0
CNP:    DW      0
CNF:    DB      0
CNG:    DB      0
GOUT:   DW      0
GMAX:   DB      0
GN:     DB      0
RQ:     DW      0
RE:     DW      0
REOF:   DB      0
