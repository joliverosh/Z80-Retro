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
NDRV    EQU     16              ; unidades A-P
NBNK    EQU     5               ; bancos de usuario (GENSYS: user memory segments)
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
        JP      COST1           ; LISTST: SIO B lista para transmitir
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
        DEFW    0,0,0,0,DIRBF,DPBSD,CSV,ALV8
        DEFW    0,0,0,0,DIRBF,DPBSD,CSV,ALV9
        DEFW    0,0,0,0,DIRBF,DPBSD,CSV,ALV10
        DEFW    0,0,0,0,DIRBF,DPBSD,CSV,ALV11
        DEFW    0,0,0,0,DIRBF,DPBSD,CSV,ALV12
        DEFW    0,0,0,0,DIRBF,DPBSD,CSV,ALV13
        DEFW    0,0,0,0,DIRBF,DPBSD,CSV,ALV14
        DEFW    0,0,0,0,DIRBF,DPBSD,CSV,ALV15
CSV:    DEFS    4
ALV0:   DEFS    253
ALV1:   DEFS    253
ALV2:   DEFS    253
ALV3:   DEFS    253
ALV4:   DEFS    253
ALV5:   DEFS    253
ALV6:   DEFS    253
ALV7:   DEFS    253
ALV8:   DEFS    253
ALV9:   DEFS    253
ALV10:  DEFS    253
ALV11:  DEFS    253
ALV12:  DEFS    253
ALV13:  DEFS    253
ALV14:  DEFS    253
ALV15:  DEFS    253

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
        CALL    TODBAS          ;          y la referencia para notar cambios de hora
        CALL    STFIND          ; ---- 1c. hay A:STARTUP.SUB?
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
        LD      B,NBNK*3
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
        CALL    RINIT           ; y las que quedan, el disco en RAM (G:)
        ; pagina cero de cada banco: JP a la tabla de saltos, el RST del
        ; depurador y un RET en 30h (los programas de la Z80-Retro llaman a ZIOS)
        LD      B,NBNK
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
        LD      A,0C3h          ; RST 30h -> servicios de ZIOS imitados
        LD      (30h),A
        LD      HL,ZEMU
        LD      (31h),HL
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
SI15:   LD      A,(NCPG)        ; "nn KB de cache de disco"
        LD      HL,MSGC
        CALL    PRKB
        LD      A,(NRPG)        ; "G: disco en RAM de nnn KB"
        OR      A
        JR      Z,SI15C
        LD      HL,MSGG
        CALL    PRSTR
        LD      A,(NRPG)
        LD      HL,MSGK
        CALL    PRKB
SI15C:  LD      A,(STOK)        ; "A:STARTUP.SUB"
        OR      A
        LD      HL,MSGS
        CALL    NZ,PRSTR
SI15E:  LD      SP,(SVSP)
        EI
        RET

; PRKB: si A (paginas) no es 0, escribe A*16 en decimal y luego el texto HL
PRKB:   OR      A
        RET     Z
        PUSH    HL
        LD      L,A
        LD      H,0
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      DE,100
        CALL    PRDIG
        LD      DE,10
        CALL    PRDIG
        LD      A,L
        ADD     A,'0'
        CALL    SIOPUT
        POP     HL
; PRSTR: escribe el texto HL (termina en 0) por la consola 0
PRSTR:  LD      A,(HL)
        OR      A
        RET     Z
        CALL    SIOPUT
        INC     HL
        JR      PRSTR
; PRDIG: digito de HL / DE (sin ceros a la izquierda: B = ya hubo digito)
PRDIG:  LD      A,'0'-1
PRD1:   INC     A
        OR      A
        SBC     HL,DE
        JR      NC,PRD1
        ADD     HL,DE
        CP      '0'
        JR      NZ,PRD2
        LD      C,A
        LD      A,E
        CP      100
        LD      A,C
        RET     Z               ; cero de las centenas: no se escribe
PRD2:   JP      SIOPUT

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

; GETBLK: deja el bloque en BUF (Z = bien). Flash: lee el registro de 128 bytes.
GETBLK: LD      A,(DSKC)
        CP      3
        JP      Z,FLREC
        CP      2
        JP      Z,RAMRD
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

; ------------------------------------------------------------- SD (en la parte con bancos:
; se usa solo con el banco 0 puesto)
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


; ------------------------------------------------------------- hora -> DS1307
; Cuando alguien cambia la hora de MP/M (TOD, SETTOD, funcion 104), se graba en
; el DS1307. MP/M no avisa al XIOS, asi que se compara: la hora de XDOS debe ser
; la de referencia mas los segundos contados por el tic (SECS). Si se aparta mas
; de 3 s, la cambiaron. Se mira una vez por segundo, en READ/WRITE: corre con el
; banco 0 puesto y con el disco reservado (MXDisk), asi que el I2C no se cruza
; con la SD en el puerto 64h.

