; ZLOADER.COM - sale de MP/M y vuelve a ZLoader sin presionar RESET.
; Pide confirmacion, espera a que nadie este usando el disco (toma la cola
; MXDisk de MP/M, asi no queda ninguna escritura a medias en la SD) y deja la
; maquina como despues de un RESET: SIO y CTC repuestos, la flash de ZLoader en
; las ventanas 0 y 1 y salto a 0000h. Lo que esta en el disco ya esta en la SD:
; el XIOS escribe en el acto. Los programas que estan corriendo se pierden.
; Tambien desde CP/M 2.2 y CP/M 3: dice el sistema que corre y se salta lo
; que es solo de MP/M (la cola MXDisk).
; (C) OLIVEROS 2026
BDOS    EQU     5
STUB    EQU     0FC00h          ; TMPD.DAT de MP/M: ya no se usa al salir

        ORG     100h
        LD      C,12            ; que sistema: H = 1 en MP/M, L = 31h en CP/M 3
        CALL    BDOS
        LD      A,H
        LD      (ESMPM),A
        LD      DE,NMPM
        DEC     A
        JR      Z,SIS1
        LD      DE,NCPM3
        LD      A,L
        CP      30h
        JR      NC,SIS1
        LD      DE,NCPM2
SIS1:   LD      (NOMBRE),DE
        LD      DE,MPREG
        LD      C,9
        CALL    BDOS
        LD      C,1             ; respuesta (con eco)
        CALL    BDOS
        AND     5Fh
        CP      'Y'
        JR      Z,SI
        LD      DE,MCRLF
        LD      C,9
        CALL    BDOS
        CALL    PNOM
        LD      DE,MNO
        LD      C,9
        JP      BDOS            ; y termina
SI:     LD      DE,MSAL
        LD      C,9
        CALL    BDOS
        CALL    PNOM
        LD      DE,MPUNT
        LD      C,9
        CALL    BDOS
        LD      A,(ESMPM)
        DEC     A
        JR      NZ,NOMP         ; en CP/M no hay MXDisk ni BDOS 141 (en 2.2)
        LD      C,141           ; medio segundo para que salga el texto
        LD      DE,30
        CALL    BDOS
        LD      DE,UQCB         ; MXDisk: cuando la tengamos, nadie usa el disco
        LD      C,135
        CALL    BDOS
        LD      DE,UQCB
        LD      C,137
        CALL    BDOS
NOMP:   LD      C,42            ; lo que el XIOS tiene sin escribir, a la SD
        RST     30h
        DI
        LD      HL,SALTO
        LD      DE,STUB
        LD      BC,SALTOL
        LDIR
        JP      STUB

; Se copia a FC00 (ventana 3) porque las ventanas 0 y 1 cambian a la flash.
SALTO:  LD      A,18h           ; SIO: reponer los dos canales
        OUT     (83h),A
        OUT     (82h),A
        LD      A,03h           ; CTC: reponer los cuatro canales
        OUT     (40h),A
        OUT     (41h),A
        OUT     (42h),A
        OUT     (43h),A
        IM      1
        XOR     A               ; flash 0 y 1 en las ventanas 0 y 1
        OUT     (60h),A
        INC     A
        OUT     (61h),A
        JP      0               ; ZLoader arranca como despues de un RESET
SALTOL  EQU     $-SALTO

UQCB:   DEFW    0
        DEFW    0
        DEFB    'MXDisk  '
MPREG:  DEFB    13,10,'Return to ZLoader? Running programs will be lost (Y/N) $'
MCRLF:  DEFB    13,10,'$'
MNO:    DEFB    ' continues.',13,10,'$'
MSAL:   DEFB    13,10,'Leaving $'
MPUNT:  DEFB    '...',13,10,'$'
NMPM:   DEFB    'MP/M$'
NCPM3:  DEFB    'CP/M 3$'
NCPM2:  DEFB    'CP/M 2.2$'
NOMBRE: DEFW    0
ESMPM:  DEFB    0

PNOM:   LD      DE,(NOMBRE)
        LD      C,9
        JP      BDOS
        END
