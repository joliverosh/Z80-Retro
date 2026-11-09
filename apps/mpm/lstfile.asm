; LSTFILE.COM - la impresora de MP/M II ZEPHYRUS a un archivo.
; Con LST=archivo en A:MPM.CFG, el XIOS guarda lo que se imprime en un anillo
; de 16 KB (una pagina de RAM). Este programa corre suelto (se desprende de la
; consola), cada medio segundo pasa lo nuevo del anillo al final del archivo y
; lo cierra tras 2 s sin impresion, para que se pueda leer con TYPE o PIP. El
; XIOS lo pone en marcha solo al arrancar.
; (C) OLIVEROS 2026
BDOS    EQU     5
LSTMD   EQU     0FFCCh          ; bloque del XIOS (ver xios.asm)
LSTPG   EQU     0FFCDh
LSTH    EQU     0FFCEh
LSTT    EQU     0FFD0h
CURPG2  EQU     0FFD2h
ANILLO  EQU     8000h           ; la pagina del anillo se pone en la ventana 2
TROZO   EQU     64              ; bytes por vez con las interrupciones apagadas

        ORG     100h
        LD      SP,PILA
        LD      C,12            ; MP/M?
        CALL    BDOS
        LD      A,H
        DEC     A
        JP      NZ,NOMPM
        LD      A,(LSTMD)
        DEC     A
        JP      NZ,NOARCH
        LD      C,32            ; usuario 0
        LD      E,0
        CALL    BDOS
        ; leer A:MPM.CFG
        LD      DE,CFCB
        LD      C,15
        CALL    BDOS
        INC     A
        JP      Z,NOCFG
        LD      DE,80h
        LD      C,26
        CALL    BDOS
        LD      DE,CFCB
        LD      C,20
        CALL    BDOS
        OR      A
        JP      NZ,NOCFG
        LD      DE,CFCB
        LD      C,16
        CALL    BDOS
        ; buscar "LST=" (sin importar mayusculas)
        LD      HL,80h
        LD      B,124
BU1:    LD      A,(HL)
        AND     5Fh
        CP      'L'
        JR      NZ,BU2
        PUSH    HL
        INC     HL
        LD      A,(HL)
        AND     5Fh
        CP      'S'
        JR      NZ,BU3
        INC     HL
        LD      A,(HL)
        AND     5Fh
        CP      'T'
        JR      NZ,BU3
        INC     HL
        LD      A,(HL)
        CP      '='
        JR      Z,BU4
BU3:    POP     HL
BU2:    INC     HL
        DJNZ    BU1
        JP      NOCFG
BU4:    POP     DE
        INC     HL              ; HL -> el nombre del archivo
        CALL    NOMBRE
        JP      NZ,MALNOM
        ; anunciar y soltar la consola
        LD      DE,MANUN
        LD      C,9
        CALL    BDOS
        LD      A,(FCB)
        ADD     A,'A'-1
        CALL    PCH
        LD      A,':'
        CALL    PCH
        LD      HL,FCB+1
        LD      B,11
AN1:    LD      A,(HL)
        CP      ' '
        CALL    NZ,PCH
        LD      A,B
        CP      4
        LD      A,'.'
        CALL    Z,PCH
        INC     HL
        DJNZ    AN1
        LD      DE,MFIN
        LD      C,9
        CALL    BDOS
        LD      C,147           ; desprenderse de la consola
        CALL    BDOS

; ---- el ciclo
CICLO:  LD      C,141           ; medio segundo
        LD      DE,30
        CALL    BDOS
        CALL    HAY
        JR      NZ,CI2
        LD      A,(ABIERTO)     ; nada nuevo: cerrar tras 2 s
        OR      A
        JR      Z,CICLO
        LD      HL,QUIETO
        INC     (HL)
        LD      A,(HL)
        CP      4
        JR      C,CICLO
        CALL    CERRAR
        JR      CICLO