TODCHK: LD      HL,(SECS)
        LD      DE,(LASTS)
        OR      A
        SBC     HL,DE
        RET     Z               ; ya se miro en este segundo
        ADD     HL,DE
        LD      (LASTS),HL
        CALL    TODNOW          ; ACC = segundos de la hora de XDOS
        LD      HL,(SECS)       ; esperado = BASE + (SECS - BSECS)
        LD      DE,(BSECS)
        OR      A
        SBC     HL,DE
        LD      DE,(BASE)
        ADD     HL,DE
        EX      DE,HL           ; DE = parte baja esperada
        LD      HL,(BASE+2)
        LD      BC,0
        ADC     HL,BC           ; HL = parte alta esperada
        LD      B,H
        LD      C,L
        LD      HL,(ACC)        ; diferencia = ahora - esperado
        OR      A
        SBC     HL,DE
        EX      DE,HL
        LD      HL,(ACC+2)
        SBC     HL,BC           ; HLDE = diferencia (32 bits)
        LD      A,H             ; pequena si HL = 0000 y DE < 4, o HL = FFFF y DE > FFFC
        AND     L
        INC     A
        JR      NZ,TC2
        LD      A,D             ; HL = FFFF: negativa; pequena si DE >= FFFD
        INC     A
        JR      NZ,TC9
        LD      A,E
        CP      0FDh
        RET     NC              ; -3..-1
        JR      TC9
TC2:    LD      A,H
        OR      L
        JR      NZ,TC9
        LD      A,D
        OR      A
        JR      NZ,TC9
        LD      A,E
        CP      4
        RET     C               ; 0..3
TC9:    CALL    RTCSET          ; la cambiaron: grabar el DS1307
TODBAS: CALL    TODNOW          ; nueva referencia
        LD      HL,(ACC)
        LD      (BASE),HL
        LD      HL,(ACC+2)
        LD      (BASE+2),HL
        LD      HL,(SECS)
        LD      (BSECS),HL
        LD      (LASTS),HL
        RET

; TODNOW: ACC = ((dia * 24 + hora) * 60 + minuto) * 60 + segundo
TODNOW: CALL    TODADR
        PUSH    HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        LD      (ACC),DE
        LD      HL,0
        LD      (ACC+2),HL
        POP     HL
        INC     HL
        INC     HL
        LD      B,3             ; hora, minuto, segundo
        LD      C,24
TN1:    PUSH    HL
        PUSH    BC
        LD      A,C
        CALL    MUL32           ; ACC = ACC * A
        POP     BC
        POP     HL
        LD      A,(HL)
        CALL    BCDBIN
        CALL    ADD32A          ; ACC = ACC + A
        INC     HL
        LD      C,60
        DJNZ    TN1
        RET

; MUL32: ACC = ACC * A (A de 8 bits)
MUL32:  LD      DE,(ACC)
        LD      (X32),DE
        LD      DE,(ACC+2)
        LD      (X32+2),DE
        LD      HL,0
        LD      (ACC),HL
        LD      (ACC+2),HL
        LD      B,8
M32A:   PUSH    AF
        LD      HL,ACC          ; ACC = ACC * 2
        SLA     (HL)
        INC     HL
        RL      (HL)
        INC     HL
        RL      (HL)
        INC     HL
        RL      (HL)
        POP     AF
        RLA
        JR      NC,M32B
        PUSH    AF
        LD      HL,(ACC)        ; ACC = ACC + X
        LD      DE,(X32)
        ADD     HL,DE
        LD      (ACC),HL
        LD      HL,(ACC+2)
        LD      DE,(X32+2)
        ADC     HL,DE
        LD      (ACC+2),HL
        POP     AF
M32B:   DJNZ    M32A
        RET

; ADD32A: ACC = ACC + A
ADD32A: PUSH    HL
        LD      HL,(ACC)
        LD      E,A
        LD      D,0
        ADD     HL,DE
        LD      (ACC),HL
        LD      HL,(ACC+2)
        LD      DE,0
        ADC     HL,DE
        LD      (ACC+2),HL
        POP     HL
        RET

