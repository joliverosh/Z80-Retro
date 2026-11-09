; =============================================================================
;  XIOS de MP/M II para la Z80-Retro (Z80 CPU Rev 2.2 y ZEPHYRUS Rev 2.3)
;  OLIVEROS 2026 - sobre ZLoader/ZIOS v6 de Peter Wilson (MIT)
;
;  Memoria: las 4 ventanas de 16 KB del 74LS670 (puertos 60h-63h).
;    - Ventana 3 (C000-FFFF): memoria comun, la misma pagina siempre.
;    - Ventanas 0-2 (0000-BFFF): un banco = 3 paginas de 16 KB. El banco 0 es
;      el del sistema (las paginas que dejo ZIOS); los bancos 1-7 son de los
;      usuarios y salen de las paginas de RAM libres (20h-3Fh).
;  Consolas: 0 = SIO A, 1 = SIO B, con recepcion por interrupcion (IM 2, los
;    mismos vectores que ZIOS: SIO en FFE0-FFEE, CTC en FFF0-FFF6).
;  Reloj: canal 1 del CTC tal como lo deja ZIOS (120 Hz a 7,3728 MHz); la
;    bandera 1 de MP/M se pone a 60 Hz.
;  Discos: A-H como en CP/M 2.2 de la placa. Unidades en la SD (tarjeta 0 o 1)
;    con driver SPI propio; la que ZIOS tenga en el disco en flash (H:) se lee
;    mapeando la pagina de flash. El mapa de unidades se le pide a ZIOS al
;    arrancar (servicio 11), antes de tomar la maquina.
;  Por encima de MP/M (tope FD) quedan FE00-FFFF: el puente de ZIOS hasta que
;  SYSTEMINIT toma la maquina, y despues los buferes de las consolas, la pila de
;  interrupciones y la tabla de vectores.
;
;  Se ensambla dos veces (ORG 0 y ORG 100h) para sacar el BNKXIOS.SPR.
; =============================================================================
NMBCNS  EQU     2               ; consolas
NDRV    EQU     8               ; unidades A-H
TPS     EQU     60              ; tics por segundo para MP/M (GENSYS)

PGPORT  EQU     60h             ; registros de pagina: 60h + ventana
SIOAD   EQU     81h
SIOAC   EQU     83h
SIOBD   EQU     80h
SIOBC   EQU     82h
SPIL    EQU     68h             ; SPI: dato con el reloj en bajo
SPIH    EQU     69h             ;      y en alto
SPIIN   EQU     64h             ; MISO en el bit 0
SPICS   EQU     64h             ; seleccion de la tarjeta
CSOFF   EQU     01h
ZIOS    EQU     0FE00h          ; entrada al API de ZIOS desde la aplicacion

RXA     EQU     0FE00h          ; bufer circular de la consola 0 (128 bytes)
RXB     EQU     0FE80h          ; bufer circular de la consola 1
ISTK    EQU     0FF80h          ; pila de las interrupciones (FF00-FF7F)
VSIO    EQU     0FFE0h          ; vectores de la SIO (WR2 = E0h, lo puso ZIOS)
VCTC    EQU     0FFF0h          ; vectores del CTC (vector F0h, lo puso ZIOS)

POLL    EQU     131
FLAGSET EQU     133

        ORG     ORIGEN

; ------------------------------------------------------------- tabla de saltos
        JP      COMMONBASE
        JP      WARMSTART
        JP      CONST
        JP      CONIN
        JP      CONOUT
        JP      LIST
        JP      NADA            ; PUNCH
        JP      NADA            ; READER
        JP      HOME
        JP      SELDSK
        JP      SETTRK
        JP      SETSEC
        JP      SETDMA
        JP      READ
        JP      WRITE
        JP      NADA            ; LISTST
        JP      SECTRAN
        JP      SELMEM
        JP      POLLDEV
        JP      STCLK
        JP      SPCLK
        JP      EXITRG
        JP      MAXCON
        JP      SYSINIT
        JP      IDLE

; ================================================================ parte en banco
; (solo datos que usa el BDOS con el banco 0 puesto)
DPBASE:
        DEFW    0,0,0,0,DIRBF,DPBSD,CSV,ALV0
        DEFW    0,0,0,0,DIRBF,DPBSD,CSV,ALV1
        DEFW    0,0,0,0,DIRBF,DPBSD,CSV,ALV2
        DEFW    0,0,0,0,DIRBF,DPBSD,CSV,ALV3
        DEFW    0,0,0,0,DIRBF,DPBSD,CSV,ALV4
        DEFW    0,0,0,0,DIRBF,DPBSD,CSV,ALV5
        DEFW    0,0,0,0,DIRBF,DPBSD,CSV,ALV6
        DEFW    0,0,0,0,DIRBF,DPBSD,CSV,ALV7
CSV:    DEFS    4
ALV0:   DEFS    253
ALV1:   DEFS    253
ALV2:   DEFS    253
ALV3:   DEFS    253
ALV4:   DEFS    253
ALV5:   DEFS    253
ALV6:   DEFS    253
ALV7:   DEFS    253

; ------------------------------------------------------------- arranque
; C = RST del depurador, DE = entrada del depurador, HL = tabla de saltos del XIOS
SYSINIT: LD     (SVSP),SP
        LD      SP,LSTK
        LD      (JTBL),HL
        LD      (DBGE),DE
        LD      A,C
        LD      (DBGR),A
        CALL    PGQRY           ; ---- 1. paginas del banco 0 (en la comun)
        CALL    RTCTOD          ; ---- 1b. la hora del DS1307 (servicio 28) a la TOD de XDOS
        ; ---- 2. mapa de unidades (servicio 11) y disco en flash (servicio 36)
        LD      HL,ZMAP
        LD      B,0
        LD      C,11
        CALL    ZIOS
        LD      HL,ZMAP         ; tarjeta y disco virtual*32 de A-H
        LD      DE,DCARD
        LD      IX,DMW
        LD      B,NDRV