CI2:    XOR     A
        LD      (QUIETO),A
        LD      A,(ABIERTO)
        OR      A
        CALL    Z,ABRIR
        LD      A,(ABIERTO)
        OR      A
        JR      Z,CICLO         ; no se pudo: se vuelve a probar
CI3:    CALL    TRAER           ; hasta TROZO bytes del anillo a BTROZ
        LD      A,B
        OR      A
        JR      Z,CI5
        LD      HL,BTROZ
CI4:    LD      A,(HL)
        PUSH    HL
        PUSH    BC
        CALL    PONER
        POP     BC
        POP     HL
        INC     HL
        DJNZ    CI4
        JR      CI3
CI5:    LD      A,(POS)         ; el registro a medias tambien (con 1A)
        OR      A
        JR      Z,CICLO
        LD      HL,REG
        LD      DE,REG2
        LD      BC,128
        LDIR
        LD      A,(POS)
        LD      E,A
        LD      D,0
        LD      HL,REG2
        ADD     HL,DE
CI6:    LD      (HL),1Ah
        INC     HL
        INC     E
        BIT     7,E
        JR      Z,CI6
        LD      DE,REG2
        CALL    ESCRIB
        JR      CICLO

; HAY: NZ si hay algo en el anillo
HAY:    LD      HL,(LSTT)
        LD      DE,(LSTH)
        OR      A
        SBC     HL,DE
        RET

; TRAER: hasta TROZO bytes del anillo a BTROZ; B = cuantos
TRAER:  LD      DE,BTROZ
        LD      B,0
        DI
        LD      A,(LSTPG)
        OUT     (62h),A
TR1:    LD      HL,(LSTH)
        LD      A,(LSTT)
        CP      L
        JR      NZ,TR2
        LD      A,(LSTT+1)
        CP      H
        JR      Z,TR9
TR2:    PUSH    HL
        LD      A,H
        OR      80h             ; (ANILLO)
        LD      H,A
        LD      A,(HL)
        LD      (DE),A
        INC     DE
        POP     HL
        INC     HL
        LD      A,H
        AND     3Fh
        LD      H,A
        LD      (LSTH),HL
        INC     B
        LD      A,B
        CP      TROZO
        JR      NZ,TR1
TR9:    LD      A,(CURPG2)
        OUT     (62h),A
        EI
        RET

; PONER: el byte A al archivo
PONER:  LD      HL,POS
        LD      E,(HL)
        LD      D,0
        INC     (HL)
        LD      HL,REG
        ADD     HL,DE
        LD      (HL),A
        LD      A,(POS)
        CP      128
        RET     NZ
        LD      DE,REG          ; registro lleno: escribirlo y pasar al siguiente
        CALL    ESCRIB
        XOR     A
        LD      (POS),A
        LD      HL,(RECNO)
        INC     HL
        LD      (RECNO),HL
        RET

; ESCRIB: el registro DE en RECNO
ESCRIB: LD      C,26
        CALL    BDOS
        LD      HL,(RECNO)
        LD      (FCB+33),HL
        XOR     A
        LD      (FCB+35),A
        LD      DE,FCB
        LD      C,34
        JP      BDOS

; ABRIR: abre el archivo (o lo crea) para seguir al final
ABRIR:  LD      HL,FCB+12
        LD      B,24
AB1:    LD      (HL),0
        INC     HL
        DJNZ    AB1
        LD      HL,0
        LD      (RECNO),HL
        XOR     A
        LD      (POS),A
        LD      DE,FCB
        LD      C,15
        CALL    BDOS
        INC     A
        JR      NZ,AB2
        LD      DE,FCB          ; no existe: crearlo
        LD      C,22
        CALL    BDOS
        INC     A
        RET     Z               ; disco lleno: ABIERTO sigue en 0
        JR      AB9