; RTCSET: la hora de XDOS al DS1307 (seg, min, hora, dia de la semana, dia,
; mes, anio). El dia 1 de MP/M es el domingo 1/1/1978.
RTCSET: CALL    TODADR
        LD      E,(HL)
        INC     HL
        LD      D,(HL)          ; DE = dia (1 = 1/1/1978)
        INC     HL
        LD      A,(HL)
        LD      (RTB+2),A       ; hora (BCD, 24 h)
        INC     HL
        LD      A,(HL)
        LD      (RTB+1),A       ; minuto
        INC     HL
        LD      A,(HL)
        AND     7Fh             ; bit 7 = 0: el reloj anda
        LD      (RTB+0),A       ; segundo
        EX      DE,HL
        CALL    DAY2YMD         ; dia -> dia de la semana, dia, mes, anio (BCD)
        LD      HL,DDOW
        LD      DE,RTB+3
        LD      BC,4
        LDIR
        ; I2C: START, D0, registro 0, los 7 bytes, STOP
        LD      A,3
        LD      (IVAL),A
        OUT     (SPICS+1),A
        CALL    ISTART
        LD      A,0D0h
        CALL    IWBY
        OR      A
        JR      NZ,RS9          ; no responde
        XOR     A
        CALL    IWBY
        LD      HL,RTB
        LD      B,7
RSW:    LD      A,(HL)
        CALL    IWBY
        INC     HL
        DJNZ    RSW
RS9:    JP      ISTOP

; I2C por software en 64h/65h (de rtc.asm, rutinas de zlib/libi2c.asm de Peter
; Wilson, MIT). Bit 1 = SDA; escribir en 65h sube SCL. El bit 0 (RRW) queda en 1.
IDLY:   PUSH    BC
        LD      B,3
IDL1:   DJNZ    IDL1
        POP     BC
        RET
ISTART: LD      A,1
        CALL    ICLK
        LD      A,1
        CALL    IDAT
        CALL    IDLY
        XOR     A
        CALL    IDAT
        CALL    IDLY
        XOR     A
        CALL    ICLK
        JP      IDLY
ISTOP:  XOR     A
        CALL    IDAT
        CALL    IDLY
        LD      A,1
        CALL    ICLK
        CALL    IDLY
        LD      A,1
        CALL    IDAT
        CALL    IDLY
        XOR     A
        CALL    ICLK
        JP      IDLY
IWBI:   CALL    IDAT
        CALL    IDLY
        LD      A,1
        CALL    ICLK
        CALL    IDLY
        XOR     A
        CALL    ICLK
        JP      IDLY
IWBY:   PUSH    BC              ; manda A; devuelve el bit ACK (0 = reconocido)
        LD      B,8
        LD      C,A
IW1:    RLC     C
        LD      A,C
        CALL    IWBI
        DJNZ    IW1
        CALL    IRBI
        POP     BC
        RET
IRBI:   LD      A,1
        CALL    IDAT
        CALL    IDLY
        LD      A,1
        CALL    ICLK
        CALL    IDLY
        IN      A,(SPICS)
        AND     2
        PUSH    AF
        XOR     A
        CALL    ICLK
        CALL    IDLY
        POP     AF
        SRA     A
        RET
IDAT:   PUSH    BC
        AND     1
        LD      A,(ICLKP)
        LD      C,A
        LD      A,(IVAL)
        JR      Z,ID1
        OR      2
        JR      ID2
ID1:    AND     0FDh
ID2:    LD      (IVAL),A
        OUT     (C),A
        POP     BC
        RET
ICLK:   PUSH    BC
        RRCA
        LD      A,SPICS
        ADC     A,0
        LD      (ICLKP),A
        LD      C,A
        LD      A,(IVAL)
        OUT     (C),A
        POP     BC
        RET

ACC:    DEFS    4
X32:    DEFS    4
BASE:   DEFS    4               ; segundos de la hora de referencia
BSECS:  DEFW    0               ; SECS cuando se tomo la referencia
LASTS:  DEFW    0
IVAL:   DEFB    3
ICLKP:  DEFB    SPICS

; ------------------------------------------------------------- disco en RAM
; G: (la unidad que ZIOS tenia como disco en RAM) en las paginas libres que no
; tomo la cache. Una pagina por pista, 128 registros por pagina. Se formatea en
; cada arranque: lo que tenia ZIOS en su disco en RAM se pierde igual (sus
; paginas son ahora los bancos de MP/M).

; RAMADR: HL = registro TRK/SEC en la ventana 0, CPAGE = su pagina; OFS = SEC & 3
RAMADR: LD      A,(SEC)
        AND     3
        LD      (OFS),A
        LD      HL,RAMPG
        LD      A,(TRK)
        ADD     A,L
        LD      L,A
        JR      NC,RA1
        INC     H
