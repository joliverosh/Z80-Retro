; SETBOOT.COM - MP/M II ZEPHYRUS: graba el cargador de MP/M (H:MPMLDR.COM, o el
; archivo que se diga) en la zona de arranque de A: (sectores 70h-7Bh de la
; pista de sistema), la que usa BOS 5. Lo mismo que L + WI 70:A en ZLoader, pero
; desde MP/M. La entrada 5 de la tabla de arranque (WB) se pone una sola vez
; en ZLoader; esto solo cambia el cargador. Usa el servicio 43 del XIOS, con
; MXDisk tomado para que nadie use el disco mientras tanto. (C) OLIVEROS 2026
;   SETBOOT            H:MPMLDR.COM
;   SETBOOT d:archivo  otro cargador (hasta 6 KB)
BDOS    EQU     5
FCB1    EQU     5Ch
NREG    EQU     48              ; 0100-18FF: 12 sectores de 512
REG0    EQU     70h*4           ; el registro de A: donde empieza (sector 70h)

        ORG     100h
        LD      SP,PILA
        LD      C,12            ; MP/M? (BDOS 12: H = 1)
        CALL    BDOS
        LD      A,H
        DEC     A
        LD      DE,MNOMPM
        JP      NZ,FIN
        LD      A,(FCB1+1)      ; sin archivo: H:MPMLDR.COM
        CP      ' '
        JR      Z,S1
        LD      HL,FCB1
        LD      DE,FCB
        LD      BC,12
        LDIR
S1:     LD      HL,FCB+12
        LD      B,24
S2:     LD      (HL),0
        INC     HL
        DJNZ    S2
        LD      DE,FCB
        LD      C,15
        CALL    BDOS
        INC     A
        LD      DE,MNOHAY
        JP      Z,FIN
        LD      HL,IMG          ; todo el archivo a memoria (con MXDisk
        LD      B,NREG          ; tomado no se puede leer)
        LD      C,0             ; C = registros leidos
S3:     PUSH    BC
        PUSH    HL
        EX      DE,HL
        LD      C,26
        CALL    BDOS
        LD      DE,FCB
        LD      C,20
        CALL    BDOS
        POP     HL
        POP     BC
        OR      A
        JR      NZ,S4
        LD      DE,128
        ADD     HL,DE
        INC     C
        DJNZ    S3
        PUSH    BC              ; mas de 6 KB: no entra
        LD      DE,DMA
        PUSH    DE
        LD      C,26
        CALL    BDOS
        POP     DE
        LD      DE,FCB
        LD      C,20
        CALL    BDOS
        POP     BC
        OR      A
        LD      DE,MGRANDE
        JP      Z,FIN
S4:     LD      A,C
        OR      A
        LD      DE,MVACIO
        JP      Z,FIN
        LD      (NLEI),A
        LD      DE,FCB
        LD      C,16
        CALL    BDOS
        LD      DE,MPREG        ; seguro?
        LD      C,9
        CALL    BDOS
        LD      C,1
        CALL    BDOS
        AND     5Fh
        CP      'Y'
        LD      DE,MNO
        JP      NZ,FIN
        LD      DE,UQCB         ; MXDisk: cuando la tengamos, nadie usa el disco
        LD      C,135
        CALL    BDOS
        LD      DE,UQCB
        LD      C,137
        CALL    BDOS
        LD      HL,IMG
        LD      DE,REG0
        LD      A,(NLEI)
        LD      B,A
S5:     PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      B,0             ; unidad A:
        LD      C,43
        RST     30h
        POP     HL
        POP     DE
        POP     BC
        OR      A
        JR      NZ,S8
        PUSH    DE
        LD      DE,128
        ADD     HL,DE
        POP     DE
        INC     DE
        DJNZ    S5
        CALL    SUELTA
        LD      DE,MOK
        JP      FIN
S8:     CALL    SUELTA
        LD      DE,MERR
        JP      FIN
SUELTA: LD      DE,UQCB         ; MXDisk otra vez a la cola
        LD      C,139
        JP      BDOS

FIN:    LD      C,9
        CALL    BDOS
        LD      C,0
        JP      BDOS

UQCB:   DEFW    0
        DEFW    0
        DEFB    'MXDisk  '
FCB:    DEFB    8,'MPMLDR  COM'
        DEFS    24
NLEI:   DEFB    0
MNOMPM: DEFB    'SETBOOT needs MP/M II ZEPHYRUS$'
MNOHAY: DEFB    'Loader file not found$'
MGRANDE: DEFB   'The loader is larger than 6 KB$'
MVACIO: DEFB    'The loader file is empty$'
MPREG:  DEFB    'Write the MP/M loader to the boot area of A: (sectors 70h-7Bh)? (Y/N) $'
MNO:    DEFB    13,10,'Nothing written.$'
MOK:    DEFB    13,10,'Loader written. BOS 5 boots it (if the boot entry is not there yet,',13,10
        DEFB    'in ZLoader once: WB 5 70:A 0100 1800 0100 01 MP/M)$'
MERR:   DEFB    13,10,'Write error: the boot area may be incomplete$'
DMA:    DEFS    128
        DEFS    64
PILA:
IMG:    DEFS    NREG*128
        END