AB2:    LD      DE,FCB          ; tamano en registros
        LD      C,35
        CALL    BDOS
        LD      HL,(FCB+33)
        LD      A,H
        OR      L
        JR      Z,AB9
        DEC     HL              ; el ultimo registro: seguir donde esta el 1A
        LD      (RECNO),HL
        LD      DE,REG
        LD      C,26
        CALL    BDOS
        LD      HL,(RECNO)
        LD      (FCB+33),HL
        XOR     A
        LD      (FCB+35),A
        LD      DE,FCB
        LD      C,33
        CALL    BDOS
        LD      HL,REG
        LD      B,0
AB3:    LD      A,(HL)
        CP      1Ah
        JR      Z,AB4
        INC     HL
        INC     B
        BIT     7,B
        JR      Z,AB3
        LD      HL,(RECNO)      ; lleno: se sigue en el siguiente
        INC     HL
        LD      (RECNO),HL
        LD      B,0
AB4:    LD      A,B
        LD      (POS),A
AB9:    LD      A,1
        LD      (ABIERTO),A
        RET

CERRAR: LD      DE,FCB
        LD      C,16
        CALL    BDOS
        XOR     A
        LD      (ABIERTO),A
        RET

; NOMBRE: "X:NOMBRE.EXT" en HL -> FCB. NZ si no sirve.
NOMBRE: LD      DE,FCB+1
        LD      B,11
NO0:    LD      A,' '
        LD      (DE),A
        INC     DE
        DJNZ    NO0
        LD      A,1             ; A: si no dice
        LD      (FCB),A
        INC     HL
        LD      A,(HL)
        DEC     HL
        CP      ':'
        JR      NZ,NO1
        LD      A,(HL)
        AND     5Fh
        SUB     'A'-1
        CP      17
        JR      NC,NOMAL
        OR      A
        JR      Z,NOMAL
        LD      (FCB),A
        INC     HL
        INC     HL
NO1:    LD      DE,FCB+1
        LD      B,8
        CALL    PARTE
        LD      A,(FCB+1)
        CP      ' '
        JR      Z,NOMAL
        LD      A,(HL)
        CP      '.'
        JR      NZ,NO2
        INC     HL
        LD      DE,FCB+9
        LD      B,3
        CALL    PARTE
NO2:    XOR     A
        RET
NOMAL:  OR      1
        RET
PARTE:  LD      A,(HL)
        CP      '.'
        RET     Z
        CP      '!'
        RET     C
        CP      7Fh
        RET     NC
        CP      'a'
        JR      C,PA1
        AND     5Fh
PA1:    LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    PARTE
PA2:    LD      A,(HL)          ; lo que sobre del nombre se salta
        CP      '.'
        RET     Z
        CP      '!'
        RET     C
        INC     HL
        JR      PA2

PCH:    PUSH    BC
        PUSH    HL
        LD      E,A
        LD      C,2
        CALL    BDOS
        POP     HL
        POP     BC
        RET
NOMPM:  LD      DE,MNOMPM
        JR      SALE
NOARCH: LD      DE,MNOAR
        JR      SALE
NOCFG:  LD      DE,MNOCFG
        JR      SALE
MALNOM: LD      DE,MMAL
SALE:   LD      C,9
        CALL    BDOS
        LD      C,0
        JP      BDOS

MANUN:  DEFB    13,10,'Printer output to file $'
MFIN:   DEFB    13,10,'$'
MNOMPM: DEFB    13,10,'LSTFILE needs MP/M II ZEPHYRUS',13,10,'$'
MNOAR:  DEFB    13,10,'The printer is not set to a file (see A:MPM.CFG)',13,10,'$'
MNOCFG: DEFB    13,10,'Cannot read LST= in A:MPM.CFG',13,10,'$'
MMAL:   DEFB    13,10,'Bad file name in LST= of A:MPM.CFG',13,10,'$'
CFCB:   DEFB    1,'MPM     CFG'
        DEFS    24
FCB:    DEFS    36
ABIERTO: DEFB   0
QUIETO: DEFB    0
POS:    DEFB    0
RECNO:  DEFW    0
REG:    DEFS    128
REG2:   DEFS    128
BTROZ:  DEFS    TROZO
        DEFS    64
PILA:
        END