RA1:    LD      A,(HL)
        LD      (CPAGE),A
        LD      A,(SEC)         ; direccion = SEC * 128
        AND     7Fh
        LD      H,A
        LD      L,0
        SRL     H
        RR      L
        RET

; RAMRD: registro del disco en RAM -> BUF (en el sitio de BUFPTR)
RAMRD:  CALL    RAMADR
        LD      A,0FFh          ; BUF ya no tiene un bloque de la SD
        LD      (CCARD),A
        LD      (BUFSL),A
        PUSH    HL
        CALL    BUFPTR
        EX      DE,HL
        POP     HL
        LD      BC,128
        CALL    CPYC
        XOR     A
        RET

; RAMWR: BUF (sitio de BUFPTR) -> registro del disco en RAM. A = 0.
RAMWR:  CALL    RAMADR
        PUSH    HL
        CALL    BUFPTR
        POP     DE
        LD      BC,128
        CALL    CPYC
        XOR     A
        RET

; RINIT: las paginas que quedan libres (despues de la cache) para el disco en
; RAM, su DPB, el DPH de la unidad y el directorio vacio (E5).
RINIT:  LD      HL,RAMPG
        LD      B,0
        LD      C,3Fh
RI1:    LD      A,C
        CALL    USADA
        JR      Z,RI2
        CALL    ESCACHE
        JR      Z,RI2
        LD      (HL),C
        INC     HL
        INC     B
        LD      A,B
        CP      16
        JR      Z,RI3
RI2:    DEC     C
        LD      A,C
        CP      1Fh
        JR      NZ,RI1
RI3:    LD      A,B
        LD      (NRPG),A
        OR      A
        RET     Z
        ADD     A,A             ; DSM = paginas * 16 - 1
        ADD     A,A
        ADD     A,A
        ADD     A,A
        DEC     A
        LD      (DPBRM+5),A
        XOR     A
        LD      (DPBRM+6),A
        LD      HL,DCARD        ; las unidades con tarjeta 2 usan DPBRM
        LD      B,0
RI4:    LD      A,(HL)
        CP      2
        JR      NZ,RI5
        PUSH    HL
        LD      A,B
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,A
        LD      E,A
        LD      D,0
        LD      HL,DPBASE+10
        ADD     HL,DE
        LD      DE,DPBRM
        LD      (HL),E
        INC     HL
        LD      (HL),D
        POP     HL
RI5:    INC     HL
        INC     B
        LD      A,B
        CP      NDRV
        JR      NZ,RI4
        LD      A,(RAMPG)       ; directorio (2 KB al principio) en E5
        LD      (CPAGE),A
        LD      HL,0
        LD      B,32            ; 32 trozos de 64
RI6:    PUSH    BC
        LD      A,I
        DI
        PUSH    AF
        LD      A,(CPAGE)
        OUT     (PGPORT),A
        LD      B,64
RI7:    LD      (HL),0E5h
        INC     HL
        DJNZ    RI7
        LD      A,(CURPG0)
        OUT     (PGPORT),A
        POP     AF
        JP      PO,RI8
        EI
RI8:    POP     BC
        DJNZ    RI6
        RET

; ESCACHE: Z si la pagina C es de la cache
ESCACHE: PUSH   HL
        PUSH    BC
        LD      HL,CPG
        LD      B,4
EC1:    LD      A,(HL)
        CP      C
        JR      Z,EC9
        INC     HL
        DJNZ    EC1
        OR      1               ; NZ
EC9:    POP     BC
        POP     HL
        RET

NRPG:   DEFB    0               ; paginas del disco en RAM (0 = no hay)
RAMPG:  DEFS    16

; ------------------------------------------------------------- historial de ordenes
; Solo para el TMP (el indicador nA>): ^W recupera la orden anterior; cada ^W
; seguido va una mas atras (hasta 8 por consola). Funciona dentro de la
; lectura de linea del BDOS: el XIOS devuelve ^X (borra la linea) y despues los
; caracteres de la orden guardada, como si se escribieran. Los programas no lo
; ven: para ellos ^W sigue siendo ^W.
HLEN    EQU     80              ; caracteres por linea
HNUM    EQU     8               ; lineas por consola

; HCON: IX = estado de la consola D
HCON:   LD      IX,HST0
        LD      A,D
        OR      A
        RET     Z
        LD      IX,HST1
        RET
; estado por consola (desplazamientos en IX):
;  0 largo de la linea actual   1 reproduciendo: caracteres que faltan
;  2 indice de reproduccion     3 linea que se reproduce
;  4 lineas guardadas           5 la mas nueva   6 profundidad del ultimo ^W
;  7.. linea actual (HLEN)      7+HLEN.. HNUM lineas de (1 largo + HLEN)
HSZ     EQU     7+HLEN+HNUM*(HLEN+1)