SI2:    LD      A,(HL)          ; tarjeta
        LD      (DE),A
        INC     DE
        INC     HL
        PUSH    DE
        LD      E,(HL)          ; disco virtual
        INC     HL
        LD      D,(HL)
        INC     HL
        PUSH    HL
        EX      DE,HL
        ADD     HL,HL           ; * 32: sus bits van sobre los 13 del bloque
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      (IX+0),L
        LD      (IX+1),H
        POP     HL
        POP     DE
        INC     IX
        INC     IX
        DJNZ    SI2
        LD      HL,DCARD        ; unidad del disco en flash -> su DSM
        LD      B,0
SI3:    LD      A,(HL)
        CP      3
        JR      NZ,SI4
        PUSH    HL
        PUSH    BC
        LD      H,B
        LD      C,36
        CALL    ZIOS
        LD      (DPBFL+5),DE
        LD      A,D             ; EXM = 0 si DSM > 255
        OR      A
        JR      Z,SI3B
        XOR     A
        LD      (DPBFL+4),A
SI3B:   POP     BC
        POP     HL
        LD      A,B             ; su DPH apunta al DPB de la flash
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,A
        PUSH    HL
        LD      E,A
        LD      D,0
        LD      HL,DPBASE+10
        ADD     HL,DE
        LD      DE,DPBFL
        LD      (HL),E
        INC     HL
        LD      (HL),D
        POP     HL
SI4:    INC     HL
        INC     B
        LD      A,B
        CP      NDRV
        JR      NZ,SI3
        LD      C,31            ; tics por segundo de ZIOS (120 o 240)
        CALL    ZIOS
        LD      B,0             ; divisor para 60 Hz
SI5:    INC     B
        SUB     TPS
        JR      Z,SI5B
        JR      NC,SI5
SI5B:   LD      A,B
        LD      (TDIVN),A
        LD      (TDIV),A
        ; ---- 3. desde aqui la maquina es de MP/M
        DI
        ; pagina comun: la que muestra en la ventana 0 lo mismo que FIRMA
        LD      C,20h
SI6:    LD      A,C
        OUT     (PGPORT),A
        LD      HL,FIRMA
        LD      (HL),5Ah
        RES     7,H             ; misma direccion en la ventana 0
        RES     6,H
        LD      A,(HL)
        CP      5Ah
        JR      NZ,SI7
        LD      HL,FIRMA
        LD      (HL),0A5h
        RES     7,H
        RES     6,H
        LD      A,(HL)
        CP      0A5h
        JR      Z,SI8
SI7:    INC     C
        LD      A,C
        CP      40h
        JR      NZ,SI6
SI8:    LD      A,C
        LD      (CMNPG),A
        LD      A,(BNKPG)
        OUT     (PGPORT),A
        ; paginas de los bancos 1-7: las libres, de arriba hacia abajo
        LD      HL,BNKPG+3
        LD      C,3Fh
        LD      B,21
SI9:    LD      A,C
        CALL    USADA
        JR      Z,SI10
        LD      (HL),C
        INC     HL
        DEC     B
SI10:   DEC     C
        INC     B               ; (no cambia Z)
        DEC     B
        JR      NZ,SI9
        CALL    CINIT           ; las paginas que sobran: cache de disco
        ; pagina cero de cada banco: JP a la tabla de saltos, el RST del
        ; depurador y un RET en 30h (los programas de la Z80-Retro llaman a ZIOS)
        LD      B,7
SI11:   LD      A,B             ; ventana 0 <- primera pagina del banco B
        ADD     A,A
        ADD     A,B
        LD      E,A
        LD      D,0
        LD      HL,BNKPG
        ADD     HL,DE
        LD      A,(HL)
        OUT     (PGPORT),A
        LD      A,0C3h
        LD      (0),A
        LD      HL,(JTBL)
        LD      (1),HL
        LD      A,(DBGR)
        ADD     A,A
        ADD     A,A
        ADD     A,A
        LD      L,A
        LD      H,0
        LD      (HL),0C3h
        INC     HL
        LD      DE,(DBGE)
        LD      (HL),E
        INC     HL
        LD      (HL),D
        LD      A,(DBGR)
        CP      6
        JR      Z,SI12
        LD      A,0C9h
        LD      (30h),A
SI12:   DEC     B
        JP      P,SI11
        LD      A,(BNKPG)       ; banco 0 otra vez en la ventana 0
        LD      (CURPG0),A
        OUT     (PGPORT),A
        ; vectores: SIO (WR2 = E0h) y CTC (F0h); I = FFh, IM 2
        LD      HL,VECS
        LD      DE,VSIO
        LD      BC,24
        LDIR
        LD      A,0FFh
        LD      I,A
        IM      2
        XOR     A               ; buferes vacios
        LD      (HDA),A
        LD      (TLA),A
        LD      (HDB),A
        LD      (TLB),A
        LD      HL,SIOINI
        LD      B,SIOINN
SI13:   LD      C,(HL)
        INC     HL
        LD      A,(HL)
        INC     HL
        OUT     (C),A
        DJNZ    SI13
        ; SD: SDHC o SDSC (CMD58, bit CCS del OCR)
        LD      A,0FFh
        LD      (CCARD),A
        XOR     A
        CALL    SDTIPO
        LD      A,1
        CALL    SDTIPO
        ; mensaje
        LD      HL,MSG
SI14:   LD      A,(HL)
        OR      A
        JR      Z,SI15
SI14B:  IN      A,(SIOAC)
        AND     4
        JR      Z,SI14B
        LD      A,(HL)
        OUT     (SIOAD),A
        INC     HL
        JR      SI14
SI15:   LD      A,(NCPG)        ; "cache de nn KB"
        OR      A
        JR      Z,SI15C
        ADD     A,A             ; KB = paginas * 16
        ADD     A,A
        ADD     A,A
        ADD     A,A
        LD      B,'0'-1
SI15A:  INC     B
        SUB     10
        JR      NC,SI15A
        ADD     A,'0'+10
        LD      C,A
        LD      A,B
        CALL    SIOPUT
        LD      A,C
        CALL    SIOPUT
        LD      HL,MSGC
SI15B:  LD      A,(HL)
        OR      A
        JR      Z,SI15C
        CALL    SIOPUT
        INC     HL
        JR      SI15B
SI15C:  LD      SP,(SVSP)
        EI
        RET

