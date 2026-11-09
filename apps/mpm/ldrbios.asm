; =============================================================================
;  LDRBIOS de MP/M II para la Z80-Retro (OLIVEROS 2026)
;  Va dentro de MPMLDR.COM, en 1700h. MPMLDR corre como programa de CP/M, con
;  ZIOS todavia debajo, asi que este BIOS lee el disco con el servicio 17 de
;  ZIOS (registro de CP/M) y escribe con el servicio 4.
;  La unidad 0 del cargador es la unidad LDRV de ZIOS (7 = H:, el disco en
;  flash, donde va MPM.SYS).
; =============================================================================
LDRV    EQU     7
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

MSG:    DEFB    13,10,'ZEPHYRUS LDRBIOS: loading MPM.SYS from drive ',LDRV+'A',':',13,10,0

BOOT:   LD      HL,MSG
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
        LD      H,LDRV          ; DSM del disco (servicio 36)
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
        LD      H,LDRV
        LD      L,0
        LD      C,17            ; A_CPMRD
        CALL    ZIOS
        OR      A
        RET     Z
        LD      A,1
        RET

TRK:    DEFW    0
SEC:    DEFW    0
DIRBF:  DEFS    128
ALV:    DEFS    64
        END
