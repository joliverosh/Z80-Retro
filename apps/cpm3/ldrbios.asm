;==================================================================================
; LDRBIOS: BIOS minimo para CPMLDR (cargador de CP/M 3) en la Z80-Retro.
;
; Se enlaza detras de CPMLDR.REL (DRI):  LINK CPMLDR[L100]=CPMLDR,LDRBIOS
; CPMLDR lee A:CPM3.SYS (usuario 0) con este BIOS, carga la parte comun y la
; parte con bancos (en el banco actual, que sera el banco 0) y salta al BIOS.
;
; Solo hace falta: BOOT, CONOUT, SELDSK/HOME/SETTRK/SETSEC/SETDMA, READ,
; SECTRN y MOVE. La unidad A: es la unidad logica 0 de ZIOS (ZLoader, al
; arrancar una entrada del menu con direccion relativa, pone en A: el disco
; donde esta la imagen).
;==================================================================================

import zapi.asm

ZIOS      EQU    0FE00h

          CSEG

          JP     BOOT         ;  0
          JP     NOP          ;  1 WBOOT
          JP     NOP          ;  2 CONST
          JP     NOP          ;  3 CONIN
          JP     CONOUT       ;  4
          JP     NOP          ;  5 LIST
          JP     NOP          ;  6 AUXOUT
          JP     NOP          ;  7 AUXIN
          JP     HOME         ;  8
          JP     SELDSK       ;  9
          JP     SETTRK       ; 10
          JP     SETSEC       ; 11
          JP     SETDMA       ; 12
          JP     READ         ; 13
          JP     NOP          ; 14 WRITE
          JP     NOP          ; 15 LISTST
          JP     SECTRN       ; 16
          JP     NOP          ; 17
          JP     NOP          ; 18
          JP     NOP          ; 19
          JP     NOP          ; 20
          JP     NOP          ; 21
          JP     NOP          ; 22
          JP     NOP          ; 23
          JP     NOP          ; 24
          JP     MOVE         ; 25
          JP     NOP          ; 26
          JP     NOP          ; 27
          JP     NOP          ; 28
          JP     NOP          ; 29
          JP     NOP          ; 30
          JP     NOP          ; 31
          JP     NOP          ; 32

BOOT:
NOP:      XOR    A
          RET

; CONOUT: caracter en C a la consola de ZIOS (dispositivo 1)
CONOUT:   LD     E,C
          LD     B,1
          LD     C,A_TXCHR
          JP     ZIOS

SELDSK:   LD     HL,0
          LD     A,C
          OR     A
          RET    NZ           ; solo A:
          LD     HL,DPH0
          RET

HOME:     LD     BC,0
SETTRK:   LD     (TRK),BC
          RET
SETSEC:   LD     (SECT),BC
          RET
SETDMA:   LD     (DMA),BC
          RET
SECTRN:   LD     H,B
          LD     L,C
          RET
MOVE:     EX     DE,HL
          LDIR
          EX     DE,HL
          RET

; READ: sector fisico de 512 bytes; LBA = pista*128 + sector en la unidad 0
READ:     LD     HL,(DMA)
          LD     C,A_DSKDM
          CALL   ZIOS
          LD     HL,(TRK)
          LD     H,L
          LD     L,0
          SRL    H
          RR     L
          LD     DE,(SECT)
          ADD    HL,DE
          EX     DE,HL
          LD     HL,0         ; H = unidad 0, L = 0
          LD     C,A_DSKRD
          CALL   ZIOS
          OR     A
          RET    Z
          LD     A,1
          RET

; Mismo formato que el BIOS de CP/M 3 y el de CP/M 2.2
DPB:      DW     512
          DB     4,15,0
          DW     2015,511
          DB     0FFh,0
          DW     8000h,1
          DB     2,3

DPH0:     DW     0
          DB     0,0,0,0,0,0,0,0,0
          DB     0
          DW     DPB
          DW     CSV
          DW     ALV
          DW     DIRBCB
          DW     DTABCB
          DW     0FFFFh       ; sin hash
          DB     0

DIRBCB:   DB     0FFh,0,0,0,0,0
          DW     0,0,DIRBUF
DTABCB:   DB     0FFh,0,0,0,0,0
          DW     0,0,DTABUF

TRK:      DW     0
SECT:     DW     0
DMA:      DW     0

CSV:      DS     4
ALV:      DS     512
DIRBUF:   DS     512
DTABUF:   DS     512

          END