; RTCTOD: pide la fecha a ZIOS (servicio 28: seg, min, hora, dia, mes, anio en
; BCD) y la escribe en la TOD de XDOS, cuya direccion esta en SYSDAT+252. Si el
; reloj no responde o da algo que no es una fecha, deja la TOD como esta.
RTCTOD: LD      HL,TBUF
        LD      C,28
        CALL    ZIOS
        LD      HL,TBUF         ; validar: digitos BCD y rangos
        LD      DE,TMAX
        LD      B,6
RT1:    LD      A,(HL)
        AND     0Fh
        CP      10
        RET     NC
        LD      A,(DE)
        LD      C,A
        LD      A,(HL)
        CP      C
        RET     NC              ; fuera de rango (o FF sin reloj)
        INC     HL
        INC     DE
        DJNZ    RT1
        LD      A,(TBUF+3)      ; dia y mes empiezan en 1
        OR      A
        RET     Z
        LD      A,(TBUF+4)
        OR      A
        RET     Z
        ; dias desde el 31/12/1977: anios completos desde 1978
        LD      A,(TBUF+5)
        CALL    BCDBIN
        ADD     A,22
        LD      B,A
        LD      HL,0
        LD      C,78
RT2:    LD      A,B
        OR      A
        JR      Z,RT4
        LD      DE,365
        LD      A,C
        AND     3
        JR      NZ,RT3
        INC     DE              ; bisiesto (1980..2096)
RT3:    ADD     HL,DE
        INC     C
        DJNZ    RT2
RT4:    LD      A,(TBUF+4)      ; meses ya pasados
        CALL    BCDBIN
        LD      B,A
        LD      DE,MESES
RT5:    DEC     B
        JR      Z,RT6
        LD      A,(DE)
        ADD     A,L
        LD      L,A
        JR      NC,RT5B
        INC     H
RT5B:   INC     DE
        JR      RT5
RT6:    LD      A,(TBUF+4)      ; 29 de febrero ya pasado
        CALL    BCDBIN
        CP      3
        JR      C,RT7
        LD      A,(TBUF+5)
        CALL    BCDBIN
        AND     3
        JR      NZ,RT7
        INC     HL
RT7:    LD      A,(TBUF+3)
        CALL    BCDBIN
        LD      E,A
        LD      D,0
        ADD     HL,DE
        EX      DE,HL           ; DE = dia
        LD      HL,(SYSDAT)
        LD      L,252
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A             ; HL = TOD
        LD      (HL),E
        INC     HL
        LD      (HL),D
        INC     HL
        LD      A,(TBUF+2)
        LD      (HL),A
        INC     HL
        LD      A,(TBUF+1)
        LD      (HL),A
        INC     HL
        LD      A,(TBUF+0)
        LD      (HL),A
        RET
BCDBIN: PUSH    BC
        LD      B,A
        AND     0F0h
        RRCA
        LD      C,A
        RRCA
        RRCA
        ADD     A,C
        LD      C,A
        LD      A,B
        AND     0Fh
        ADD     A,C
        POP     BC
        RET
TBUF:   DEFS    6
TMAX:   DEFB    60h,60h,24h,32h,13h,9Ah ; limites (exclusivos) en BCD
MESES:  DEFB    31,28,31,30,31,30,31,31,30,31,30,31

; GETBLK: deja el bloque en BUF (Z = bien). Flash: lee el registro de 128 bytes.
GETBLK: LD      A,(DSKC)
        CP      3
        JP      Z,FLREC
        LD      HL,CCARD        ; ya esta en el bufer?
        CP      (HL)
        JR      NZ,GB0
        LD      HL,(BLK)
        LD      DE,(CBLK)
        OR      A
        SBC     HL,DE
        JR      NZ,GB0
        LD      HL,(BLK+2)
        LD      DE,(CBLK+2)
        SBC     HL,DE
        RET     Z
GB0:    LD      A,(NCPG)        ; con cache: buscarlo alli
        OR      A
        JP      NZ,CGET
GB1:    LD      A,0FFh
        LD      (CCARD),A       ; invalido mientras se lee
        LD      (BUFSL),A
        CALL    SDRD
        RET     NZ
        LD      A,(DSKC)
        LD      (CCARD),A
        LD      HL,(BLK)
        LD      (CBLK),HL
        LD      HL,(BLK+2)
        LD      (CBLK+2),HL
        XOR     A
        RET


; ------------------------------------------------------------- cache de disco
; Bloques de 512 bytes de la SD en las paginas de RAM que sobran (hasta 4, o sea
; 128 bloques = 64 KB). Asociativa de 2 vias: conjunto = (bloque bajo + bloque
; medio + tarjeta) AND (NCONJ-1). Escritura inmediata (write-through): la tarjeta
; siempre tiene los datos al dia, la cache solo evita relecturas (el directorio,
; los programas que se cargan una y otra vez).
; Todo esto corre con el banco 0 puesto: la pagina de la cache se pone un momento
; en la ventana 0 con las interrupciones apagadas, de 64 en 64 bytes para no
; perder caracteres de las consolas.

; CGET: el bloque BLK de la tarjeta DSKC. GMODE = 0: basta el registro OFS en
; BUF; GMODE = 1: el bloque entero en BUF. Z = bien.
CGET:   CALL    CLOOK
        LD      (CSLOT),A
        JR      NZ,CGMISS
        CALL    SLADR           ; acierto: HL = bloque en la ventana 0
        LD      A,(GMODE)
        OR      A
        JR      NZ,CGFULL
        CALL    RECOFF          ; solo el registro
        ADD     HL,DE
        PUSH    HL
        CALL    BUFPTR
        EX      DE,HL
        POP     HL
        LD      A,0FFh          ; BUF queda con un solo registro: no es un bloque
        LD      (CCARD),A
        LD      (BUFSL),A
        LD      BC,128
        CALL    CPYC
        XOR     A
        RET
CGFULL: LD      DE,BUF
        LD      BC,512
        CALL    CPYC
        CALL    BUFTAG
        XOR     A
        RET