TCONST: PUSH    IX               ; (SUBMIT STARTUP no se anuncia: el TMP vacia lo tecleado antes)
        CALL    HCON
        LD      A,(IX+1)
        POP     IX
        OR      A
        JP      Z,CONSTR
        LD      A,0FFh
        RET

TCONIN: CALL    STPEND          ; la primera orden de la consola 0 al arrancar
        JR      Z,TCIN0         ; con A:STARTUP.SUB es SUBMIT STARTUP
        LD      HL,(STPTR)
        LD      A,(HL)
        INC     HL
        LD      (STPTR),HL
        RET
TCIN0:  PUSH    IX
        CALL    HCON
        LD      A,(IX+1)        ; reproduciendo una orden guardada?
        OR      A
        JR      Z,TCI1
        DEC     (IX+1)
        LD      A,(IX+3)        ; caracter = linea guardada [indice]
        CALL    HLINE
        INC     HL              ; saltar el largo
        LD      A,(IX+2)
        INC     (IX+2)
        LD      E,A
        LD      D,0
        ADD     HL,DE
        LD      A,(HL)
        LD      C,A
        CALL    HADD            ; tambien pasa a la linea actual
        LD      A,C
        POP     IX
        RET
TCI1:   PUSH    DE
        CALL    CONINR          ; el caracter de verdad
        POP     DE
        LD      C,A
        CP      17h             ; ^W
        JR      Z,TCIW
        LD      (IX+6),0        ; cualquier otra tecla: el proximo ^W empieza de nuevo
        CP      0Dh
        JR      Z,TCICR
        CP      0Ah
        JR      Z,TCICR
        CP      08h
        JR      Z,TCIBS
        CP      7Fh
        JR      Z,TCIBS
        CP      18h             ; ^X
        JR      Z,TCICL
        CP      15h             ; ^U
        JR      Z,TCICL
        CP      20h
        CALL    NC,HADD
TCIR:   LD      A,C
        POP     IX
        RET
TCIBS:  LD      A,(IX+0)
        OR      A
        JR      Z,TCIR
        DEC     (IX+0)
        JR      TCIR
TCICL:  LD      (IX+0),0
        JR      TCIR
TCICR:  PUSH    BC
        CALL    HSAVE
        POP     BC
        LD      (IX+0),0
        JR      TCIR
TCIW:   LD      A,(IX+4)        ; hay lineas guardadas?
        OR      A
        JR      Z,TCIR          ; no: ^W pasa tal cual
        LD      A,(IX+6)        ; profundidad: 1 = la mas nueva
        CP      (IX+4)
        JR      NC,TCW1
        INC     A
TCW1:   LD      (IX+6),A
        LD      B,A             ; linea = mas nueva - (profundidad - 1), modulo HNUM
        LD      A,(IX+5)
        INC     A
        SUB     B
        JR      NC,TCW2
        ADD     A,HNUM
TCW2:   LD      (IX+3),A
        CALL    HLINE
        LD      A,(HL)
        LD      (IX+1),A        ; caracteres que faltan
        LD      (IX+2),0
        LD      (IX+0),0        ; la linea actual se borra (^X)
        LD      C,18h
        JR      TCIR

; HADD: agrega C a la linea actual (si cabe y es imprimible)
HADD:   LD      A,C
        CP      20h
        RET     C
        CP      7Fh
        RET     NC
        LD      A,(IX+0)
        CP      HLEN
        RET     NC
        INC     (IX+0)
        PUSH    IX
        POP     HL
        LD      DE,7
        ADD     HL,DE
        LD      E,A
        ADD     HL,DE
        LD      (HL),C
        RET

; HSAVE: la linea actual pasa al historial (si no esta vacia ni repite la ultima)
HSAVE:  LD      A,(IX+0)
        OR      A
        RET     Z
        LD      A,(IX+4)        ; igual a la mas nueva? no se repite
        OR      A
        JR      Z,HS2
        LD      A,(IX+5)
        CALL    HLINE
        LD      A,(HL)
        CP      (IX+0)
        JR      NZ,HS2
        LD      B,A
        INC     HL
        PUSH    IX
        POP     DE
        PUSH    HL
        LD      HL,7
        ADD     HL,DE
        EX      DE,HL
        POP     HL
HS1:    LD      A,(DE)
        CP      (HL)
        JR      NZ,HS2
        INC     HL
        INC     DE
        DJNZ    HS1
        RET                     ; repetida
HS2:    LD      A,(IX+5)        ; la siguiente posicion del anillo
        INC     A
        CP      HNUM
        JR      C,HS3
        XOR     A
