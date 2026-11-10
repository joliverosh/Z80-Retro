; =============================================================================
;  LDRBIOS de MP/M II para la Z80-Retro (OLIVEROS 2026)
;  Va dentro de MPMLDR.COM, en 1700h. MPMLDR corre como programa de CP/M, con
;  ZIOS todavia debajo, asi que este BIOS lee el disco con el servicio 17 de
;  ZIOS (registro de CP/M) y escribe con el servicio 4.
;  La unidad 0 del cargador es A: (la SD) si su directorio tiene MPM.SYS en el
;  usuario 0; si no, H: (el disco en flash, que siempre trae uno). Asi MP/M se
;  actualiza copiando MPM.SYS a A:, sin grabar la flash; para volver al de la
;  flash basta borrar o renombrar A:MPM.SYS.
; =============================================================================
ZIOS    EQU     0FE00h

        ORG     1700h
        JP      BOOT
        JP      NADA            ; WBOOT
        JP      NADA            ; CONST
        JP      NADA            ; CONIN
        JP      CONOUT
        JP      NADA            ; LIST
        JP      NADA            ; AUXOUT
        JP      NADA            ; AUXIN
        JP      HOME
        JP      SELDSK
        JP      SETTRK
        JP      SETSEC
        JP      SETDMA
        JP      READ
        JP      NADA            ; WRITE
        JP      NADA            ; LISTST
        JP      SECTRAN

DPH:    DEFW    0,0,0,0,DIRBF,DPB,0,ALV
DPB:    DEFW    512             ; como el disco en flash de ZIOS
        DEFB    4,15,1
DSM:    DEFW    231
        DEFW    127
        DEFB    0C0h,0
        DEFW    0
        DEFW    0
DPBSD:  DEFW    512             ; el de las unidades de la SD (como xios.asm)
        DEFB    4,15,0
        DEFW    2015
        DEFW    511
        DEFB    0FFh,0
        DEFW    0
        DEFW    1

LDRV:   DEFB    7
MSG:    DEFB    13,10,'ZEPHYRUS LDRBIOS: loading MPM.SYS from drive '
MSGD:   DEFB    'H:',13,10,0
NAME:   DEFB    0,'MPM     SYS'

BOOT:   CALL    FIND
        LD      HL,MSG
BOOT1:  LD      A,(HL)
        OR      A
        RET     Z
        PUSH    HL
        LD      C,A
        CALL    CONOUT
        POP     HL
        INC     HL
        JR      BOOT1

NADA:   XOR     A
        RET

CONOUT: LD      E,C
        LD      B,0
        LD      C,4
        JP      ZIOS

HOME:   LD      BC,0
SETTRK: LD      (TRK),BC
        RET
SETSEC: LD      (SEC),BC
        RET
SECTRAN: LD     H,B
        LD      L,C
        RET
SETDMA: LD      H,B
        LD      L,C
        LD      C,12            ; A_DSKDM
        JP      ZIOS

SELDSK: LD      HL,0
        LD      A,C
        OR      A
        RET     NZ
        CALL    BOOT
        LD      A,(LDRV)
        OR      A
        JR      Z,SEL1          ; A: ya tiene el DPB de la SD
        LD      H,A             ; DSM del disco en flash (servicio 36)
        LD      C,36
        CALL    ZIOS
        LD      (DSM),DE
        LD      A,D
        OR      A
        JR      Z,SEL1
        XOR     A
        LD      (DPB+4),A       ; EXM = 0 con DSM > 255
SEL1:   LD      HL,DPH
        RET

READ:   LD      HL,(SEC)        ; HLDE = unidad, 0, pista*512 + sector
        LD      A,(TRK)
        AND     3Fh
        ADD     A,A
        OR      H
        LD      D,A
        LD      E,L
        LD      A,(LDRV)
        LD      H,A
        LD      L,0
        LD      C,17            ; A_CPMRD
        CALL    ZIOS
        OR      A
        RET     Z
        LD      A,1
        RET

; FIND: una sola vez, busca MPM.SYS (usuario 0) en las 512 entradas del
; directorio de A:, los registros 512-639 (la pista 1). Si esta, la unidad 0
; pasa a ser A: con el DPB de la SD. Si A: no se lee, queda H:.
FIND:   LD      A,(HECHO)
        OR      A
        RET     NZ
        INC     A
        LD      (HECHO),A
        LD      BC,DIRBF
        CALL    SETDMA
        LD      DE,512
FD1:    PUSH    DE
        LD      HL,0            ; unidad 0 de ZIOS (A:)
        LD      C,17
        CALL    ZIOS
        POP     DE
        OR      A
        RET     NZ
        LD      HL,DIRBF
        LD      B,4
FD2:    PUSH    BC
        PUSH    HL
        PUSH    DE
        LD      DE,NAME
        LD      A,(DE)          ; el usuario se compara entero
        CP      (HL)
        JR      NZ,FD4
        LD      B,11
FD3:    INC     HL
        INC     DE
        LD      A,(HL)          ; sin los atributos (bit 7)
        AND     7Fh
        EX      DE,HL
        CP      (HL)
        EX      DE,HL
        JR      NZ,FD4
        DJNZ    FD3
        INC     HL              ; y es la extension 0 (si no, el archivo
        LD      A,(HL)          ; esta roto y se usa el de la flash)
        AND     1Fh
        JR      NZ,FD4
        INC     HL
        INC     HL
        LD      A,(HL)
        AND     3Fh
        JR      NZ,FD4
        POP     DE              ; esta
        POP     HL
        POP     BC
        XOR     A
        LD      (LDRV),A
        LD      A,'A'
        LD      (MSGD),A
        LD      HL,DPBSD
        LD      DE,DPB
        LD      BC,15
        LDIR
        RET
FD4:    POP     DE
        POP     HL
        POP     BC
        LD      A,L
        ADD     A,32
        LD      L,A
        JR      NC,FD5
        INC     H
FD5:    DJNZ    FD2
        INC     DE
        LD      A,E
        CP      128             ; 512+128 = 0280h
        JR      NZ,FD1
        RET

HECHO:  DEFB    0
TRK:    DEFW    0
SEC:    DEFW    0
DIRBF:  DEFS    128
ALV:    DEFS    256             ; DSM 2015 de la SD: 252 bytes
        END