CGMISS: CALL    TAGADR          ; el hueco elegido queda invalido mientras se lee
        LD      (HL),0FFh
        CALL    GB1             ; leer de la tarjeta a BUF
        RET     NZ
        LD      A,(CSLOT)
        CALL    SLADR
        EX      DE,HL
        LD      HL,BUF
        LD      BC,512
        CALL    CPYC
        LD      A,(CSLOT)       ; etiqueta = tarjeta y bloque
        CALL    TAGADR
        LD      A,(DSKC)
        LD      (HL),A
        INC     HL
        EX      DE,HL
        LD      HL,BLK
        LD      BC,4
        LDIR
        LD      A,(CSLOT)       ; la via recien llenada es la mas reciente
        CALL    SETLRU
        CALL    BUFTAG
        XOR     A
        RET

; BUFTAG: BUF tiene el bloque BLK entero y su copia esta en el hueco CSLOT
BUFTAG: LD      A,(DSKC)
        LD      (CCARD),A
        LD      HL,(BLK)
        LD      (CBLK),HL
        LD      HL,(BLK+2)
        LD      (CBLK+2),HL
        LD      A,(CSLOT)
        LD      (BUFSL),A
        RET

; CWRREC: el registro que WRITE acaba de escribir en la tarjeta, tambien en la
; cache (si el bloque de BUF esta en ella). Devuelve A = 0 (bien).
CWRREC: LD      A,(BUFSL)
        CP      0FFh
        JR      Z,CWR9
        CALL    SLADR
        CALL    RECOFF
        ADD     HL,DE
        PUSH    HL              ; registro en la cache
        CALL    BUFPTR          ; HL = registro en BUF (BUFPTR usa DE)
        POP     DE
        LD      BC,128
        CALL    CPYC
CWR9:   XOR     A
        RET

; CWRERR: la escritura fallo. BUF tiene datos que la tarjeta no tiene: se
; olvidan BUF y su copia en la cache, y la proxima lectura va a la tarjeta.
CWRERR: LD      A,(BUFSL)
        CP      0FFh
        JR      Z,CWE9
        CALL    TAGADR
        LD      (HL),0FFh
CWE9:   LD      A,0FFh
        LD      (CCARD),A
        LD      (BUFSL),A
        RET

; CLOOK: busca DSKC/BLK. Z: esta, A = hueco. NZ: no esta, A = hueco a usar.
CLOOK:  LD      A,(BLK)
        LD      HL,BLK+1
        ADD     A,(HL)
        LD      HL,DSKC
        ADD     A,(HL)
        LD      HL,NCONJ
        AND     (HL)            ; NCONJ = conjuntos - 1
        LD      (CSET),A
        ADD     A,A
        LD      B,A             ; via 0
        CALL    TAGCMP
        JR      Z,CLHIT
        INC     B               ; via 1
        CALL    TAGCMP
        JR      Z,CLHIT
        DEC     B               ; no esta: una via vacia, o la menos reciente
        LD      A,B
        CALL    TAGADR
        LD      A,(HL)
        INC     A
        JR      Z,CLMISS        ; via 0 vacia
        INC     B
        LD      A,B
        CALL    TAGADR
        LD      A,(HL)
        INC     A
        JR      Z,CLMISS        ; via 1 vacia
        DEC     B
        LD      HL,CLRU
        LD      A,(CSET)
        ADD     A,L
        LD      L,A
        JR      NC,CLM1
        INC     H
CLM1:   LD      A,(HL)          ; via usada mas recientemente
        XOR     1
        ADD     A,B
        LD      B,A
CLMISS: OR      0FFh            ; NZ sin perder el hueco
        LD      A,B
        RET
CLHIT:  LD      A,B
        PUSH    AF
        CALL    SETLRU
        POP     AF
        CP      A               ; Z
        RET

; SETLRU: el hueco A es la via mas reciente de su conjunto
SETLRU: LD      B,A
        SRL     A               ; conjunto
        LD      HL,CLRU
        ADD     A,L
        LD      L,A
        JR      NC,SL1
        INC     H
SL1:    LD      A,B
        AND     1
        LD      (HL),A
        RET

; TAGCMP: Z si la etiqueta del hueco B es DSKC/BLK. Conserva B.
TAGCMP: LD      A,B
        CALL    TAGADR
        LD      A,(DSKC)
        CP      (HL)
        RET     NZ
        INC     HL
        LD      DE,BLK
        LD      C,4
TC1:    LD      A,(DE)
        CP      (HL)
        RET     NZ
        INC     HL
        INC     DE
        DEC     C
        JR      NZ,TC1
        RET

; TAGADR: HL = etiqueta del hueco A (5 bytes: tarjeta, bloque de 32 bits)
TAGADR: LD      L,A
        LD      H,0
        LD      D,H
        LD      E,L
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,DE
        LD      DE,CTAG
        ADD     HL,DE
        RET

; SLADR: hueco A -> CPAGE = su pagina, HL = su direccion en la ventana 0
SLADR:  LD      B,A
        RLCA                    ; pagina = CPG[hueco / 32]
        RLCA
        RLCA
        AND     7
        LD      E,A
        LD      D,0
        LD      HL,CPG
        ADD     HL,DE
        LD      A,(HL)
        LD      (CPAGE),A
        LD      A,B             ; direccion = (hueco AND 31) * 512
        AND     1Fh
        ADD     A,A
        LD      H,A
        LD      L,0
        RET

; RECOFF: DE = OFS * 128 (desplazamiento del registro dentro del bloque)
RECOFF: LD      A,(OFS)
        RRCA
        LD      E,A
        AND     1
        LD      D,A
        LD      A,E
        AND     80h
        LD      E,A
        RET

; CPYC: copia BC bytes (multiplo de 64) de HL a DE con la pagina CPAGE puesta en
; la ventana 0. Las interrupciones se apagan solo durante cada trozo de 64 bytes.
CPYC:   PUSH    BC
        LD      A,I             ; P/V = IFF2
        DI
        PUSH    AF
        LD      A,(CPAGE)
        OUT     (PGPORT),A
        LD      BC,64
        LDIR
        LD      A,(CURPG0)
        OUT     (PGPORT),A
        POP     AF
        JP      PO,CPY1
        EI
CPY1:   POP     BC
        LD      A,C
        SUB     64
        LD      C,A
        JR      NC,CPY2
        DEC     B