HS3:    LD      (IX+5),A
        CALL    HLINE
        LD      A,(IX+0)
        LD      (HL),A
        INC     HL
        EX      DE,HL
        PUSH    IX
        POP     HL
        LD      BC,7
        ADD     HL,BC
        LD      C,A
        LD      B,0
        LDIR
        LD      A,(IX+4)
        CP      HNUM
        RET     NC
        INC     (IX+4)
        RET

; HLINE: HL = linea A del historial de la consola IX
HLINE:  PUSH    DE
        LD      E,A
        LD      D,0
        LD      HL,0
        LD      B,HLEN+1
HL1:    ADD     HL,DE
        DJNZ    HL1
        PUSH    IX
        POP     DE
        ADD     HL,DE
        LD      DE,7+HLEN
        ADD     HL,DE
        POP     DE
        RET

HST0:   DEFS    HSZ
HST1:   DEFS    HSZ

; ------------------------------------------------------------- STARTUP.SUB
; STFIND: busca STARTUP.SUB en el usuario 0 de A: leyendo el directorio con
; ZIOS (todavia esta debajo). Si esta, SYSINIT deja "SUBMIT STARTUP" escrito en
; la consola 0, como si se hubiera tecleado: se ejecuta al aparecer 0A>.
STFIND: XOR     A
        LD      (STOK),A
        LD      (STREC),A
        LD      HL,STBUF        ; DMA de ZIOS
        LD      C,12
        CALL    ZIOS
STF1:   LD      A,(STREC)       ; pista 1 (despues del sistema), registro STREC
        LD      E,A
        LD      D,02h
        LD      HL,0            ; unidad 0 (A:)
        LD      C,17
        CALL    ZIOS
        OR      A
        RET     NZ              ; error de lectura: nada
        LD      HL,STBUF
        LD      B,4             ; 4 entradas por registro
STF2:   PUSH    BC
        PUSH    HL
        LD      A,(HL)          ; usuario 0
        OR      A
        JR      NZ,STF4
        INC     HL
        LD      DE,STNAME
        LD      B,11
STF3:   LD      A,(HL)
        AND     7Fh
        EX      DE,HL
        CP      (HL)
        EX      DE,HL
        JR      NZ,STF4
        INC     HL
        INC     DE
        DJNZ    STF3
        POP     HL
        POP     BC
        LD      A,1
        LD      (STOK),A
        RET
STF4:   POP     HL
        LD      DE,32
        ADD     HL,DE
        POP     BC
        DJNZ    STF2
        LD      A,(STREC)       ; siguiente registro (128 en el directorio)
        INC     A
        LD      (STREC),A
        CP      128
        JR      NZ,STF1
        RET
STNAME: DEFB    'STARTUP SUB'
STREC:  DEFB    0
STCMD:  DEFB    'H:SUBMIT A:STARTUP',13,0
STOK:   DEFB    0
STPTR:  DEFW    STCMD

; STPEND: NZ si a la consola D (0) le quedan caracteres de SUBMIT STARTUP
STPEND: LD      A,D
        OR      A
        JR      Z,STP0
        XOR     A               ; consola 1: nada (Z)
        RET
STP0:
        LD      A,(STOK)
        OR      A
        RET     Z
        LD      HL,(STPTR)
        LD      A,(HL)
        OR      A
        RET     NZ
        XOR     A               ; se acabo
        LD      (STOK),A
        RET
STBUF:  DEFS    128
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

MSG:    DEFB    13,10,'ZEPHYRUS XIOS 1.2 (OLIVEROS 2026): 2 consolas, 5 bancos, unidades A-P',13,10,0
MSGC:   DEFB    ' KB de cache de disco',13,10,0
MSGS:   DEFB    'A:STARTUP.SUB',13,10,0
MSGG:   DEFB    'G: disco en RAM de ',0
MSGK:   DEFB    ' KB',13,10,0

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
DPBRM:  DEFW    128             ; disco en RAM: una pagina de 16 KB por pista
        DEFB    3,7,0           ; bloques de 1 KB
        DEFW    0               ; DSM: SYSINIT (paginas * 16 - 1)
        DEFW    63              ; 64 entradas de directorio
        DEFB    0C0h,0
        DEFW    0
        DEFW    0
DPBFL:  DEFW    512             ; disco en flash (ZIOS, paginas 03-1F)
        DEFB    4,15,1
        DEFW    0               ; DSM: SYSINIT pone el de ZIOS
        DEFW    127
        DEFB    0C0h,0
        DEFW    0
        DEFW    0

; ------------------------------------------------------------- consolas
; D = consola
CONST:  CALL    ISTMP           ; el TMP (indicador de ordenes): historial
        JP      Z,TCONST
CONSTR: LD      A,D
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

CONIN:  CALL    ISTMP
        JP      Z,TCONIN
CONINR: LD      A,D
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

; LIST: la impresora (LST:) sale por la SIO B, la misma linea de la consola 1
; (un terminal, el NUNTIUS o un cable a oli que la capture).
LIST:   CALL    COST1
        OR      A
        JR      NZ,COUT1B
        PUSH    BC
        LD      C,POLL
        LD      E,4             ; dispositivo 4: impresora lista
        CALL    XDOS
        POP     BC
        JR      COUT1B

POLLDEV: LD     A,C
        CP      4
        JP      Z,COST1         ; 4: impresora (SIO B) lista
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
        LD      HL,TICKS        ; cuenta de tics (60 por segundo), 32 bits
        INC     (HL)
        JR      NZ,ITK1
        INC     HL
        INC     (HL)
        JR      NZ,ITK1
        INC     HL
        INC     (HL)
        JR      NZ,ITK1
        INC     HL
        INC     (HL)
ITK1:   LD      A,(TICKN)
        OR      A
        JR      Z,IT1
        LD      C,FLAGSET       ; bandera 1: cada tic
        LD      E,1
        CALL    XDOS
IT1:    LD      HL,CNTSEC
        DEC     (HL)
        JR      NZ,ITDONE
        LD      (HL),TPS
        LD      HL,(SECS)       ; segundos desde el arranque (para TODCHK)
        INC     HL
        LD      (SECS),HL
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
        LD      HL,0
        CP      4
        RET     NC              ; sin unidad
        CP      2
        JR      NZ,SELD1
        LD      A,(NRPG)        ; disco en RAM: solo si hay paginas
        OR      A
        RET     Z
SELD1:
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

; READ / WRITE: 0 = bien, 1 = error
READ:   CALL    TODCHK          ; cambiaron la hora? -> al DS1307
        CALL    DSKADR
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

WRITE:  CALL    TODCHK
        CALL    DSKADR
        LD      A,(DSKC)
        CP      3
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
        LD      A,(DSKC)
        CP      2
        JP      Z,RAMWR         ; disco en RAM
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

; TODADR: HL = TOD de XDOS (dia de 16 bits, hora, minuto, segundo en BCD)
TODADR: LD      HL,(SYSDAT)
        LD      L,252
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        RET

; BINBCD: A (0-99) -> BCD
BINBCD: PUSH    BC              ; conserva BC
        LD      B,0FFh
BB1:    INC     B
        SUB     10
        JR      NC,BB1
        ADD     A,10
        LD      C,A
        LD      A,B
        RLCA
        RLCA
        RLCA
        RLCA
        OR      C
        POP     BC
        RET

; DAY2YMD: HL = dia de MP/M (1 = domingo 1/1/1978) -> DDOW (1 = domingo),
; DDATE, DMON, DYEAR (BCD; el anio 20YY o 19YY en dos cifras). Va en la comun:
; la usan RTCSET (banco 0) y el servicio 28 de ZIOS (banco del programa).
DAY2YMD: PUSH   HL              ; dia de la semana: (dia - 1) mod 7 + 1
        DEC     HL
        LD      DE,7
DY1:    OR      A
        SBC     HL,DE
        JR      NC,DY1
        ADD     HL,DE
        INC     L
        LD      A,L
        LD      (DDOW),A
        POP     HL
        LD      C,78            ; anio (desde 1900)
DY2:    LD      DE,365
        LD      A,C
        AND     3
        JR      NZ,DY3
        INC     DE              ; bisiesto (1980..2096)
DY3:    PUSH    HL
        OR      A
        SBC     HL,DE
        JR      C,DY4
        JR      Z,DY4
        POP     DE              ; mas dias que el anio: al siguiente
        INC     C
        JR      DY2
DY4:    POP     HL              ; HL = dia del anio (1..366)
        LD      A,C
        SUB     100
        JR      NC,DY5
        ADD     A,100
DY5:    CALL    BINBCD
        LD      (DYEAR),A
        LD      DE,MESES
        LD      B,1             ; mes
DY6:    PUSH    DE
        LD      A,(DE)
        LD      E,A
        LD      D,0
        LD      A,B
        CP      2
        JR      NZ,DY7
        LD      A,C
        AND     3
        JR      NZ,DY7
        INC     E               ; febrero bisiesto
DY7:    PUSH    HL
        OR      A
        SBC     HL,DE
        JR      C,DY8
        JR      Z,DY8
        POP     DE              ; descartar
        POP     DE
        INC     DE
        INC     B
        JR      DY6