CPY2:   LD      A,B
        OR      C
        JR      NZ,CPYC
        RET

; CINIT: paginas libres para la cache (las que no son de ningun banco ni la
; comun), de arriba hacia abajo: 4, 2, 1 o ninguna. Etiquetas vacias.
CINIT:  LD      HL,CPG
        LD      B,0             ; paginas encontradas
        LD      C,3Fh
CI1:    LD      A,C
        CALL    USADA
        JR      Z,CI2
        LD      (HL),C
        INC     HL
        INC     B
        LD      A,B
        CP      4
        JR      Z,CI3
CI2:    DEC     C
        LD      A,C
        CP      1Fh
        JR      NZ,CI1
CI3:    LD      A,B             ; 3 -> 2 (los conjuntos van en potencia de 2)
        CP      3
        JR      NZ,CI4
        DEC     A
CI4:    LD      (NCPG),A
        ADD     A,A             ; conjuntos = paginas * 16
        ADD     A,A
        ADD     A,A
        ADD     A,A
        DEC     A
        LD      (NCONJ),A
        LD      HL,CTAG         ; todas las etiquetas vacias (tarjeta FF)
        LD      DE,CTAG+1
        LD      (HL),0FFh
        LD      BC,5*128-1
        LDIR
        LD      A,0FFh
        LD      (BUFSL),A
        RET

GMODE:  DEFB    0               ; 0 = basta el registro, 1 = bloque entero
CSLOT:  DEFB    0
CSET:   DEFB    0
BUFSL:  DEFB    0FFh            ; hueco que tiene el bloque de BUF (FF = ninguno)
NCPG:   DEFB    0               ; paginas de cache (0 = sin cache)
NCONJ:  DEFB    0
CPAGE:  DEFB    0
CPG:    DEFS    4
CLRU:   DEFS    64              ; via mas reciente de cada conjunto
CTAG:   DEFS    5*128           ; etiquetas: tarjeta (FF = vacio) y bloque

; USADA: Z si la pagina A es del banco 0, la comun o ya esta asignada
USADA:  PUSH    HL
        PUSH    BC
        LD      HL,BNKPG
        LD      B,24
US1:    CP      (HL)
        JR      Z,US9
        INC     HL
        DJNZ    US1
        LD      HL,CMNPG
        CP      (HL)
US9:    POP     BC
        POP     HL
        RET

; SDTIPO: tarjeta A -> HCARD (1 = SDHC). Sin tarjeta queda en 0.
SDTIPO: LD      (DSKC),A
        LD      HL,0
        LD      (ARG),HL
        LD      (ARG+2),HL
        LD      C,40h+58
        CALL    SDCMD
        JR      NZ,SDT9
        CALL    SPIRX           ; OCR, byte alto: bit 6 = CCS
        PUSH    AF
        CALL    SPIRX
        CALL    SPIRX
        CALL    SPIRX
        POP     AF
        AND     40h
        JR      Z,SDT9
        LD      A,(DSKC)
        LD      HL,HCARD
        ADD     A,L
        LD      L,A
        JR      NC,SDT8
        INC     H
SDT8:   LD      (HL),1
SDT9:   JP      SDEND

SIOINI: DEFB    SIOAC,28h, SIOAC,10h, SIOAC,30h     ; reponer TX, estado y errores
        DEFB    SIOBC,28h, SIOBC,10h, SIOBC,30h
        DEFB    SIOAC,5, SIOAC,0EAh                 ; RTS activo
        DEFB    SIOBC,5, SIOBC,0EAh
        DEFB    SIOBC,2, SIOBC,0E0h                 ; vector base E0h
        DEFB    SIOBC,1, SIOBC,1Ch                  ; B: RX por int., estado afecta al vector
        DEFB    SIOAC,1, SIOAC,18h                  ; A: RX por int.
SIOINN  EQU     ($-SIOINI)/2

VECS:   DEFW    ITXB,IEXB,IRXB,ISPB,ITXA,IEXA,IRXA,ISPA    ; FFE0-FFEE
        DEFW    INULL,ITICK,INULL,INULL                    ; FFF0-FFF6 (CTC 0-3)

MSG:    DEFB    13,10,'Z80-Retro XIOS 1.2 (OLIVEROS 2026): 2 consolas, 7 bancos, SD y flash',13,10,0
MSGC:   DEFB    ' KB de cache de disco',13,10,0

SIOPUT: PUSH    AF
SIOP1:  IN      A,(SIOAC)
        AND     4
        JR      Z,SIOP1
        POP     AF
        OUT     (SIOAD),A
        RET


; =============================================================== memoria comun
COMMONBASE:
        JP      COLDST
SWTUSER: JP     0
SWTSYS: JP      0
PDISP:  JP      0
XDOS:   JP      0
SYSDAT: DEFW    0

COLDST:
WARMSTART:
        LD      C,0
        JP      XDOS

NADA:   XOR     A
        RET

; DPB en la memoria comun: los programas los leen con la funcion 31 del BDOS
DPBSD:  DEFW    512             ; SPT: 512 registros (64 KB) por pista
        DEFB    4,15,0          ; BSH, BLM, EXM: bloques de 2 KB
        DEFW    2015            ; DSM (4 MB menos la primera pista)
        DEFW    511             ; DRM
        DEFB    0FFh,0          ; AL0, AL1
        DEFW    0               ; CKS: fija
        DEFW    1               ; OFF
DPBFL:  DEFW    512             ; disco en flash (ZIOS, paginas 03-1F)
        DEFB    4,15,1
        DEFW    0               ; DSM: SYSINIT pone el de ZIOS
        DEFW    127
        DEFB    0C0h,0
        DEFW    0
        DEFW    0

; ------------------------------------------------------------- consolas
; D = consola
CONST:  LD      A,D
        OR      A
        JR      NZ,CST1
CST0:   LD      A,(HDA)
        LD      HL,TLA
        CP      (HL)
        JR      CSTR
CST1:   LD      A,(HDB)
        LD      HL,TLB
        CP      (HL)
CSTR:   LD      A,0
        RET     Z
        DEC     A
        RET