DY8:    POP     HL
        POP     DE
        LD      A,L
        CALL    BINBCD
        LD      (DDATE),A
        LD      A,B
        CALL    BINBCD
        LD      (DMON),A
        RET
MESES:  DEFB    31,28,31,30,31,30,31,31,30,31,30,31
DDOW:   DEFB    0               ; (en este orden: como los registros 3-6 del DS1307)
DDATE:  DEFB    0
DMON:   DEFB    0
DYEAR:  DEFB    0
RTB:    DEFS    7


; ISTMP: Z si el proceso que corre es un TMP (nombre "Tmp..."). Los TMP corren
; en el banco 0, asi que el historial de ordenes vive en la parte con bancos.
; Conserva DE.
ISTMP:  PUSH    DE
        CALL    TODADR          ; HL = datapg (TOD esta al principio)
        LD      DE,5            ; datapg+5: rlr, el proceso que corre
        ADD     HL,DE
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        LD      E,6             ; nombre en el descriptor + 6
        ADD     HL,DE
        POP     DE
        LD      A,(HL)
        AND     7Fh
        CP      'T'
        RET     NZ
        INC     HL
        LD      A,(HL)
        AND     7Fh
        CP      'm'
        RET     NZ
        INC     HL
        LD      A,(HL)
        AND     7Fh
        CP      'p'
        RET

; ------------------------------------------------------------- servicios de ZIOS
; Los programas de la Z80-Retro llaman a ZIOS con RST 30h (numero en C). Bajo
; MP/M, ZIOS ya no esta: la pagina cero de cada banco salta aqui, que atiende
; los servicios que tienen sentido con las funciones de MP/M:
;   0 salir, 4 escribir un caracter, 5 leer uno (espera), 6 hay caracter?,
;   28 fecha y hora (6 bytes BCD en HL), 31 tics (DEHL, A = 60 por segundo).
; Los demas devuelven A = FF.
ZEMU:   LD      (ZHL),HL
        PUSH    HL
        PUSH    DE
        PUSH    BC
        LD      A,C
        OR      A
        JP      Z,0             ; 0: terminar el programa
        CP      4
        JR      Z,ZTX
        CP      5
        JR      Z,ZRX
        CP      6
        JR      Z,ZCK
        CP      28
        JR      Z,ZDT
        CP      31
        JR      Z,ZTK
        LD      A,0FFh
ZRET:   POP     BC
        POP     DE
        POP     HL
        RET
ZTX:    LD      A,E             ; E = caracter
        LD      C,6             ; salida directa
        CP      0FEh
        JR      C,ZTX1
        LD      C,2             ; FE y FF no se pueden mandar con la 6
ZTX1:   CALL    5
        XOR     A
        JR      ZRET
ZRX:    LD      C,6             ; esperar un caracter, sin eco
        LD      E,0FFh
        CALL    5
        OR      A
        JR      NZ,ZRET
        LD      C,141           ; ceder un tic a los demas procesos
        LD      DE,1
        CALL    5
        JR      ZRX
ZCK:    LD      C,11            ; A = FF si hay caracter
        CALL    5
        OR      A
        JR      ZRET
ZDT:    CALL    TODADR          ; copia de la hora de XDOS sin que el tic la cambie
        LD      DE,ZTOD
        LD      BC,5
        DI
        LDIR
        EI
        LD      HL,(ZTOD)
        CALL    DAY2YMD
        LD      HL,(ZHL)        ; buffer: seg, min, hora, dia, mes, anio
        LD      A,(ZTOD+4)
        LD      (HL),A
        INC     HL
        LD      A,(ZTOD+3)
        LD      (HL),A
        INC     HL
        LD      A,(ZTOD+2)
        LD      (HL),A
        INC     HL
        LD      A,(DDATE)
        LD      (HL),A
        INC     HL
        LD      A,(DMON)
        LD      (HL),A
        INC     HL
        LD      A,(DYEAR)
        LD      (HL),A
        XOR     A
        JR      ZRET
ZTK:    POP     BC              ; DEHL = tics, A = tics por segundo
        POP     AF
        POP     AF
        DI
        LD      HL,(TICKS)
        LD      DE,(TICKS+2)
        EI
        LD      A,TPS
        RET
ZHL:    DEFW    0
ZTOD:   DEFS    5

; ------------------------------------------------------------- datos (comun)
TICKN:  DEFB    0
TICKS:  DEFS    4               ; tics desde el arranque (servicio 31 de ZIOS)
SECS:   DEFW    0               ; segundos desde el arranque
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