CONIN:  LD      A,D
        OR      A
        JR      NZ,CIN1
        CALL    CST0
        OR      A
        JR      NZ,CIN0B
        LD      C,POLL
        LD      E,1             ; consola 0, entrada
        CALL    XDOS
CIN0B:  LD      HL,HDA
        LD      DE,RXA
        JR      CINGET
CIN1:   CALL    CST1
        OR      A
        JR      NZ,CIN1B
        LD      C,POLL
        LD      E,3
        CALL    XDOS
CIN1B:  LD      HL,HDB
        LD      DE,RXB
CINGET: LD      A,(HL)          ; HL = cabeza (lectura)
        PUSH    AF
        INC     A
        AND     7Fh
        LD      (HL),A
        POP     AF
        ADD     A,E
        LD      E,A
        LD      A,(DE)
        AND     7Fh
        RET

COST0:  IN      A,(SIOAC)       ; listo para transmitir: A = FF
        JR      COSTR
COST1:  IN      A,(SIOBC)
COSTR:  AND     4
        RET     Z
        LD      A,0FFh
        RET

CONOUT: LD      A,D
        OR      A
        JR      NZ,COUT1
COUT0:  CALL    COST0
        OR      A
        JR      NZ,COUT0B
        PUSH    BC
        LD      C,POLL
        LD      E,0
        CALL    XDOS
        POP     BC
COUT0B: LD      A,C
        OUT     (SIOAD),A
        RET
COUT1:  CALL    COST1
        OR      A
        JR      NZ,COUT1B
        PUSH    BC
        LD      C,POLL
        LD      E,2
        CALL    XDOS
        POP     BC
COUT1B: LD      A,C
        OUT     (SIOBD),A
        RET

LIST:   RET                     ; sin impresora

POLLDEV: LD     A,C
        CP      4
        JP      NC,NADA
        OR      A
        JP      Z,COST0
        DEC     A
        JP      Z,CST0
        DEC     A
        JP      Z,COST1
        JP      CST1

MAXCON: LD      A,NMBCNS
        RET

; ------------------------------------------------------------- reloj
STCLK:  LD      A,0FFh
        LD      (TICKN),A
        RET
SPCLK:  XOR     A
        LD      (TICKN),A
        RET
EXITRG: LD      A,(PREEMP)
        OR      A
        RET     NZ
        EI
        RET
IDLE:   EI
        HALT
        RET

; ------------------------------------------------------------- interrupciones
; Recepcion de la SIO: al bufer circular (si se llena se pierde el caracter)
IRXA:   PUSH    AF
        PUSH    HL
        LD      HL,TLA
        IN      A,(SIOAD)
        PUSH    DE
        LD      DE,RXA
IRXPUT: PUSH    AF
        LD      A,(HL)
        ADD     A,E
        LD      E,A
        POP     AF
        LD      (DE),A
        LD      A,(HL)
        INC     A
        AND     7Fh
        DEC     HL              ; HL = cabeza
        CP      (HL)
        INC     HL
        JR      Z,IRX9          ; lleno
        LD      (HL),A
IRX9:   POP     DE
        POP     HL
        POP     AF
        EI
        RETI
IRXB:   PUSH    AF
        PUSH    HL
        LD      HL,TLB
        IN      A,(SIOBD)
        PUSH    DE
        LD      DE,RXB
        JR      IRXPUT
; Recepcion especial (error): descartar y reponer
ISPA:   PUSH    AF
        IN      A,(SIOAD)
        LD      A,30h
        OUT     (SIOAC),A
        JR      IRET
ISPB:   PUSH    AF
        IN      A,(SIOBD)
        LD      A,30h
        OUT     (SIOBC),A
        JR      IRET
; Transmision y estado: solo reponer
ITXA:   PUSH    AF
        LD      A,28h
        OUT     (SIOAC),A
        JR      IRET
ITXB:   PUSH    AF
        LD      A,28h
        OUT     (SIOBC),A
        JR      IRET
IEXA:   PUSH    AF
        LD      A,10h
        OUT     (SIOAC),A
        JR      IRET
IEXB:   PUSH    AF
        LD      A,10h
        OUT     (SIOBC),A
IRET:   POP     AF
INULL:  EI
        RETI

; Tic del CTC (canal 1)
ITICK:  LD      (SVHL),HL
        POP     HL
        LD      (SVRET),HL
        PUSH    AF
        LD      HL,0
        ADD     HL,SP
        LD      (SVSP),HL
        LD      SP,ISTK
        PUSH    DE
        PUSH    BC
        LD      A,0FFh
        LD      (PREEMP),A
        LD      HL,TDIV         ; 120 Hz -> 60 Hz
        DEC     (HL)
        JR      NZ,ITDONE
        LD      A,(TDIVN)
        LD      (HL),A
        LD      A,(TICKN)
        OR      A
        JR      Z,IT1
        LD      C,FLAGSET       ; bandera 1: cada tic
        LD      E,1
        CALL    XDOS
IT1:    LD      HL,CNTSEC
        DEC     (HL)
        JR      NZ,ITDONE
        LD      (HL),TPS
        LD      C,FLAGSET       ; bandera 2: cada segundo
        LD      E,2
        CALL    XDOS
        LD      HL,CNTMIN
        DEC     (HL)
        JR      NZ,ITDONE
        LD      (HL),60
        LD      C,FLAGSET       ; bandera 4: cada minuto
        LD      E,4
        CALL    XDOS
ITDONE: XOR     A
        LD      (PREEMP),A
        POP     BC
        POP     DE
        LD      HL,(SVSP)
        LD      SP,HL
        POP     AF
        LD      HL,(SVRET)
        PUSH    HL
        LD      HL,(PDISP+1)    ; al despachador
        PUSH    HL
        LD      HL,(SVHL)
        RETI

; ------------------------------------------------------------- memoria
; SELMEM: BC = descriptor de memoria; el banco esta en (BC+3)
SELMEM: LD      HL,3
        ADD     HL,BC
        LD      A,(HL)
SELBNK: LD      L,A             ; banco A -> sus 3 paginas
        ADD     A,A
        ADD     A,L
        LD      HL,BNKPG
        ADD     A,L
        LD      L,A
        JR      NC,SB1
        INC     H
SB1:    LD      A,(HL)
        LD      (CURPG0),A
        OUT     (PGPORT),A
        INC     HL
        LD      A,(HL)
        OUT     (PGPORT+1),A
        INC     HL
        LD      A,(HL)
        OUT     (PGPORT+2),A
        RET

; ------------------------------------------------------------- discos
HOME:   LD      BC,0
SETTRK: LD      (TRK),BC
        RET
SETSEC: LD      (SEC),BC
        RET
SETDMA: LD      (DMA),BC
        RET
SECTRAN: LD     H,B
        LD      L,C
        RET
SELDSK: LD      HL,0
        LD      A,C
        CP      NDRV
        RET     NC
        LD      E,A
        LD      D,0
        LD      HL,DCARD
        ADD     HL,DE
        LD      A,(HL)
        CP      2               ; disco en RAM (o sin unidad): no
        LD      HL,0
        RET     Z
        CP      4
        RET     NC
        LD      A,C
        LD      (DRV),A
        LD      L,C             ; DPH = DPBASE + 16*unidad
        LD      H,0
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      DE,DPBASE
        ADD     HL,DE
        RET

; DSKADR: tarjeta en DSKC, bloque de 512 en BLK (32 bits), desplazamiento en OFS
DSKADR: LD      A,(DRV)
        LD      E,A
        LD      D,0
        LD      HL,DCARD
        ADD     HL,DE
        LD      A,(HL)
        LD      (DSKC),A
        LD      HL,(SEC)        ; registro = pista*512 + sector
        LD      A,(TRK)
        ADD     A,A
        ADD     A,H
        LD      H,A             ; HL = registro (15 bits)
        LD      A,L
        AND     3
        LD      (OFS),A         ; registro & 3: cuarto del bloque de 512
        LD      (RECN),HL
        SRL     H               ; bloque de 512 dentro de la unidad (13 bits)
        RR      L
        SRL     H
        RR      L
        EX      DE,HL           ; DE = bloque
        LD      A,(DRV)
        ADD     A,A
        LD      C,A
        LD      B,0
        LD      HL,DMW
        ADD     HL,BC
        LD      A,(HL)          ; DMW = disco virtual * 32
        OR      D
        LD      D,A
        INC     HL
        LD      L,(HL)
        LD      H,0             ; HLDE = numero de bloque en la tarjeta
        LD      (BLK),DE
        LD      (BLK+2),HL
        RET

; READ / WRITE: 0 = bien, 1 = error
READ:   CALL    DSKADR
        XOR     A               ; basta el registro de 128 bytes
        LD      (GMODE),A
        CALL    GETBLK
        RET     NZ
        CALL    SWTUSER
        CALL    BUFPTR
        LD      DE,(DMA)
        LD      BC,128
        LDIR
        CALL    SWTSYS
        XOR     A
        RET

WRITE:  CALL    DSKADR
        LD      A,(DSKC)
        CP      2
        JR      NC,ERR1         ; flash: solo lectura
        LD      A,1             ; hace falta el bloque entero (se reescribe)
        LD      (GMODE),A
        CALL    GETBLK
        RET     NZ
        CALL    SWTUSER
        CALL    BUFPTR
        EX      DE,HL
        LD      HL,(DMA)
        LD      BC,128
        LDIR
        CALL    SWTSYS
        CALL    SDWR
        JP      Z,CWRREC        ; escrito: el registro tambien a la cache
        CALL    CWRERR          ; fallo: olvidar el bloque (BUF ya no es la tarjeta)
ERR1:   LD      A,1
        OR      A
        RET

BUFPTR: LD      HL,BUF          ; HL = BUF + OFS*128
        LD      A,(OFS)
        RRCA
        LD      E,A
        AND     1
        LD      D,A
        LD      A,E
        AND     80h
        LD      E,A
        ADD     HL,DE
        RET

; FLREC: registro del disco en flash -> BUF+desplazamiento. Pagina 3 + reg/128.
FLREC:  LD      A,0FFh
        LD      (CCARD),A
        LD      HL,(RECN)
        LD      A,L
        RLA                     ; pagina = 3 + registro >> 7
        LD      A,H
        RLA
        ADD     A,3
        LD      B,A
        LD      A,L
        AND     7Fh             ; direccion = (registro & 7Fh) * 128
        LD      H,A
        LD      L,0
        SRL     H
        RR      L
        PUSH    HL
        CALL    BUFPTR
        EX      DE,HL           ; DE = destino en la comun
        POP     HL              ; HL = origen en la ventana 0
        LD      A,I             ; guardar IFF2
        DI
        PUSH    AF
        LD      A,B
        OUT     (PGPORT),A
        LD      BC,128
        LDIR
        LD      A,(CURPG0)
        OUT     (PGPORT),A
        POP     AF
        JP      PO,FLR1
        EI
FLR1:   XOR     A
        RET

; ------------------------------------------------------------- SD por SPI
; (los metodos de zlib/libspi.asm de Peter Wilson)
SPITX:  RLCA                    ; manda A, bit 7 primero (MOSI = bit 0)
        OUT     (SPIL),A
        OUT     (SPIH),A
        RLCA
        OUT     (SPIL),A
        OUT     (SPIH),A
        RLCA
        OUT     (SPIL),A
        OUT     (SPIH),A
        RLCA
        OUT     (SPIL),A
        OUT     (SPIH),A
        RLCA
        OUT     (SPIL),A
        OUT     (SPIH),A
        RLCA
        OUT     (SPIL),A
        OUT     (SPIH),A
        RLCA
        OUT     (SPIL),A
        OUT     (SPIH),A
        RLCA
        OUT     (SPIL),A
        OUT     (SPIH),A
        RET
SPIRX:  PUSH    BC              ; recibe en A (manda unos)
        LD      B,8
SRX1:   LD      A,1
        OUT     (SPIL),A
        OUT     (SPIH),A
        IN      A,(SPIIN)
        RRA
        RL      C
        DJNZ    SRX1
        LD      A,C
        POP     BC
        RET

; SDSEL: CS de la tarjeta DSKC (0 o 1)
SDSEL:  XOR     A
        OUT     (SPIL),A
        LD      A,(DSKC)
        OR      A
        LD      A,05h
        JR      Z,SDS1
        LD      A,09h
SDS1:   OUT     (SPICS),A
        RET
SDEND:  XOR     A
        OUT     (SPIL),A
        LD      A,CSOFF
        OUT     (SPICS),A
        JP      SPIRX           ; un byte de reloj con CS arriba

; SDCMD: comando C con el argumento en BLK (ajustado a SDSC). A = R1, Z si 0.
SDCMD:  CALL    SDSEL
        LD      DE,0
SDC1:   CALL    SPIRX           ; esperar a que no este ocupada
        INC     A
        JR      Z,SDC2
        DEC     DE
        LD      A,D
        OR      E
        JR      NZ,SDC1
        DEC     A
        RET                     ; A = FF, NZ
SDC2:   LD      A,C
        CALL    SPITX
        LD      HL,ARG+3
        LD      B,4
SDC3:   LD      A,(HL)
        CALL    SPITX
        DEC     HL
        DJNZ    SDC3
        LD      A,0FFh          ; CRC (no se usa salvo CMD0/8)
        CALL    SPITX
        LD      B,16
SDC4:   CALL    SPIRX
        CP      0FFh
        JR      NZ,SDC5
        DJNZ    SDC4
SDC5:   OR      A
        RET

; SDARG: ARG = BLK (SDHC) o BLK*512 (SDSC)
SDARG:  LD      HL,(BLK)
        LD      DE,(BLK+2)
        LD      A,(DSKC)
        PUSH    HL
        LD      HL,HCARD
        ADD     A,L
        LD      L,A
        JR      NC,SDA0
        INC     H
SDA0:   LD      A,(HL)
        POP     HL
        OR      A
        JR      NZ,SDA1
        LD      D,E             ; *256
        LD      E,H
        LD      H,L
        LD      L,0
        SLA     H               ; *2
        RL      E
        RL      D
SDA1:   LD      (ARG),HL
        LD      (ARG+2),DE
        RET

SDRD:   CALL    SDARG
        LD      C,40h+17
        CALL    SDCMD
        JR      NZ,SDERR
        LD      DE,0
SDR1:   CALL    SPIRX           ; token de datos FE
        CP      0FEh
        JR      Z,SDR2
        CP      0FFh
        JR      NZ,SDERR
        DEC     DE
        LD      A,D
        OR      E
        JR      NZ,SDR1
        JR      SDERR
SDR2:   LD      HL,BUF
        LD      DE,512
SDR3:   CALL    SPIRX
        LD      (HL),A
        INC     HL
        DEC     DE
        LD      A,D
        OR      E
        JR      NZ,SDR3
        CALL    SPIRX           ; CRC
        CALL    SPIRX
        CALL    SDEND
        XOR     A
        RET
SDERR:  CALL    SDEND
        LD      A,1
        OR      A
        RET

SDWR:   CALL    SDARG
        LD      C,40h+24
        CALL    SDCMD
        JR      NZ,SDERR
        CALL    SPIRX
        LD      A,0FEh
        CALL    SPITX
        LD      HL,BUF
        LD      DE,512
SDW1:   LD      A,(HL)
        CALL    SPITX
        INC     HL
        DEC     DE
        LD      A,D
        OR      E
        JR      NZ,SDW1
        LD      A,0FFh          ; CRC
        CALL    SPITX
        CALL    SPITX
        CALL    SPIRX           ; respuesta xxx00101
        AND     1Fh
        CP      5
        JR      NZ,SDERR
        LD      DE,0
SDW2:   CALL    SPIRX           ; esperar fin de escritura
        INC     A
        JR      Z,SDW3
        DEC     DE
        LD      A,D
        OR      E
        JR      NZ,SDW2
        JR      SDERR
SDW3:   CALL    SDEND
        XOR     A
        RET

; PGQRY: paginas del banco 0 preguntandole a ZIOS (servicio 1). Va en la memoria
; comun porque la ventana que se pregunta cambia un momento.
PGQRY:
        LD      HL,BNKPG
        LD      B,0
SI1:    PUSH    BC
        PUSH    HL
        LD      E,B
        LD      D,3Fh
        LD      C,1
        CALL    ZIOS            ; A = pagina que habia
        POP     HL
        POP     BC
        LD      (HL),A
        PUSH    BC
        PUSH    HL
        LD      E,B
        LD      D,A
        LD      C,1
        CALL    ZIOS            ; volver a ponerla
        POP     HL
        POP     BC
        INC     HL
        INC     B
        LD      A,B
        CP      3
        JR      NZ,SI1
        RET

; ------------------------------------------------------------- datos (comun)
TICKN:  DEFB    0
PREEMP: DEFB    0
TDIV:   DEFB    2
TDIVN:  DEFB    2
CNTSEC: DEFB    TPS
CNTMIN: DEFB    60
SVHL:   DEFW    0
SVRET:  DEFW    0
SVSP:   DEFW    0
HDA:    DEFB    0               ; cabeza (lectura) y cola (escritura) de RXA
TLA:    DEFB    0
HDB:    DEFB    0
TLB:    DEFB    0
CURPG0: DEFB    0
CMNPG:  DEFB    0
BNKPG:  DEFS    24              ; 3 paginas por banco, bancos 0-7
DRV:    DEFB    0
TRK:    DEFW    0
SEC:    DEFW    0
DMA:    DEFW    0
DSKC:   DEFB    0
OFS:    DEFB    0
RECN:   DEFW    0
BLK:    DEFS    4
ARG:    DEFS    4
CCARD:  DEFB    0FFh
CBLK:   DEFS    4
HCARD:  DEFB    0,0
DCARD:  DEFS    NDRV
DMW:    DEFS    2*NDRV
JTBL:   DEFW    0
DBGE:   DEFW    0
DBGR:   DEFB    0
FIRMA:  DEFB    0
ZMAP:   DEFS    64
        DEFS    48
LSTK:
DIRBF:  DEFS    128             ; en la comun: READ copia con el banco del usuario puesto
BUF:    DEFS    512
        DEFB    0               ; para que el SPR incluya el bufer
        END
