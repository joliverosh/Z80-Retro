; =============================================================================
;  XIOS de MP/M II para la Z80-Retro (Z80 CPU Rev 2.2 y ZEPHYRUS Rev 2.3)
;  OLIVEROS 2026 - sobre ZLoader/ZIOS v6 de Peter Wilson (MIT)
;
;  Memoria: las 4 ventanas de 16 KB del 74LS670 (puertos 60h-63h).
;    - Ventana 3 (C000-FFFF): memoria comun, la misma pagina siempre.
;    - Ventanas 0-2 (0000-BFFF): un banco = 3 paginas de 16 KB. El banco 0 es
;      el del sistema (las paginas que dejo ZIOS); los bancos 1-7 son de los
;      usuarios y salen de las paginas de RAM libres (20h-3Fh).
;  Consolas: 0-3 virtuales en la SIO A (Ctrl-F1..F4 o Ctrl-\ 1..4 eligen la que
;    se ve; cada una tiene su pantalla de 80 x 24 en una pagina de RAM y se
;    redibuja al cambiar), 4 = SIO B. Recepcion y transmision por interrupcion
;    (IM 2, los mismos vectores que ZIOS: SIO en FFE0-FFEE, CTC en FFF0-FFF6).
;    Con STATUS=ON en A:MPM.CFG la fila 24 es una linea de estado.
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
NMBCNS  EQU     5               ; consolas: 0-3 virtuales en la SIO A, 4 en la SIO B
NDRV    EQU     16              ; unidades A-P
MAXBNK  EQU     7               ; bancos de usuario (GENSYS: user memory segments)
MAXRPG  EQU     128             ; paginas del disco en RAM como maximo (2 MB)
MAXEXT  EQU     160             ; paginas del bus de expansion que se toman
; Memoria baja del banco 0 (4000-63FF): MP/M empieza mas arriba y la ventana 1
; no cambia durante SYSINIT. Solo para lo que se usa con el banco 0 puesto.
B0MEM   EQU     4000h
HSTB    EQU     B0MEM           ; historial: HSZ bytes por consola (hasta 5)
; CFGBUF B0MEM+1000h, RPV +1300h, POOL +1400h (ver mas abajo)
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

VQ      EQU     0FFD5h          ; caracteres de la consola que se ve que faltan pasar a
                                ; su pantalla (VQMAX, hasta FFDA)
ITXF    EQU     0FE00h          ; el camino corto del transmisor de la SIO A (FE00-FE3F)
RXB     EQU     0FE40h          ; bufer circular de la SIO B (consola 4)
DIRBF   EQU     0FE80h          ; bufer de directorio (en la comun: READ copia con el banco del usuario puesto)
BOUNCE  EQU     0FF00h          ; 64 bytes de paso entre BUF y el DMA del programa
ISTK    EQU     0FF80h          ; pila de las interrupciones (FF40-FF7F)
TXA     EQU     0FF80h          ; buferes de salida (6 + 32 bytes cada uno), FF80-FFCB
TXB     EQU     TXA+6+TXMSK+1
; Impresora a un archivo (A:MPM.CFG con LST=archivo): bloque fijo que lee H:LSTFILE
LSTMD   EQU     0FFCCh          ; 0 = LST: a la SIO B, 1 = al anillo de LSTPG
LSTPG   EQU     0FFCDh          ; pagina de 16 KB del anillo
LSTH    EQU     0FFCEh          ; cabeza (la saca LSTFILE), 0-3FFF
LSTT    EQU     0FFD0h          ; cola (la pone LIST)
CURPG2  EQU     0FFD2h          ; pagina de la ventana 2 del banco puesto (para LSTFILE)
CURPG1  EQU     0FFD4h          ; y de la ventana 1 (BKCALL la repone)
VQN     EQU     0FFD3h          ; cuantos hay en VQ
VQMAX   EQU     6               ; VQFL corre con las interrupciones apagadas: de a
                                ; pocos, para que la SIO A no pierda lo que llega
VSIO    EQU     0FFE0h          ; vectores de la SIO (WR2 = E0h, lo puso ZIOS)
VCTC    EQU     0FFF0h          ; vectores del CTC (vector F0h, lo puso ZIOS)

POLL    EQU     131
FLAGSET EQU     133
FLAGWT  EQU     132
FLTXA   EQU     12              ; banderas: hay lugar en el bufer de salida de la SIO A / B
FLTXB   EQU     13
TXMSK   EQU     31              ; bufer de salida de 32 caracteres por canal
CTC0    EQU     40h             ; canal 0 del CTC (reloj de la SIO por P3/P6)
; Pagina VTPG (en la ventana 0 durante BKCALL): las pantallas de las consolas
; virtuales: un anillo de VRING filas de 80 cada una (24 se ven, el resto es lo
; que se fue por arriba), los datos y la pila de BKCALL al final
GBUF    EQU     3C00h           ; trozo que se esta mandando (redibujo, linea de estado)
VST     EQU     3C80h           ; estado por consola (5 x 16 bytes): fila, columna, fila
                                ; de arriba (en el anillo), estado ESC, param 1, param 2,
                                ; param actual, salida sin ver, direccion de la fila del
                                ; cursor (2), si vale (1), -, filas guardadas arriba (12),
                                ; principio de su anillo (13-14)
VNR     EQU     3CD0h           ; filas que se ven (24, o 23 con la linea de estado)
KN      EQU     3CD1h           ; teclado: bytes de una secuencia en KBUF (10: Ctrl-\)
KBUF    EQU     3CD2h           ; (8)
GSTG    EQU     3CDAh           ; redibujo: etapa (0 prefijo, 1..VNR filas, VNR+1 cursor)
GCNT    EQU     3CDBh
GPTR    EQU     3CDCh
STDAY   EQU     3CDEh           ; dia de MP/M de la fecha ya calculada
VIEWOFS EQU     3CE0h           ; filas hacia atras que se estan mirando (0 = al dia)
NVC     EQU     3CE1h           ; consolas virtuales: 4, o 5 con CONSOLE4=VIRTUAL
VRING   EQU     3CE2h           ; filas del anillo de cada una: 48 (4) o 36 (5)
VQD0    EQU     3CE3h           ; VQFL: donde empieza la tanda (2) y su columna
VQC0    EQU     3CE5h
GCOL    EQU     3CE6h           ; redibujo: columna de la fila que va saliendo,
GATTR   EQU     3CE7h           ; atributo que ya tiene el terminal
GRLEN   EQU     3CE8h           ; y largo de la fila
RAWH    EQU     7CFCh           ; cabeza y cola (0-1FF) del anillo RAWQ de la SIO A, en
RAWT    EQU     7CFEh           ; la pagina de atributos: IRXA las usa solo con la ventana 1
RAWQ    EQU     7E00h           ; (512 bytes: un bloque de 1K de XMODEM entra sin perderse)
; Los atributos de cada caracter van en otra pagina (VTAPG), en la ventana 1
; durante BKCALL: el de (HL) esta en (HL+4000h). Bits: 0 negrita, 1 subrayado,
; 2 parpadeo, 3 inverso, 4-6 color del texto, 7 hay color.
VRXB    EQU     3D00h           ; lo tecleado en cada consola virtual: 64 bytes cada una
VRXP    EQU     3E40h           ; y su cabeza y cola (5 x 2)
BKSTK   EQU     4000h           ; tope de la pila de BKCALL

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
        LD      HL,HSTB         ; historial vacio
        LD      DE,HSTB+1
        LD      BC,NMBCNS*HSZ-1
        LD      (HL),0
        LDIR
        CALL    STFIND          ; ---- 1c. hay A:STARTUP.SUB?
        CALL    EXTQRY          ; ---- 1d. RAM del bus de expansion (servicio 2)
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
        CALL    CFGPRS          ; A:MPM.CFG: impresora, linea de estado, velocidades, unidades
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
        LD      A,(BNKPG+2)     ; (BKCALL las repone)
        LD      (CURPG2),A
        LD      A,(BNKPG+1)
        LD      (CURPG1),A
        LD      A,(BNKPG)
        LD      (CURPG0),A
        OUT     (PGPORT),A
        CALL    RDPRB           ; y las del disco en RAM de ZIOS, que no las entrego
        CALL    PGPOOL          ; paginas libres -> bancos 1-7 segun cuantas haya
        CALL    CINIT           ; las paginas que sobran: cache de disco
        CALL    LSTINI          ; una para la impresora si va a un archivo
        CALL    RINIT           ; y las que quedan, el disco en RAM (G:)
        CALL    STARMA          ; ordenes que se teclean solas en la consola 0
        ; pagina cero de cada banco: JP a la tabla de saltos, el RST del
        ; depurador y un RET en 30h (los programas de la Z80-Retro llaman a ZIOS)
        LD      A,(NBNKS)
        LD      B,A
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
        LD      HL,ITXFS        ; el camino corto del transmisor de la SIO A, a
        LD      DE,ITXF         ; FE00 (ZIOS ya no esta)
        LD      BC,ITXFE-ITXFS
        LDIR
        LD      HL,ITXF
        LD      (VSIO+8),HL
        LD      A,0FFh
        LD      I,A
        IM      2
        XOR     A               ; buferes vacios
        LD      (VQN),A
        LD      (HDB),A
        LD      (TLB),A

        LD      HL,TXINI        ; buferes de salida vacios
        LD      DE,TXA
        LD      BC,6
        LDIR
        LD      HL,TXINI+6
        LD      DE,TXB
        LD      C,6
        LDIR
        LD      HL,SIOINI
        LD      B,SIOINN
SI13:   LD      C,(HL)
        INC     HL
        LD      A,(HL)
        INC     HL
        OUT     (C),A
        DJNZ    SI13
        CALL    CFBAUD          ; velocidades de A:MPM.CFG
        ; SD: SDHC o SDSC (CMD58, bit CCS del OCR)
        LD      A,0FFh
        LD      (CCARD),A
        XOR     A
        CALL    SDTIPO
        LD      A,1
        CALL    SDTIPO
        ; mensaje
        LD      HL,MSG
        CALL    PRSTR
        LD      A,(NBNKS)       ; "n bancos, unidades A-P"
        ADD     A,'0'
        CALL    SIOPUT
        LD      HL,MSGB
        CALL    PRSTR
        LD      A,(NCPG)        ; "nn KB de cache de disco"
        LD      HL,MSGC
        CALL    PRKB
        LD      A,(NRPG)        ; "G: disco en RAM de nnn KB"
        OR      A
        LD      HL,MSGG0        ; (o que no hay: toda la RAM esta en uso)
        JR      NZ,SI15B
        CALL    PRSTR
        JR      SI15C
SI15B:  LD      HL,MSGG
        CALL    PRSTR
        LD      A,(NRPG)
        LD      HL,MSGK
        CALL    PRKB
SI15C:  LD      A,(STSUB)       ; "A:STARTUP.SUB"
        OR      A
        LD      HL,MSGS
        CALL    NZ,PRSTR
        LD      A,(LSTMD)       ; "LST: a un archivo"
        OR      A
        LD      HL,MSGL
        CALL    NZ,PRSTR
SI15E:  CALL    TODADR          ; donde XDOS tiene el proceso que corre
        LD      DE,5
        ADD     HL,DE
        LD      (RLRA),HL
        LD      (VCRLR+1),HL
        CALL    UDINI           ; READ/WRITE directo al DMA del programa
        LD      A,(STATON)      ; con linea de estado: redibujar (fija las filas
        OR      A               ; que se desplazan)
        JR      Z,SI15F
        LD      (GENACT),A
        CALL    TXSTA
SI15F:  LD      SP,(SVSP)
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
        LD      B,0             ; 0: todavia no hay digitos (ceros a la izquierda)
        LD      DE,1000
        CALL    PRDIG
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
; PRDIG: digito de HL / DE; HL = resto
PRDIG:  LD      A,'0'-1
PRD1:   INC     A
        OR      A
        SBC     HL,DE
        JR      NC,PRD1
        ADD     HL,DE
        CP      '0'
        JR      NZ,PRD2
        INC     B
        DEC     B
        RET     Z
PRD2:   LD      B,1
        JP      SIOPUT

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
GETBLK: CALL    FLCHK           ; BUF con cambios y otro bloque: a la tarjeta
        RET     NZ
        LD      A,(DSKC)
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
GB0:    LD      A,(GMODE)       ; un bloque sin usar: no hace falta leerlo
        CP      2
        JP      Z,GBNEW
        LD      A,(NCPG)        ; con cache: buscarlo alli
        OR      A
        JP      NZ,CGET
GB1:    LD      A,0FFh
        LD      (CCARD),A       ; invalido mientras se lee
        LD      (BUFSL),A
        LD      (BUFOK),A       ; (FF: BUF no esta en la cache)
        CALL    SDRDX
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
        LD      (BUFOK),A       ; (FF: BUF no esta en la cache)
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
        LD      A,0
        LD      (BUFOK),A       ; BUF esta en el hueco BUFSL
        RET

; CWRREC: el registro que WRITE acaba de escribir en la tarjeta, tambien en la
; cache (si el bloque de BUF esta en ella). Devuelve A = 0 (bien).
CWRREC: LD      A,(BUFOK)
        INC     A
        JR      Z,CWR9
        LD      A,(BUFSL)
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
CWRERR: LD      A,(BUFOK)
        INC     A
        JR      Z,CWE9
        LD      A,(BUFSL)
        CALL    TAGADR
        LD      (HL),0FFh
CWE9:   LD      A,0FFh
        LD      (CCARD),A
        LD      (BUFSL),A
        LD      (BUFOK),A       ; (FF: BUF no esta en la cache)
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

; CINIT: paginas de la reserva para la cache (despues de los bancos): 8, 4, 2,
; 1 o ninguna (los conjuntos van en potencia de 2). Etiquetas vacias.
CINIT:  LD      A,(POOLN)
        LD      C,8
CI1:    CP      C
        JR      NC,CI4
        SRL     C
        JR      NZ,CI1
CI4:    LD      A,C
        LD      (NCPG),A
        LD      DE,CPG
        CALL    POOLTK
        LD      A,(NCPG)
        ADD     A,A             ; conjuntos = paginas * 16
        ADD     A,A
        ADD     A,A
        ADD     A,A
        DEC     A
        LD      (NCONJ),A
        LD      HL,CTAG         ; todas las etiquetas vacias (tarjeta FF)
        LD      DE,CTAG+1
        LD      (HL),0FFh
        LD      BC,5*256-1
        LDIR
        LD      A,0FFh
        LD      (BUFSL),A
        LD      (BUFOK),A       ; (FF: BUF no esta en la cache)
        RET

GMODE:  DEFB    0               ; 0 = basta el registro, 1 = bloque entero
CSLOT:  DEFB    0
CSET:   DEFB    0
BUFSL:  DEFB    0               ; hueco que tiene el bloque de BUF (0-255)
BUFOK:  DEFB    0FFh            ; 0: BUFSL vale; FF: BUF no esta en la cache
NCPG:   DEFB    0               ; paginas de cache (0 = sin cache)
NCONJ:  DEFB    0
CPAGE:  DEFB    0
CPG:    DEFS    8
CLRU:   DEFS    128             ; via mas reciente de cada conjunto
CTAG:   DEFS    5*256           ; etiquetas: tarjeta (FF = vacio) y bloque

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

; SPIRB: 512 bytes de la SD a (HL), con el bucle desenrollado (400 ciclos por
; byte en lugar de 620)
SPIRB:  LD      C,SPIIN
        LD      A,1
        LD      B,0
        CALL    SRB1
SRB1:
        OUT     (SPIL),A
        OUT     (SPIH),A
        IN      D,(C)
        RR      D
        RL      E
        OUT     (SPIL),A
        OUT     (SPIH),A
        IN      D,(C)
        RR      D
        RL      E
        OUT     (SPIL),A
        OUT     (SPIH),A
        IN      D,(C)
        RR      D
        RL      E
        OUT     (SPIL),A
        OUT     (SPIH),A
        IN      D,(C)
        RR      D
        RL      E
        OUT     (SPIL),A
        OUT     (SPIH),A
        IN      D,(C)
        RR      D
        RL      E
        OUT     (SPIL),A
        OUT     (SPIH),A
        IN      D,(C)
        RR      D
        RL      E
        OUT     (SPIL),A
        OUT     (SPIH),A
        IN      D,(C)
        RR      D
        RL      E
        OUT     (SPIL),A
        OUT     (SPIH),A
        IN      D,(C)
        RR      D
        RL      E
        LD      (HL),E
        INC     HL
        DJNZ    SRB1
        RET

; SPIWB: 512 bytes de (HL) a la SD, desenrollado
SPIWB:  LD      B,0
        CALL    SWB1
SWB1:   LD      A,(HL)
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
        RLCA
        OUT     (SPIL),A
        OUT     (SPIH),A
        INC     HL
        DJNZ    SWB1
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
        LD      A,(SDCRC)       ; CRC (solo cuenta en CMD0 y CMD8)
        CALL    SPITX
        LD      A,0FFh
        LD      (SDCRC),A
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
        CALL    SPIRB
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
        CALL    SPIWB
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

ACC:    DEFS    4
X32:    DEFS    4
BASE:   DEFS    4               ; segundos de la hora de referencia
BSECS:  DEFW    0               ; SECS cuando se tomo la referencia
LASTS:  DEFW    0

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
        LD      (BUFOK),A       ; (FF: BUF no esta en la cache)
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
RINIT:  LD      A,(POOLN)       ; todas las que quedan (hasta MAXRPG)
        CP      MAXRPG+1
        JR      C,RI1
        LD      A,MAXRPG
RI1:    LD      (NRPG),A
        LD      DE,RAMPG
        CALL    POOLTK
        LD      A,(NRPG)
        OR      A
        RET     Z
        LD      L,A
        LD      H,0
        CP      16
        JR      NC,RI2
        ADD     HL,HL           ; hasta 15 paginas: bloques de 1 KB,
        ADD     HL,HL           ; DSM = paginas * 16 - 1
        ADD     HL,HL
        ADD     HL,HL
        DEC     HL
        LD      BC,0307h        ; BSH, BLM
        LD      DE,03F00h       ; DRM = 63 (2 bloques de 1 KB), EXM = 0
        JR      RI3
RI2:    ADD     HL,HL           ; 16 o mas: bloques de 2 KB, DSM = paginas * 8 - 1
        ADD     HL,HL
        ADD     HL,HL
        DEC     HL
        LD      BC,040Fh
        LD      DE,07F01h       ; DRM = 127 (2 bloques de 2 KB), EXM = 1 con DSM < 256
        LD      A,H
        OR      A
        JR      Z,RI3
        DEC     E               ; EXM = 0
RI3:    LD      (DPBRM+5),HL
        LD      A,B
        LD      (DPBRM+2),A
        LD      A,C
        LD      (DPBRM+3),A
        LD      A,E
        LD      (DPBRM+4),A
        LD      A,D
        LD      (DPBRM+7),A
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
        LD      A,(RAMPG)       ; directorio (hasta 4 KB al principio) en E5
        LD      (CPAGE),A
        LD      HL,0
        LD      B,64            ; 64 trozos de 64
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

NRPG:   DEFB    0               ; paginas del disco en RAM (0 = no hay)
RAMPG:  DEFS    MAXRPG

; ------------------------------------------------------------- reserva de paginas
; EXTQRY: con ZIOS todavia debajo, le pide todas sus paginas libres (servicio 2)
; y guarda las del bus de expansion (40h en adelante) en POOL+32. ZIOS ya probo
; cuales tienen RAM y reservo las que no.
EXTQRY: LD      HL,POOL+32
        LD      B,0
EQ1:    PUSH    HL
        PUSH    BC
        LD      C,2
        CALL    ZIOS            ; A = pagina (0 = no quedan)
        POP     BC
        POP     HL
        OR      A
        JR      Z,EQ9
        CP      40h
        JR      C,EQ1           ; las de la placa se cuentan despues
        LD      (HL),A
        INC     HL
        INC     B
        LD      A,B
        CP      MAXEXT
        JR      NZ,EQ1
EQ9:    LD      A,B
        LD      (NEXT),A
        RET

; PGPOOL: arma la reserva (las paginas de la placa que no son del banco 0 ni la
; comun, de arriba hacia abajo, y despues las del bus), decide cuantos bancos
; de usuario hay (3 paginas cada uno, dejando 13 para la cache y G:, entre 1 y
; MAXBNK), les da sus paginas y deja ese numero de segmentos en SYSDAT.
PGPOOL: LD      HL,POOL
        LD      B,0
        LD      C,3Fh
PP1:    LD      A,C
        CALL    USADA
        JR      Z,PP2
        LD      (HL),C
        INC     HL
        INC     B
PP2:    DEC     C
        LD      A,C
        CP      1Fh
        JR      NZ,PP1
        LD      A,(NEXT)        ; las del bus, a continuacion
        OR      A
        JR      Z,PP3
        PUSH    BC
        EX      DE,HL
        LD      HL,POOL+32
        LD      C,A
        LD      B,0
        LDIR
        POP     BC
        LD      A,(NEXT)
        ADD     A,B
        LD      B,A
PP3:    LD      A,B
        LD      (POOLN),A
        LD      HL,POOL
        LD      (POOLP),HL
        LD      A,1             ; una pagina para las pantallas de las consolas
                                ; virtuales (y lo que se teclea en ellas)
        LD      DE,VTPG
        CALL    POOLTK
        LD      A,1             ; y otra para sus atributos
        LD      DE,VTAPG
        CALL    POOLTK
        LD      HL,VTINI
        CALL    BKCALL
        LD      A,(POOLN)
PP4:    LD      C,A             ; bancos = paginas / 3, hasta MAXBNK: la RAM es
                                ; primero para MP/M; la cache y G: se llevan lo que sobre
        LD      B,0
PP5:    LD      A,C
        SUB     3
        JR      C,PP6
        LD      C,A
        INC     B
        LD      A,B
        CP      MAXBNK
        JR      NZ,PP5
PP6:    LD      A,B
        OR      A
        JR      NZ,PP7
        INC     A               ; al menos uno
PP7:    LD      (NBNKS),A
        LD      B,A             ; 3 paginas por banco
        ADD     A,A
        ADD     A,B
        LD      DE,BNKPG+3
        CALL    POOLTK
        LD      HL,(SYSDAT)     ; SYSDAT+15: segmentos de memoria (el del
        LD      L,15            ; sistema y los de usuario)
        LD      A,(NBNKS)
        INC     A
        LD      (HL),A
        RET

; POOLTK: copia A paginas de la reserva a DE y las saca de la reserva
POOLTK: OR      A
        RET     Z
        LD      C,A
        LD      B,0
        LD      HL,POOLN
        LD      A,(HL)
        SUB     C
        LD      (HL),A
        LD      HL,(POOLP)
        LDIR
        LD      (POOLP),HL
        RET

; RDPRB: con ZIOS ya afuera, prueba las paginas del bus (40-7F y C0-FF; las
; 80-BF pueden ser gemelas de la placa) que ZIOS no entrego, que son las de su
; disco en RAM, y agrega a POOL+32 las que tienen RAM propia: guardan lo que se
; escribe y no son un espejo de otra pagina conocida.
RDPRB:  LD      C,40h
RP1:    LD      A,C
        CP      80h
        JR      NZ,RP2
        LD      C,0C0h
RP2:    CALL    ENEXT           ; ya esta en la lista?
        JR      Z,RP9
        LD      A,(NEXT)
        CP      MAXEXT
        JR      NC,RP10
        CALL    RPTEST
        JR      NZ,RP9
        LD      HL,POOL+32      ; RAM propia: a la lista
        LD      A,(NEXT)
        ADD     A,L
        LD      L,A
        JR      NC,RP3
        INC     H
RP3:    LD      (HL),C
        LD      HL,NEXT
        INC     (HL)
RP9:    INC     C
        JR      NZ,RP1
RP10:   LD      A,(BNKPG)       ; la ventana 0 como estaba
        OUT     (PGPORT),A
        RET
; ENEXT: Z si la pagina C esta en la lista del bus
ENEXT:  LD      HL,POOL+32
        LD      A,(NEXT)
        OR      A
        JR      Z,EN9
        LD      B,A
EN1:    LD      A,(HL)
        CP      C
        RET     Z
        INC     HL
        DJNZ    EN1
EN9:    OR      1
        RET
; RPTEST: Z si la pagina C tiene RAM propia (prueba en 3FF0 de la ventana 0)
RPTEST: LD      A,C
        OUT     (PGPORT),A
        LD      HL,3FF0h
        LD      A,(HL)
        LD      (RPS),A
        LD      (HL),55h
        LD      A,(HL)
        CP      55h
        JR      NZ,RPNO
        LD      (HL),0AAh
        LD      A,(HL)
        CP      0AAh
        JR      NZ,RPNO
        LD      A,(RPS)
        LD      (HL),A
        XOR     A               ; foto de las paginas conocidas
        LD      (RPM),A
        CALL    KNOWN
        LD      A,C             ; cambiar la candidata
        OUT     (PGPORT),A
        LD      A,(RPS)
        CPL
        LD      (3FF0h),A
        LD      A,1             ; cambio alguna conocida? -> espejo
        LD      (RPM),A
        CALL    KNOWN
        PUSH    AF
        LD      A,C
        OUT     (PGPORT),A
        LD      A,(RPS)
        LD      (3FF0h),A
        POP     AF
        RET
RPNO:   OR      1
        RET
; KNOWN: recorre la placa (20-3F) y la lista del bus: RPM = 0 guarda 3FF0 de
; cada una en RPV; RPM = 1 compara (NZ si alguna cambio)
KNOWN:  LD      DE,RPV
        LD      B,20h
KN1:    LD      A,B
        CALL    KONE
        RET     NZ
        INC     B
        LD      A,B
        CP      40h
        JR      NZ,KN1
        LD      HL,POOL+32
        LD      A,(NEXT)
        OR      A
        RET     Z
        LD      B,A
KN2:    LD      A,(HL)
        PUSH    HL
        CALL    KONE
        POP     HL
        RET     NZ
        INC     HL
        DJNZ    KN2
        XOR     A
        RET
KONE:   OUT     (PGPORT),A
        LD      A,(3FF0h)
        EX      DE,HL
        PUSH    AF
        LD      A,(RPM)
        OR      A
        JR      NZ,KO2
        POP     AF
        LD      (HL),A
        INC     HL
        EX      DE,HL
        XOR     A
        RET
KO2:    POP     AF
        CP      (HL)
        INC     HL
        EX      DE,HL
        RET
RPS:    DEFB    0
RPM:    DEFB    0
RPV     EQU     B0MEM+1300h     ; (en la memoria baja del banco 0)

NBNKS:  DEFB    MAXBNK
NEXT:   DEFB    0
POOLN:  DEFB    0
POOLP:  DEFW    POOL
POOL    EQU     B0MEM+1400h

; ------------------------------------------------------------- historial de ordenes
; Solo para el TMP (el indicador nA>): ^W recupera la orden anterior; cada ^W
; seguido va una mas atras (hasta 8 por consola). Funciona dentro de la
; lectura de linea del BDOS: el XIOS devuelve ^X (borra la linea) y despues los
; caracteres de la orden guardada, como si se escribieran. Los programas no lo
; ven: para ellos ^W sigue siendo ^W.
HLEN    EQU     80              ; caracteres por linea
HNUM    EQU     8               ; lineas por consola

; HCON: IX = estado de la consola D (HSTB + D * HSZ)
HCON:   PUSH    DE
        PUSH    BC
        LD      IX,HSTB
        LD      BC,HSZ
        LD      A,D
        INC     A
HC1:    DEC     A
        JR      Z,HC2
        ADD     IX,BC
        JR      HC1
HC2:    POP     BC
        POP     DE
        RET
; estado por consola (desplazamientos en IX):
;  0 largo de la linea actual   1 reproduciendo: caracteres que faltan
;  2 indice de reproduccion     3 linea que se reproduce
;  4 lineas guardadas           5 la mas nueva   6 profundidad del ultimo ^W
;  7.. linea actual (HLEN)      7+HLEN.. HNUM lineas de (1 largo + HLEN)
HSZ     EQU     7+HLEN+HNUM*(HLEN+1)

; Mientras quedan ordenes del arranque por entregar, CONST dice "nada": el TMP
; vacia lo tecleado (con CONST y CONIN) antes de leer, y se llevaria esas ordenes.
TCONST: CALL    STPEND
        LD      A,0
        RET     NZ
        PUSH    IX
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


; ------------------------------------------------------------- fecha e I2C
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
; DDATE, DMON, DYEAR (BCD; el anio 20YY o 19YY en dos cifras). En la parte con
; bancos: el servicio 28 de ZIOS la llama con BKCALL (ZDTB).
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

; ZDTB (BKCALL): la fecha del dia de ZTOD en ZTOD+5..7 (para el servicio 28)
ZDTB:   LD      HL,(ZTOD)
        CALL    DAY2YMD
        LD      HL,DDATE
        LD      DE,ZTOD+5
        LD      BC,3
        LDIR
        RET

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
IRBY:   PUSH    BC              ; recibe un byte; A = bit que se contesta (0 = ACK)
        PUSH    DE
        LD      C,A
        LD      B,8
IR1:    CALL    IRBI
        RRA
        RL      E
        DJNZ    IR1
        LD      A,C
        CALL    IWBI
        LD      A,E
        POP     DE
        POP     BC
        RET
IVAL:   DEFB    3
ICLKP:  DEFB    SPICS
; Para el servicio 34 (BKCALL, un byte cada vez). A = 0/1 (ACK/NAK) o el byte.
I2CBEG: LD      A,3             ; SCL y SDA arriba; inicio y direccion
        LD      (IVAL),A
        OUT     (SPICS+1),A
        CALL    ISTART
        LD      A,D
        AND     0FEh
        BIT     0,C
        JR      Z,I2CB1
        INC     A
I2CB1:  CALL    IWBY
        AND     1
        RET
I2CWB:  LD      A,E
        CALL    IWBY
        AND     1
        RET
I2CRB:  LD      A,E
        JP      IRBY

; ------------------------------------------------------------- consolas virtuales
; Todo esto corre con BKCALL: la pagina VTPG en la ventana 0 (pantallas y datos)
; y las interrupciones apagadas.

; VTINI: pantallas en blanco, estado en cero
VTINI:  LD      HL,0
        LD      DE,1
        LD      BC,4*0F00h-1
        LD      (HL),' '
        LDIR
        LD      HL,4000h        ; atributos en cero
        LD      DE,4001h
        LD      BC,4*0F00h-1
        LD      (HL),0
        LDIR
        LD      HL,VST
        LD      DE,VST+1
        LD      BC,VRXP+8-VST-1
        LD      (HL),0
        LDIR
        LD      A,(SIOBM)       ; 4 consolas de 48 filas, o 5 de 36
        CP      2
        LD      BC,0430h
        JR      NZ,VTI0
        LD      BC,0524h
VTI0:   LD      A,B
        LD      (NVC),A
        LD      A,C
        LD      (VRING),A
        LD      L,C             ; DE = filas * 80
        LD      H,0
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      D,H
        LD      E,L
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,DE
        EX      DE,HL
        LD      IX,VST
        LD      HL,0
VTI1:   LD      (IX+13),L       ; principio del anillo de cada consola
        LD      (IX+14),H
        ADD     HL,DE
        PUSH    DE
        LD      DE,16
        ADD     IX,DE
        POP     DE
        DJNZ    VTI1
        LD      A,(STATON)
        LD      B,A
        LD      A,24
        SUB     B
        LD      (VNR),A
        RET

; VSTIX: IX = estado de la consola D
VSTIX:  LD      A,D
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,A
        ADD     A,VST AND 0FFh
        LD      IXL,A
        LD      IXH,VST SHR 8
        RET

; VROWA: HL = direccion de la fila A (de la pantalla, 0 = la de arriba)
VROWA:  ADD     A,(IX+2)        ; (A puede venir sumado VRING: fila del pasado)
        LD      HL,VRING
        CP      (HL)
        JR      C,VR1
        SUB     (HL)
        CP      (HL)
        JR      C,VR1
        SUB     (HL)
VR1:    LD      L,A
        LD      H,0
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        PUSH    DE
        LD      D,H
        LD      E,L
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,DE           ; * 80
        LD      E,(IX+13)
        LD      D,(IX+14)
        ADD     HL,DE
        POP     DE
        RET

; VCLR: borra la fila A desde la columna E
VCLR:   CALL    VROWA
        LD      A,E
        CP      80
        RET     NC
        ADD     A,L
        LD      L,A
        JR      NC,VCL1
        INC     H
VCL1:   LD      A,80
        SUB     E
        PUSH    HL
        PUSH    AF
        CALL    VCL2            ; los caracteres: espacios
        POP     AF
        POP     HL
        SET     6,H             ; los atributos: 0
        LD      E,0
        JR      VCL3
VCL2:   LD      E,' '
VCL3:   LD      (HL),E
        DEC     A
        RET     Z
        LD      C,A
        LD      B,0
        LD      D,H
        LD      E,L
        INC     DE
        LDIR
        RET

; VQFL: pasa a la pantalla de la consola que se ve lo que espera en VQ
VQFL:   LD      A,(VQN)
        OR      A
        RET     Z
        LD      B,A
        XOR     A
        LD      (VQN),A
        LD      A,(ACTVC)
        LD      D,A
        CALL    VSTIX
        LD      HL,VQ
VQF1:   LD      A,(IX+3)        ; lo comun: caracteres que se ven, fuera de una
        OR      A               ; secuencia ESC, en la fila que ya se conoce:
        JR      NZ,VQS          ; se copian de corrido, sin IX
        OR      (IX+10)
        JR      Z,VQS
        LD      A,(IX+1)
        CP      80
        JR      NC,VQS
        LD      C,A             ; C = columna, DE = donde va
        LD      (VQC0),A
        ADD     A,(IX+8)
        LD      E,A
        LD      A,(IX+9)
        ADC     A,0
        LD      D,A
        LD      (VQD0),DE
VQR:    LD      A,(HL)
        CP      20h
        JR      C,VQRX
        CP      7Fh
        JR      NC,VQRX
        LD      (DE),A
        INC     DE
        INC     HL
        INC     C
        LD      A,C
        CP      80
        JR      Z,VQRE
        DJNZ    VQR
        CALL    VQAT
        RET
VQRE:   CALL    VQAT            ; fin de la fila: lo que siga, uno por uno
        DJNZ    VQF1
        RET
VQRX:   CALL    VQAT
VQS:    LD      C,(HL)
        PUSH    HL
        PUSH    BC
        CALL    VT0
        POP     BC
        POP     HL
        INC     HL
        DJNZ    VQF1
        RET

; VQAT: termina una tanda: columna nueva y el atributo de cada caracter
VQAT:   LD      (IX+1),C
        PUSH    HL
        PUSH    BC
        LD      A,(VQC0)
        LD      B,A
        LD      A,C
        SUB     B
        JR      Z,VQA9
        LD      HL,(VQD0)
        SET     6,H
        LD      E,(IX+15)
        CALL    VCL3
VQA9:   POP     BC
        POP     HL
        RET

; VTPUT: caracter C de la consola D a su pantalla. Entiende lo que mandan los
; programas para un terminal ANSI: CR, LF, BS, TAB y ESC [ ... H f J K A B C D
; (lo demas, como los colores, no cambia el texto y se ignora).
VTPUT:  LD      A,(NVC)
        DEC     A
        CP      D
        RET     C
        CALL    VSTIX
        LD      A,(ACTVC)
        CP      D
        JR      Z,VT0
        LD      (IX+7),1        ; salida que no se vio (linea de estado)
VT0:    LD      A,C
        AND     7Fh
        LD      C,A
        LD      A,(IX+3)
        OR      A
        JP      NZ,VTESC
        LD      A,C
        CP      20h
        JR      NC,VTPR
        CP      1Bh
        JR      Z,VTE1
        CP      0Dh
        JR      Z,VTCR
        CP      0Ah
        JR      Z,VTLF
        CP      08h
        JR      Z,VTBS
        CP      09h
        RET     NZ
        LD      A,(IX+1)        ; TAB
        CP      80
        RET     NC
        ADD     A,8
        AND     0F8h
        CP      80
        JR      C,VTB1
        LD      A,79
        JR      VTB1
VTBS:   LD      A,(IX+1)
        OR      A
        RET     Z
        DEC     A
        CP      79              ; 80 es "al final, falta saltar": va a 78
        JR      NZ,VTB1
        DEC     A
VTB1:   LD      (IX+1),A
        RET
VTE1:   LD      (IX+3),1
        RET
VTCR:   LD      (IX+1),0
        RET
VTPR:   CP      7Fh
        RET     Z
        LD      A,(IX+1)
        CP      80
        JR      C,VTP1
        LD      (IX+1),0        ; salto de linea pendiente
        CALL    VTLF
VTP1:   LD      A,(IX+10)       ; la direccion de la fila, si vale
        OR      A
        JR      Z,VTP3
        LD      L,(IX+8)
        LD      H,(IX+9)
        JR      VTP4
VTP3:   LD      A,(IX+0)
        CALL    VROWA
        LD      (IX+8),L
        LD      (IX+9),H
        LD      (IX+10),1
VTP4:   LD      A,(IX+1)
        ADD     A,L
        LD      L,A
        JR      NC,VTP2
        INC     H
VTP2:   LD      (HL),C
        SET     6,H
        LD      A,(IX+15)
        LD      (HL),A
        INC     (IX+1)
        RET
VTLF:   LD      A,(IX+0)
        INC     A
        LD      HL,VNR
        CP      (HL)
        LD      (IX+10),0
        JR      NC,VTSCR
        LD      (IX+0),A
        RET
VTSCR:  LD      A,(VRING)       ; desplazar: la fila de arriba queda en el
        LD      B,A             ; anillo (historial) y se agrega una en blanco
        LD      A,(IX+2)
        INC     A
        CP      B
        JR      C,VTS1
        XOR     A
VTS1:   LD      (IX+2),A
        LD      A,B
        SUB     (HL)
        CP      (IX+12)
        JR      Z,VTS2
        INC     (IX+12)
VTS2:   LD      A,(HL)
        DEC     A
        LD      E,0
        JP      VCLR
VTESC:  DEC     A
        JR      NZ,VTCSI
        LD      A,C             ; despues de ESC
        CP      '['
        LD      A,0
        JR      NZ,VTE0
        LD      (IX+4),A
        LD      (IX+5),A
        LD      (IX+6),A
        LD      (IX+11),A
        LD      A,2
VTE0:   LD      (IX+3),A
        RET
VTCSI:  LD      A,C             ; ESC [ ...
        SUB     '0'
        CP      10
        JR      NC,VCS1
        LD      B,A             ; digito: al parametro que va (hasta 3)
        CALL    VPARP
        LD      A,(HL)
        CP      25
        RET     NC
        LD      E,A
        ADD     A,A
        ADD     A,A
        ADD     A,E
        ADD     A,A
        ADD     A,B
        LD      (HL),A
        RET
; VPARP: HL -> el parametro A (o el actual con VPARP), en IX+4, IX+5 o IX+11
VPARP:  LD      A,(IX+6)
VPARA:  LD      E,4
        OR      A
        JR      Z,VPA1
        INC     E
        DEC     A
        JR      Z,VPA1
        LD      E,11
VPA1:   PUSH    IX
        POP     HL
        LD      D,0
        ADD     HL,DE
        RET
VCS1:   LD      A,C
        CP      ';'
        JR      NZ,VCS2
        LD      A,(IX+6)
        CP      2
        RET     NC
        INC     (IX+6)
        RET
VCS2:   CP      40h
        RET     C               ; (?, espacios: sigue la secuencia)
        LD      (IX+3),0        ; letra final
        LD      B,(IX+4)
        CP      'H'
        JR      Z,VCUP
        CP      'f'
        JR      Z,VCUP
        CP      'J'
        JR      Z,VED
        CP      'K'
        JP      Z,VEL
        CP      'm'
        JP      Z,VSGR
        SUB     'A'
        CP      4
        RET     NC
        LD      E,A             ; A B C D: B = cuantas (al menos 1)
        LD      A,B
        OR      A
        JR      NZ,VCM1
        INC     A
VCM1:   LD      B,A
        LD      A,E
        OR      A
        JR      Z,VCUU
        DEC     A
        JR      Z,VCUD
        DEC     A
        JR      Z,VCUF
        LD      A,(IX+1)        ; D: izquierda
        CP      80
        JR      C,VCB1
        LD      A,79
VCB1:   SUB     B
        JR      NC,VCB2
        XOR     A
VCB2:   LD      (IX+1),A
        RET
VCUF:   LD      A,(IX+1)
        ADD     A,B
        JR      C,VCF1
        CP      80
        JR      C,VCB2
VCF1:   LD      A,79
        JR      VCB2
VCUU:   LD      A,(IX+0)
        SUB     B
        JR      NC,VCU2
        XOR     A
VCU2:   LD      (IX+0),A
        LD      (IX+10),0
        RET
VCUD:   LD      A,(IX+0)
        ADD     A,B
        LD      HL,VNR
        JR      C,VCD1
        CP      (HL)
        JR      C,VCU2
VCD1:   LD      A,(HL)
        DEC     A
        JR      VCU2
VCUP:   LD      A,B             ; ESC [ fila ; columna H
        OR      A
        JR      Z,VCP1
        DEC     A
VCP1:   LD      HL,VNR
        CP      (HL)
        JR      C,VCP2
        LD      A,(HL)
        DEC     A
VCP2:   LD      (IX+0),A
        LD      (IX+10),0
        LD      A,(IX+5)
        OR      A
        JR      Z,VCP3
        DEC     A
VCP3:   CP      80
        JR      C,VCB2
        JR      VCF1
VED:    LD      A,B             ; J: 0 desde el cursor, 2 todo
        CP      1
        RET     Z
        LD      DE,0
        CP      2
        JR      Z,VED1
        LD      D,(IX+0)
        LD      E,(IX+1)
VED1:   LD      A,D
        PUSH    DE
        CALL    VCLR
        POP     DE
        LD      E,0
        INC     D
        LD      A,(VNR)
        CP      D
        JR      NZ,VED1
        RET
VEL:    LD      A,B             ; K: 0 desde el cursor, 2 la linea
        CP      1
        RET     Z
        LD      E,(IX+1)
        CP      2
        JR      NZ,VEL1
        LD      E,0
VEL1:   LD      A,(IX+0)
        JP      VCLR

; VSGR: ESC [ ... m: cambia el atributo actual de la consola
VSGR:   LD      A,(IX+6)
        INC     A
        LD      B,A
        LD      C,0
VSG1:   LD      A,C
        CALL    VPARA
        LD      A,(HL)
        CALL    VSG
        INC     C
        DJNZ    VSG1
        RET
VSG:    LD      D,(IX+15)
        OR      A
        JR      NZ,VSG2
        LD      D,A
VSG2:   CP      1
        JR      NZ,$+4
        SET     0,D
        CP      4
        JR      NZ,$+4
        SET     1,D
        CP      5
        JR      NZ,$+4
        SET     2,D
        CP      7
        JR      NZ,$+4
        SET     3,D
        CP      22
        JR      NZ,$+4
        RES     0,D
        CP      24
        JR      NZ,$+4
        RES     1,D
        CP      25
        JR      NZ,$+4
        RES     2,D
        CP      27
        JR      NZ,$+4
        RES     3,D
        CP      39
        JR      NZ,VSG3
        LD      A,D
        AND     0Fh
        LD      D,A
        JR      VSG9
VSG3:   SUB     30
        CP      8
        JR      NC,VSG9
        RLCA
        RLCA
        RLCA
        RLCA
        OR      80h
        LD      E,A
        LD      A,D
        AND     0Fh
        OR      E
        LD      D,A
VSG9:   LD      (IX+15),D
        RET

; KEYIN: caracter C de la SIO A. Teclas del XIOS (con cualquier modificador m):
;   ESC [ 1 ; m P..S   Ctrl-F1..F4: elegir la consola
;   ESC [ 5 ; m ~      Shift-RePag: mirar 12 filas hacia atras
;   ESC [ 6 ; m ~      Shift-AvPag: 12 hacia adelante
;   Ctrl-\ 1..4, Ctrl-\ U, Ctrl-\ D: lo mismo; Ctrl-\ Ctrl-\ manda un Ctrl-\.
; Lo demas va al bufer de la consola que se ve.
KEYIN:  LD      A,(RAWA)        ; modo crudo (H:XFER): todo tal cual al anillo
        DEC     A
        JP      Z,RAWPUT
        LD      A,(KN)
        CP      10
        JR      Z,KI10
        OR      A
        JP      NZ,KI1
        LD      A,C
        CP      1Bh
        JR      Z,KIST
        CP      1Ch
        JR      NZ,KIPUT
        LD      A,10
        LD      (KN),A
        RET
KIST:   LD      (KBUF),A
        LD      A,1
        LD      (KN),A
KITMO:  LD      A,6             ; 6 tics para que llegue el resto
        LD      (KTMO),A
        RET
KI10:   XOR     A
        LD      (KN),A
        LD      A,(NVC)
        LD      B,A
        LD      A,C
        SUB     '1'
        CP      B
        JP      C,VSW
        LD      A,C
        OR      20h
        CP      'u'
        JP      Z,VSUP
        CP      'd'
        JP      Z,VSDN
        LD      A,C
        CP      1Ch
        JR      Z,KIPUT
        PUSH    BC
        LD      C,1Ch
        CALL    KIPUT
        POP     BC
KIPUT:  LD      A,(VIEWING)     ; al bufer de la consola que se ve (si se miraba
        OR      A               ; hacia atras, se vuelve al dia)
        CALL    NZ,VSNAP
        LD      A,(ACTVC)
        LD      D,A
        LD      HL,RXCNT
        ADD     A,L
        LD      L,A
        JR      NC,KIP1
        INC     H
KIP1:   LD      A,(HL)
        CP      63
        RET     NC              ; lleno: se pierde
        INC     (HL)
        LD      A,D
        ADD     A,A
        ADD     A,(VRXP AND 0FFh)+1
        LD      L,A
        LD      H,VRXP SHR 8
        LD      A,(HL)          ; cola
        LD      E,A
        INC     A
        AND     3Fh
        LD      (HL),A
        CALL    VRXA
        LD      (HL),C
        RET
; VRXA: HL = VRXB + D * 64 + E
VRXA:   LD      A,D
        AND     3
        RRCA
        RRCA
        ADD     A,E
        LD      L,A
        LD      A,D
        RRCA
        RRCA
        AND     1
        ADD     A,VRXB SHR 8
        LD      H,A
        RET
KI1:    LD      E,A             ; E = KN (1-6): ESC [ parametros final
        LD      D,0
        LD      HL,KBUF
        ADD     HL,DE
        LD      (HL),C
        DEC     A
        JR      NZ,KI2
        LD      A,C
        CP      '['
        JP      NZ,KIBAD
KINX:   LD      HL,KN
        INC     (HL)
        JP      KITMO
KI2:    LD      A,C
        CP      ';'
        JR      Z,KI3
        SUB     '0'
        CP      10
        JR      NC,KI4
KI3:    LD      A,E
        CP      6
        JP      NC,KIBAD
        JR      KINX
KI4:    LD      A,C             ; letra final: ESC [ x ; m f
        CP      40h
        JP      C,KIBAD
        LD      A,E
        CP      6
        JR      Z,KI7
        CP      5
        JP      NZ,KIBAD
        LD      A,(KBUF+3)
        CP      ';'
        JP      NZ,KIBAD
        LD      A,(KBUF+4)
        SUB     '2'
        CP      7
        JP      NC,KIBAD
        LD      A,(KBUF+2)
        CP      '1'
        JR      NZ,KI5
        LD      A,C
        SUB     'P'
        CP      4
        JP      NC,KIBAD
        CALL    KCLR
        JP      VSW
KI5:    LD      B,A
        LD      A,C
        CP      '~'
        JP      NZ,KIBAD
        LD      A,B
        CP      '5'
        JR      Z,KI6
        CP      '6'
        JP      NZ,KIBAD
        CALL    KCLR
        JP      VSDN
KI6:    CALL    KCLR
        JP      VSUP
KI7:    LD      HL,(KBUF+2)     ; ESC [ 1 5 ; m ~ : Ctrl-F5 (la consola 4)
        LD      A,L
        CP      '1'
        JP      NZ,KIBAD
        LD      A,H
        CP      '5'
        JP      NZ,KIBAD
        LD      A,(KBUF+4)
        CP      ';'
        JP      NZ,KIBAD
        LD      A,(KBUF+5)
        SUB     '2'
        CP      7
        JP      NC,KIBAD
        LD      A,C
        CP      '~'
        JP      NZ,KIBAD
        LD      A,(NVC)
        CP      5
        JP      NZ,KIBAD
        CALL    KCLR
        LD      A,4
        JP      VSW
KCLR:   LD      B,A
        XOR     A
        LD      (KN),A
        LD      (KTMO),A
        LD      A,B
        RET
KIBAD:  LD      A,C             ; no era: lo guardado y este caracter (si es
        CP      1Bh             ; otro ESC, empieza otra secuencia)
        LD      A,E
        JR      NZ,KIB1
        CALL    KFL1
        LD      A,1Bh
        JP      KIST
KIB1:   INC     A
        JR      KFL1
; KFLUSH: se acabo el tiempo: lo guardado va al bufer como se tecleo
KFLUSH: LD      A,(KN)
        CP      10
        RET     Z
        OR      A
        RET     Z
KFL1:   LD      B,A
        XOR     A
        LD      (KN),A
        LD      (KTMO),A
        LD      HL,KBUF
KFL2:   LD      C,(HL)
        PUSH    HL
        PUSH    BC
        CALL    KIPUT
        POP     BC
        POP     HL
        INC     HL
        DJNZ    KFL2
        RET

; VRXGET: A = el siguiente caracter tecleado en la consola D (hay)
VRXGET: LD      A,D
        ADD     A,A
        ADD     A,VRXP AND 0FFh
        LD      L,A
        LD      H,VRXP SHR 8
        LD      A,(HL)          ; cabeza
        LD      E,A
        INC     A
        AND     3Fh
        LD      (HL),A
        CALL    VRXA
        LD      C,(HL)
        LD      HL,RXCNT
        LD      E,D
        LD      D,0
        ADD     HL,DE
        DEC     (HL)
        LD      HL,(RAWH)       ; queda algo sin pasar (se paro con el bufer
        LD      DE,(RAWT)       ; lleno): a KDRAIN otra vez
        OR      A
        SBC     HL,DE
        JR      Z,VRG1
        LD      A,1
        LD      (RXPEND),A
VRG1:   CALL    RTSON
        LD      A,C
        RET

; LSTPB: el caracter C al anillo de la impresora (pagina LSTPG, un momento en
; la ventana 0). Z si esta lleno.
LSTPB:  LD      HL,(LSTT)
        INC     HL
        LD      A,H
        AND     3Fh
        LD      H,A
        LD      DE,(LSTH)
        OR      A
        SBC     HL,DE
        RET     Z
        ADD     HL,DE
        LD      DE,(LSTT)
        LD      (LSTT),HL
        LD      A,(LSTPG)
        OUT     (PGPORT),A
        EX      DE,HL
        LD      (HL),C
        LD      A,(VTPG)        ; (BKCALL tiene VTPG en la ventana 0)
        OUT     (PGPORT),A
        OR      0FFh
        RET

; KDONE: un caracter de RAWQ por KEYIN. Carry si no hay o si el bufer de la
; consola que se ve esta casi lleno (queda en RAWQ hasta que lean: VRXGET).
KDONE:  LD      A,(RAWA)        ; modo crudo: el anillo es del programa
        OR      A
        JR      NZ,KDN9
        LD      A,(ACTVC)
        LD      HL,RXCNT
        ADD     A,L
        LD      L,A
        JR      NC,KDN1
        INC     H
KDN1:   LD      A,(HL)
        CP      60
        JR      NC,KDN9
        CALL    RAWGET
        JR      C,KDN9
        LD      C,A
        CALL    RTSOFF          ; mientras KEYIN trabaja (mas que un caracter a
        CALL    KEYIN           ; 115200), con --flow h el PC espera
        CALL    RTSON
        OR      A               ; NC: hubo uno
        RET
KDN9:   XOR     A
        LD      (RXPEND),A
        SCF
        RET

; ZRAWB: servicio 41 con B = 0 (prender el modo crudo en la consola C, que
; tiene que ser la que se ve) o 1 (apagarlo y redibujar). A = 0 bien, FF no.
ZRAWB:  LD      A,B
        OR      A
        JR      NZ,ZRB1
        LD      A,C
        CP      4
        JR      C,ZRB0
        LD      A,(SIOBM)       ; consola 4
        OR      A
        LD      A,2             ; la SIO B
        JR      Z,ZRB0B
        LD      A,(SIOBM)
        DEC     A
        JR      Z,ZRBE          ; CONSOLE4=OFF
        LD      A,4             ; virtual
ZRB0:   LD      HL,ACTVC
        CP      (HL)
        JR      NZ,ZRBE
        LD      A,1
ZRB0B:  LD      (RAWA),A
        CALL    RAWCLR          ; anillo vacio
        XOR     A
        RET
ZRBE:   LD      A,0FFh
        RET
ZRB1:   LD      A,(RAWA)
        DEC     A
        LD      A,0
        LD      (RAWA),A
        RET     NZ
        CALL    VSNAP
        CALL    TXSTA
        XOR     A
        RET

;==========================================================================
; ITXF: transmisor vacio de la SIO A, camino corto (unos 220 ciclos en vez de
; 500). Se copia a FE00 al arrancar, porque la memoria comun del SPR esta
; llena. Con alguien esperando lugar, o con el bufer vacio y algo por generar
; (redibujo, linea de estado), sigue el camino de siempre (ITXA).
ITXFS:
        .phase  ITXF
        PUSH    AF
        PUSH    HL
        LD      A,(TXA+3)       ; alguien espera lugar: el camino de siempre
        OR      A
        JR      NZ,ITXF9
        LD      HL,(TXA)        ; L = cabeza, H = cola
        LD      A,L
        CP      H
        JR      Z,ITXF8         ; vacio
        INC     A
        AND     TXMSK
        LD      (TXA),A
        LD      A,L             ; bufer[cabeza] (no cruza de pagina)
        ADD     A,(TXA+6) AND 0FFh
        LD      L,A
        LD      H,TXA SHR 8
        LD      A,(HL)
        OUT     (SIOAD),A
ITXF7:  POP     HL
        POP     AF
        EI
        RETI
ITXF8:  LD      A,(GENACT)      ; vacio y sin redibujo ni linea de estado
        LD      HL,STATDUE      ; pendientes: el transmisor se para
        OR      (HL)
        JR      NZ,ITXF9
        LD      (TXA+2),A
        LD      A,28h           ; reponer "Tx int pending"
        OUT     (SIOAC),A
        JR      ITXF7
ITXF9:  POP     HL
        POP     AF
        JP      ITXA
        .dephase
ITXFE:
        IF      ITXF+ITXFE-ITXFS > RXB
        .error  ITXF no cabe antes de RXB
        ENDIF

; RAWPUT / RAWGET: el anillo del modo crudo (256 bytes). RAWGET: A = el byte,
; carry si no hay.
RAWCLR: LD      HL,0
        LD      (RAWH),HL
        LD      (RAWT),HL
        RET
RAWPUT: LD      HL,(RAWT)       ; (la SIO B en modo crudo)
        PUSH    HL
        INC     HL
        LD      A,H
        AND     1
        LD      H,A
        LD      DE,(RAWH)
        OR      A
        SBC     HL,DE
        ADD     HL,DE
        POP     DE
        RET     Z               ; lleno: se pierde
        LD      (RAWT),HL
        LD      HL,RAWQ
        ADD     HL,DE
        LD      (HL),C
        RET
RAWGET: CALL    RTSON           ; el programa lee: el PC puede seguir mandando
        LD      HL,(RAWH)
        LD      DE,(RAWT)
        OR      A
        SBC     HL,DE
        SCF
        RET     Z
        ADD     HL,DE           ; HL = cabeza
        PUSH    HL
        INC     HL
        LD      A,H
        AND     1
        LD      H,A
        LD      (RAWH),HL
        EX      DE,HL           ; menos de 256 en RAWQ: RTS puede volver
        LD      HL,(RAWT)
        OR      A
        SBC     HL,DE
        BIT     0,H
        JR      NZ,RWG1
        XOR     A
        LD      (RTSHLD),A
RWG1:   POP     DE
        LD      HL,RAWQ
        ADD     HL,DE
        LD      A,(HL)
        OR      A               ; NC
        RET

; VSUP / VSDN: mirar 12 filas mas atras / mas adelante en la consola que se ve
VSUP:   LD      A,(ACTVC)
        LD      D,A
        CALL    VSTIX
        LD      A,(VIEWOFS)
        ADD     A,12
        CP      (IX+12)
        JR      C,VSET
        LD      A,(IX+12)
        JR      VSET
VSDN:   LD      A,(VIEWOFS)
        SUB     12
        JR      NC,VSET
        XOR     A
VSET:   LD      HL,VIEWOFS
        CP      (HL)
        RET     Z
        LD      (HL),A
        LD      (VIEWING),A
        JR      VSNAP2

; VSW: se ve la consola A: se vacia lo que faltaba mandar por la SIO A y se
; redibuja su pantalla (lo tecleado en cada consola queda en la suya)
VSWE:   LD      A,E             ; (servicio 40 de ZIOS: H:VC)
VSW:    LD      E,A
        LD      A,(NVC)
        DEC     A
        CP      E
        RET     C
        LD      A,(ACTVC)
        CP      E
        RET     Z
        PUSH    DE
        CALL    VQFL
        POP     DE
        LD      D,E
        LD      A,D
        LD      (ACTVC),A
        CALL    VSTIX
        LD      (IX+7),0
        LD      HL,0
        LD      (LASTPD),HL
VSNAP:  CALL    RTSON           ; (al salir del modo crudo, RTS prendido)
        XOR     A               ; (de aqui: volver a la pantalla al dia)
        LD      (VIEWOFS),A
        LD      (VIEWING),A
VSNAP2: LD      HL,SWCNT        ; redibujar
        INC     (HL)
        LD      A,(TXA+1)
        LD      (TXA),A
VSW1:   LD      A,1
        LD      (GENACT),A
        XOR     A
        LD      (GSTG),A
        LD      (GCNT),A
        SCF
        RET

; GENFILL: llena el bufer de salida de la SIO A con el redibujo o la linea de
; estado (que empieza aqui si toca)
GENFILL: CALL   VQFL
        LD      A,(GENACT)
        OR      A
        JR      NZ,GF1
        LD      A,(RAWA)        ; (en modo crudo, sin linea de estado)
        OR      A
        CALL    Z,STSTART
        LD      A,(GENACT)
        OR      A
        RET     Z
GF1:    LD      A,(TXA+1)       ; cola
        LD      E,A
        INC     A
        AND     TXMSK
        LD      HL,TXA
        CP      (HL)
        RET     Z               ; lleno
        LD      B,A
        LD      A,(GCNT)
        OR      A
        JR      Z,GF2
        DEC     A
        LD      (GCNT),A
        LD      HL,(GPTR)
        LD      C,(HL)
        INC     HL
        LD      (GPTR),HL
        LD      A,B
        LD      (TXA+1),A
        LD      D,0
        LD      HL,TXA+6
        ADD     HL,DE
        LD      (HL),C
        JR      GF1
GF2:    CALL    GCHUNK
        JR      NC,GF1
        LD      A,(GENACT)      ; termino: despues de redibujar, la linea de estado
        DEC     A
        LD      A,(STATON)
        JR      NZ,GF3
        LD      (STATDUE),A
GF3:    XOR     A
        LD      (GENACT),A
        RET

; GCHUNK: el siguiente trozo del redibujo en GBUF. Carry: no hay mas.
GCHUNK: LD      A,(GENACT)
        CP      2
        SCF
        RET     Z               ; la linea de estado es un solo trozo
        LD      A,(ACTVC)
        LD      D,A
        CALL    VSTIX
        LD      DE,GBUF
        LD      HL,GSTG
        LD      A,(HL)
        INC     (HL)
        OR      A
        JR      NZ,GC1
        XOR     A
        LD      (GCOL),A
        LD      (GATTR),A
        LD      HL,GPRE         ; 0: cancelar, borrar la pantalla
        CALL    GSTR
        LD      A,(STATON)
        OR      A
        LD      HL,GREG
        CALL    NZ,GSTR
        LD      HL,GCLS
        CALL    GSTR
        JP      GCEND
GC1:    DEC     A               ; 1..VNR: las filas
        LD      HL,VNR
        CP      (HL)
        JP      NC,GC5
        LD      B,A
        LD      A,(VIEWOFS)     ; mirando hacia atras: filas del pasado
        NEG
        ADD     A,B
        LD      HL,VRING
        ADD     A,(HL)
        CALL    VROWA           ; HL = la fila
        LD      A,(GCOL)
        OR      A
        JR      NZ,GC3
        PUSH    HL              ; al empezar la fila: su largo, sin los espacios
        LD      DE,79           ; sin atributo del final
        ADD     HL,DE
        LD      C,80
GC2:    LD      A,(HL)
        CP      ' '
        JR      NZ,GC2B
        SET     6,H
        LD      A,(HL)
        RES     6,H
        OR      A
        JR      NZ,GC2B
        DEC     HL
        DEC     C
        JR      NZ,GC2
GC2B:   LD      A,C
        LD      (GRLEN),A
        POP     HL
GC3:    LD      A,(GCOL)        ; desde donde iba
        LD      E,A
        LD      D,0
        ADD     HL,DE
        LD      DE,GBUF
GC3B:   LD      A,(GRLEN)
        LD      C,A
        LD      A,(GCOL)
        CP      C
        JR      NC,GC4          ; fin de la fila
        LD      A,E
        CP      (GBUF+100) AND 0FFh
        JR      NC,GC3E         ; GBUF lleno: lo demas en el trozo siguiente
        SET     6,H             ; atributo distinto: mandarlo
        LD      A,(HL)
        RES     6,H
        LD      C,A
        LD      A,(GATTR)
        CP      C
        JR      Z,GC3C
        LD      A,C
        LD      (GATTR),A
        CALL    GSGR
GC3C:   LD      A,(HL)
        CALL    GPUT
        INC     HL
        LD      A,(GCOL)
        INC     A
        LD      (GCOL),A
        JR      GC3B
GC3E:   LD      HL,GSTG         ; la misma fila otra vez
        DEC     (HL)
        JP      GCEND
GC4:    XOR     A
        LD      (GCOL),A
        LD      A,(VNR)
        DEC     A
        CP      B
        JP      Z,GCEND
        LD      A,13
        CALL    GPUT
        LD      A,10
        CALL    GPUT
        JP      GCEND
GC5:    SCF
        RET     NZ              ; VNR + 1: el cursor
        LD      DE,GBUF
        LD      A,(VIEWOFS)     ; mirando hacia atras: sin cursor
        OR      A
        JR      Z,GC5B
        LD      HL,GHIDE
        CALL    GSTR
        JP      GCEND
GC5B:   LD      A,(IX+15)       ; el atributo actual de la consola
        CALL    GSGR
        LD      HL,GCUR
        CALL    GSTR
        LD      A,(IX+0)
        INC     A
        CALL    GDEC
        LD      A,';'
        CALL    GPUT
        LD      A,(IX+1)
        CP      80
        JR      NC,GC6
        INC     A
GC6:    CALL    GDEC
        LD      A,'H'
        CALL    GPUT
GCEND:  EX      DE,HL           ; GCNT = lo que se escribio en GBUF
        LD      DE,GBUF
        LD      (GPTR),DE
        OR      A
        SBC     HL,DE
        LD      A,L
        LD      (GCNT),A
        OR      A
        RET

; GSGR: ESC [ 0 ; ... m del atributo A
GSGR:   PUSH    HL
        PUSH    BC
        LD      C,A
        LD      HL,GSGR0
        CALL    GSTR
        LD      HL,GSGRT
        LD      B,4
GSG1:   RRC     C
        JR      NC,GSG2
        LD      A,';'
        CALL    GPUT
        LD      A,(HL)
        CALL    GPUT
GSG2:   INC     HL
        DJNZ    GSG1
        BIT     3,C             ; (C ya giro 4: el bit 7 quedo en el 3)
        JR      Z,GSG3
        LD      A,';'
        CALL    GPUT
        LD      A,'3'
        CALL    GPUT
        LD      A,C
        AND     7
        ADD     A,'0'
        CALL    GPUT
GSG3:   LD      A,'m'
        CALL    GPUT
        POP     BC
        POP     HL
        RET
GSGR0:  DEFB    1Bh,'[0',0
GSGRT:  DEFB    '1457'

GSTR:   LD      A,(HL)          ; copia el texto HL (termina en 0) a DE
        OR      A
        RET     Z
        CALL    GPUT
        INC     HL
        JR      GSTR
GPUT:   LD      (DE),A
        INC     DE
        RET
GDEC:   LD      C,'0'-1         ; A (1-99) en decimal
GD1:    INC     C
        SUB     10
        JR      NC,GD1
        ADD     A,'0'+10
        LD      B,A
        LD      A,C
        CP      '0'
        CALL    NZ,GPUT
        LD      A,B
        JR      GPUT
GBCD:   PUSH    AF              ; A en BCD, dos cifras
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    GNIB
        POP     AF
GNIB:   AND     0Fh
        ADD     A,'0'
        JR      GPUT

GPRE:   DEFB    18h,1Bh,'[0m',1Bh,'[?25h',0 ; CAN: termina una secuencia a medias
GHIDE:  DEFB    1Bh,'[?25l',0
GREG:   DEFB    1Bh,'[1;23r',0          ; las filas 1-23 se desplazan
GCLS:   DEFB    1Bh,'[H',1Bh,'[2J',0
GCUR:   DEFB    1Bh,'[',0

; STSTART: arma la linea de estado (fila 24) en GBUF, si la consola que se ve
; no esta a media secuencia ESC
STSTART: LD     A,(ACTVC)
        LD      D,A
        CALL    VSTIX
        LD      A,(IX+3)
        OR      A
        RET     NZ
        LD      (STATDUE),A
        LD      DE,GBUF
        LD      HL,STPRE
        CALL    GSTR
        LD      B,0             ; [1] 2* 3  4 : la que se ve y las que tienen
STS1:   LD      A,(ACTVC)       ; salida sin ver
        CP      B
        LD      A,' '
        JR      NZ,STS2
        LD      A,'['
STS2:   CALL    GPUT
        LD      A,B
        ADD     A,'1'
        CALL    GPUT
        PUSH    DE
        LD      D,B
        CALL    VSTIX
        POP     DE
        LD      A,(ACTVC)
        CP      B
        LD      A,']'
        JR      Z,STS3
        LD      A,(IX+7)
        OR      A
        LD      A,'*'
        JR      NZ,STS3
        LD      A,' '
STS3:   CALL    GPUT
        INC     B
        LD      A,(NVC)
        CP      B
        JR      NZ,STS1
        LD      HL,STSEP
        CALL    GSTR
        LD      A,(VIEWOFS)     ; mirando hacia atras: HIST -n
        OR      A
        JR      Z,STS6
        LD      HL,STHIST
        CALL    GSTR
        LD      A,(VIEWOFS)
        CALL    GDEC
        LD      A,' '
        CALL    GPUT
        CALL    GPUT
        JR      STS8
STS6:   LD      HL,(LASTPD)     ; el proceso que escribio ultimo en esta consola
        LD      A,H
        CP      0C0h            ; (su descriptor en la memoria comun)
        JR      NC,STS6B
        LD      HL,STNONE
STS6B:  LD      BC,6
        ADD     HL,BC
        LD      B,8
STS7:   LD      A,(HL)
        AND     7Fh
        CP      ' '
        JR      NC,STS7B
        LD      A,' '
STS7B:  CALL    GPUT
        INC     HL
        DJNZ    STS7
STS8:   LD      HL,STCPU        ; CPU ocupada en el ultimo segundo
        CALL    GSTR
        LD      A,(IDLES)
        LD      C,A
        LD      A,TPS
        SUB     C
        JR      NC,STS9
        XOR     A
STS9:   LD      L,A             ; * 100 / TPS
        LD      H,0
        LD      B,H
        LD      C,L
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,BC           ; (B = 0) * 5
        LD      BC,-3
        LD      A,-1
STS10:  INC     A
        ADD     HL,BC
        JR      C,STS10         ; / 3
        LD      C,A             ; tres columnas, a la derecha
        CP      100
        JR      C,STS11
        LD      HL,ST100
        CALL    GSTR
        JR      STS12
STS11:  LD      A,' '
        CALL    GPUT
        LD      A,C
        CP      10
        JR      NC,STS11B
        LD      A,' '
        CALL    GPUT
STS11B: LD      A,C
        CALL    GDEC
STS12:  LD      HL,STPCT
        CALL    GSTR
        PUSH    DE              ; la fecha: se calcula cuando cambia el dia
        CALL    TODADR
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        PUSH    HL
        EX      DE,HL
        LD      DE,(STDAY)
        OR      A
        SBC     HL,DE
        ADD     HL,DE
        JR      Z,STS4
        LD      (STDAY),HL
        CALL    DAY2YMD
STS4:   POP     HL
        POP     DE
        PUSH    HL
        LD      A,(DDOW)
        DEC     A
        LD      C,A
        ADD     A,A
        ADD     A,C
        LD      C,A
        LD      B,0
        LD      HL,STDOW
        ADD     HL,BC
        LD      BC,3
        LDIR
        LD      HL,ST20
        CALL    GSTR
        LD      A,(DYEAR)
        CALL    GBCD
        LD      A,'-'
        CALL    GPUT
        LD      A,(DMON)
        CALL    GBCD
        LD      A,'-'
        CALL    GPUT
        LD      A,(DDATE)
        CALL    GBCD
        POP     HL              ; hora, minuto, segundo (BCD)
        LD      B,3
        LD      C,' '
STS5:   LD      A,C
        CALL    GPUT
        LD      A,(HL)
        CALL    GBCD
        INC     HL
        LD      C,':'
        DJNZ    STS5
        LD      HL,STFIN
        CALL    GSTR
        LD      A,2
        LD      (GENACT),A
        JP      GCEND
STPRE:  DEFB    1Bh,'7',1Bh,'[24;1H',1Bh,'[7m ZEPHYRUS 1.4 | ',0
STSEP:  DEFB    ' | ',0
STHIST: DEFB    'HIST -',0
STNONE: DEFB    0,0,0,0,0,0,'        '
STCPU:  DEFB    ' | CPU',0
ST100:  DEFB    ' 100',0
STPCT:  DEFB    '% | ',0
ST20:   DEFB    ' 20',0
STFIN:  DEFB    ' ',1Bh,'[0m',1Bh,'[K',1Bh,'8',0
STDOW:  DEFB    'SunMonTueWedThuFriSat'

; ------------------------------------------------------------- STARTUP.SUB
; STFIND: busca STARTUP.SUB en el usuario 0 de A: leyendo el directorio con
; ZIOS (todavia esta debajo). Si esta, SYSINIT deja "SUBMIT STARTUP" escrito en
; la consola 0, como si se hubiera tecleado: se ejecuta al aparecer 0A>.
STFIND: XOR     A
        LD      (CFOK),A
        LD      (STATON),A
        LD      (CFBW4),A
        LD      (CFBW4+2),A
        LD      (STOK),A
        LD      (STSUB),A
        LD      (STREC),A
        LD      (LSTMD),A
        LD      H,A
        LD      L,A
        LD      (CFBLK),HL
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
        LD      DE,STNAME
        CALL    STCMP
        JR      NZ,STF2B
        LD      A,1
        LD      (STSUB),A
STF2B:  POP     HL
        PUSH    HL
        LD      DE,CFNAME       ; A:MPM.CFG, su primera extension
        CALL    STCMP
        JR      NZ,STF4
        LD      A,(HL)          ; HL -> extension (byte 12)
        OR      A
        JR      NZ,STF4
        LD      DE,4            ; byte 16: primer bloque
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        LD      (CFBLK),DE
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
; A:MPM.CFG: sus primeros 4 registros (512 bytes) a CFGBUF. El bloque es de
; 2 KB y empieza despues de la pista 1: registro = 512 + bloque * 16.
        LD      HL,(CFBLK)
        LD      A,H
        OR      L
        RET     Z
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      DE,512
        ADD     HL,DE
        LD      (CFREC),HL
        LD      HL,CFGBUF
        LD      B,4
CFR1:   PUSH    BC
        PUSH    HL
        LD      C,12            ; DMA de ZIOS
        CALL    ZIOS
        LD      DE,(CFREC)
        LD      HL,0
        LD      C,17
        CALL    ZIOS
        POP     HL
        POP     BC
        OR      A
        JR      NZ,CFR2         ; no hay mas: lo leido alcanza
        LD      DE,128
        ADD     HL,DE
        LD      DE,(CFREC)
        INC     DE
        LD      (CFREC),DE
        DJNZ    CFR1
CFR2:   LD      (HL),1Ah        ; fin
        LD      A,1
        LD      (CFOK),A
        RET

; CFGPRS: lee la configuracion de CFGBUF (despues del mapa de ZIOS). Lineas:
;   LST=B | LST=archivo        STATUS=ON | STATUS=OFF
;   BAUD A=9600                DRIVE C=SD0:12 | RAM | FLASH | OFF
; Lo que empieza con ; o no se entiende se salta.
CFGPRS: LD      A,(CFOK)
        OR      A
        RET     Z
        LD      HL,CFGBUF
CP0:    CALL    SKIPSP
        LD      A,(HL)
        CP      1Ah
        RET     Z
        OR      A
        RET     Z
        CP      ' '
        JR      C,CPNX          ; CR, LF
        LD      DE,KLST
        CALL    KWMAT
        JR      Z,DOLST
        LD      DE,KSTAT
        CALL    KWMAT
        JR      Z,DOSTAT
        LD      DE,KBAUD
        CALL    KWMAT
        JP      Z,DOBAUD
        LD      DE,KDRV
        CALL    KWMAT
        JP      Z,DODRV
        LD      DE,KCON4
        CALL    KWMAT
        JR      Z,DOCON4
CPNL:   LD      A,(HL)          ; al final de la linea
        CP      1Ah
        RET     Z
        OR      A
        RET     Z
        INC     HL
        CP      10
        JR      NZ,CPNL
        JR      CP0
CPNX:   INC     HL
        JR      CP0
DOLST:  LD      A,(HL)          ; LST=B: SIO B; otra cosa: un archivo
        AND     5Fh
        CP      'B'
        JR      NZ,DOL1
        INC     HL
        LD      A,(HL)
        DEC     HL
        CP      '!'
        LD      A,0
        JR      C,DOL2
DOL1:   LD      A,1
DOL2:   LD      (LSTMD),A
        JR      CPNL
DOCON4: LD      DE,KOFF         ; CONSOLE4=B | OFF | VIRTUAL
        CALL    KWMAT
        LD      A,1
        JR      Z,DOC41
        LD      DE,KVIRT
        CALL    KWMAT
        LD      A,2
        JR      Z,DOC41
        XOR     A
DOC41:  LD      (SIOBM),A
        JR      CPNL
DOSTAT: LD      DE,KON
        CALL    KWMAT
        LD      A,0
        JR      NZ,DOS1
        INC     A
DOS1:   LD      (STATON),A
        JR      CPNL
; BAUD A=9600
DOBAUD: CALL    SKIPSP
        LD      A,(HL)
        AND     5Fh
        SUB     'A'
        CP      2
        JR      NC,CPNL
        LD      (CFDRV),A       ; (el canal)
        INC     HL
        CALL    SKIPSP
        LD      A,(HL)
        CP      '='
        JR      NZ,CPNL
        INC     HL
        CALL    SKIPSP
        PUSH    HL
        LD      DE,TASAS
DB1:    LD      A,(DE)
        OR      A
        JR      Z,DB9           ; no esta
        POP     HL
        PUSH    HL
        CALL    KWMAT0          ; DE -> nombre (termina en 0)
        JR      Z,DB2
DB1B:   LD      A,(DE)          ; a la entrada siguiente
        INC     DE
        OR      A
        JR      NZ,DB1B
        INC     DE
        INC     DE
        JR      DB1
DB2:    LD      A,(HL)          ; la palabra termino?
        CP      '!'
        JR      NC,DB1B
        INC     DE              ; DE -> WR4, TC
        POP     AF              ; (HL guardado)
        PUSH    HL
        LD      HL,CFBW4
        LD      A,(CFDRV)
        ADD     A,A             ; 2 bytes por canal
        LD      C,A
        LD      B,0
        ADD     HL,BC
        LD      A,(DE)
        LD      (HL),A
        INC     HL
        INC     DE
        LD      A,(DE)
        LD      (HL),A
DB9:    POP     HL
        JP      CPNL
; DRIVE C=SD0:12
DODRV:  CALL    SKIPSP
        LD      A,(HL)
        AND     5Fh
        SUB     'A'
        CP      NDRV
        JP      NC,CPNL
        LD      (CFDRV),A
        INC     HL
        CALL    SKIPSP
        LD      A,(HL)
        CP      ':'
        JR      NZ,DD0
        INC     HL
DD0:    CALL    SKIPSP
        LD      A,(HL)
        CP      '='
        JP      NZ,CPNL
        INC     HL
        CALL    SKIPSP
        LD      DE,KOFF
        CALL    KWMAT
        LD      B,0FFh
        JR      Z,DD5
        LD      DE,KRAM
        CALL    KWMAT
        LD      B,2
        JR      Z,DD5
        LD      DE,KFLASH
        CALL    KWMAT
        LD      B,3
        JR      Z,DD5
        LD      DE,KSD
        CALL    KWMAT
        JP      NZ,CPNL
        LD      A,(HL)          ; SD0: o SD1:
        SUB     '0'
        CP      2
        JP      NC,CPNL
        LD      B,A
        INC     HL
        LD      A,(HL)
        CP      ':'
        JP      NZ,CPNL
        INC     HL
        PUSH    BC
        CALL    DECNUM          ; DE = disco virtual
        POP     BC
        JP      NZ,CPNL
        PUSH    HL
        EX      DE,HL           ; DMW = disco * 32
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        EX      DE,HL
        LD      A,(CFDRV)
        LD      L,A
        LD      H,0
        ADD     HL,HL
        PUSH    BC
        LD      BC,DMW
        ADD     HL,BC
        POP     BC
        LD      (HL),E
        INC     HL
        LD      (HL),D
        POP     HL
DD5:    PUSH    HL
        LD      A,(CFDRV)
        LD      E,A
        LD      D,0
        LD      HL,DCARD
        ADD     HL,DE
        LD      (HL),B
        POP     HL
        JP      CPNL
; DECNUM: numero decimal en HL -> DE (hasta 65535). NZ si no hay digitos.
DECNUM: LD      DE,0
        LD      A,(HL)
        SUB     '0'
        CP      10
        JR      NC,DN9
DN1:    LD      A,(HL)
        SUB     '0'
        CP      10
        JR      NC,DN8
        PUSH    HL
        LD      H,D             ; DE = DE * 10 + A
        LD      L,E
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,DE
        ADD     HL,HL
        LD      E,A
        LD      D,0
        ADD     HL,DE
        EX      DE,HL
        POP     HL
        INC     HL
        JR      DN1
DN8:    XOR     A
        RET
DN9:    OR      1
        RET
SKIPSP: LD      A,(HL)
        CP      ' '
        JR      Z,SK1
        CP      9
        RET     NZ
SK1:    INC     HL
        JR      SKIPSP
; KWMAT: Z si en HL esta la palabra DE (mayusculas, termina en 0); HL queda
; despues de ella. NZ: HL no cambia. KWMAT0 no compara mayusculas en DE.
KWMAT:
KWMAT0: PUSH    HL
KW1:    LD      A,(DE)
        OR      A
        JR      Z,KWOK
        LD      C,A
        LD      A,(HL)
        CP      'a'
        JR      C,KW2
        AND     5Fh
KW2:    CP      C
        JR      NZ,KWNO
        INC     HL
        INC     DE
        JR      KW1
KWOK:   POP     AF
        XOR     A
        RET
KWNO:   POP     HL
        OR      1
        RET
; CFBAUD: aplica las velocidades de A:MPM.CFG (con las interrupciones apagadas)
CFBAUD: LD      HL,CFBW4
        LD      C,SIOAC
        LD      DE,0E11Ah       ; WR3 y WR1 del canal A
        CALL    CFB1
        LD      HL,CFBW4+2
        LD      C,SIOBC
        LD      DE,0C11Eh
CFB1:   LD      A,(HL)
        OR      A
        RET     Z               ; no se pidio
        INC     HL
        LD      A,(HL)          ; constante del CTC
        DEC     HL
        OR      A
        JR      Z,CFB2
        LD      A,07h
        OUT     (CTC0),A
        INC     HL
        LD      A,(HL)
        DEC     HL
        OUT     (CTC0),A
CFB2:   LD      A,4
        OUT     (C),A
        LD      A,(HL)
        OUT     (C),A
        LD      A,1
        OUT     (C),A
        OUT     (C),E
        LD      A,3
        OUT     (C),A
        OUT     (C),D
        LD      A,5
        OUT     (C),A
        LD      A,0EAh
        OUT     (C),A
        RET
KLST:   DEFB    'LST=',0
KSTAT:  DEFB    'STATUS=',0
KBAUD:  DEFB    'BAUD ',0
KDRV:   DEFB    'DRIVE ',0
KCON4:  DEFB    'CONSOLE4=',0
KVIRT:  DEFB    'VIRTUAL',0
KON:    DEFB    'ON',0
KOFF:   DEFB    'OFF',0
KRAM:   DEFB    'RAM',0
KFLASH: DEFB    'FLASH',0
KSD:    DEFB    'SD',0
; velocidades con la CPU a 7,3728 MHz: nombre, WR4, constante del CTC (como BAUD.COM)
TASAS:  DEFB    '230400',0,84h,0
        DEFB    '115200',0,0C4h,0
        DEFB    '9600',0,44h,3
        DEFB    '4800',0,44h,6
        DEFB    '2400',0,44h,12
        DEFB    '1200',0,44h,24
        DEFB    '600',0,44h,48
        DEFB    '300',0,44h,96
        DEFB    0
CFREC:  DEFW    0
CFOK:   DEFB    0
CFDRV:  DEFB    0
CFBW4:  DEFB    0,0,0,0         ; WR4 y constante del CTC de los canales A y B
CFGBUF  EQU     B0MEM+1000h

; STCMP: Z si el nombre de la entrada HL (usuario en HL) es el de DE (11
; letras). Deja HL en el byte 12 de la entrada.
STCMP:  INC     HL
        LD      B,11
STC1:   LD      A,(HL)
        AND     7Fh
        EX      DE,HL
        CP      (HL)
        EX      DE,HL
        INC     HL
        INC     DE
        RET     NZ
        DJNZ    STC1
        RET

; LSTINI: si LST va a un archivo, una pagina de la reserva para el anillo
LSTINI: LD      HL,0
        LD      (LSTH),HL
        LD      (LSTT),HL
        LD      A,(LSTMD)
        OR      A
        RET     Z
        LD      A,(POOLN)
        OR      A
        JR      Z,LSI9          ; no hay: a la SIO B
        LD      A,1
        LD      DE,LSTPG
        JP      POOLTK
LSI9:   LD      (LSTMD),A
        RET

; STARMA: las ordenes del arranque: H:LSTFILE si LST va a un archivo y
; H:SUBMIT A:STARTUP si existe A:STARTUP.SUB
STARMA: LD      DE,STCMD
        LD      A,(LSTMD)
        OR      A
        JR      Z,SA1
        LD      HL,STLF
        CALL    STCPY
SA1:    LD      A,(STSUB)
        OR      A
        JR      Z,SA2
        LD      HL,STSB
        CALL    STCPY
SA2:    XOR     A
        LD      (DE),A
        LD      HL,STCMD
        LD      (STPTR),HL
        LD      A,(HL)
        LD      (STOK),A        ; algo que teclear?
        RET
STCPY:  LD      A,(HL)
        OR      A
        RET     Z
        LD      (DE),A
        INC     HL
        INC     DE
        JR      STCPY

STNAME: DEFB    'STARTUP SUB'
CFNAME: DEFB    'MPM     CFG'
STLF:   DEFB    'H:LSTFILE',13,0
STSB:   DEFB    'H:SUBMIT A:STARTUP',13,0
STREC:  DEFB    0
CFBLK:  DEFW    0
STSUB:  DEFB    0
STCMD:  DEFS    32
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
; SDRDX / SDWRX: lectura / escritura de la SD con un reintento. Si falla, la
; tarjeta se vuelve a iniciar (pudo haberse cambiado) y su cache se olvida. Si
; vuelve a fallar, un mensaje en la consola del proceso dice donde.
SDRDX:  CALL    SDRD
        RET     Z
        CALL    SDREIN
        CALL    Z,SDRD
        RET     Z
        LD      HL,MSGRD
        JR      SDFAIL
SDWRX:  CALL    SDWR
        RET     Z
        CALL    SDREIN
        CALL    Z,SDWR
        RET     Z
        LD      HL,MSGWR
SDFAIL: CALL    SDMSG
        LD      A,1
        OR      A
        RET

; SDREIN: inicia otra vez la tarjeta DSKC (CMD0, CMD8, ACMD41, CMD58). Z = bien.
SDREIN: CALL    CPURGE
        LD      A,CSOFF         ; 80 relojes con CS arriba
        OUT     (SPICS),A
        LD      B,10
SRI1:   CALL    SPIRX
        DJNZ    SRI1
        LD      HL,0
        LD      (ARG),HL
        LD      (ARG+2),HL
        LD      A,95h
        LD      (SDCRC),A
        LD      C,40h+0
        CALL    SDCMDE
        CP      1               ; en espera
        RET     NZ
        LD      HL,01AAh
        LD      (ARG),HL
        LD      A,87h
        LD      (SDCRC),A
        LD      C,40h+8
        CALL    SDCMD           ; (las tarjetas viejas no lo conocen: da igual)
        CALL    SPIRX
        CALL    SPIRX
        CALL    SPIRX
        CALL    SPIRX
        CALL    SDEND
        LD      DE,4000         ; ACMD41 hasta que salga del estado de espera
SRI2:   PUSH    DE
        LD      HL,0
        LD      (ARG),HL
        LD      (ARG+2),HL
        LD      C,40h+55
        CALL    SDCMDE
        LD      HL,4000h        ; HCS
        LD      (ARG+2),HL
        LD      C,40h+41
        CALL    SDCMDE
        POP     DE
        OR      A
        JR      Z,SRI3
        DEC     DE
        LD      A,D
        OR      E
        JR      NZ,SRI2
        INC     A               ; NZ
        RET
SRI3:   LD      A,(DSKC)
        CALL    SDTIPO          ; SDHC o SDSC
        XOR     A
        RET
SDCMDE: CALL    SDCMD
        PUSH    AF
        CALL    SDEND
        POP     AF
        RET

; CPURGE: olvida lo que hay en la cache (y en BUF) de la tarjeta DSKC
CPURGE: CALL    FLUSH           ; (lo de BUF a la tarjeta antes de olvidarlo)
        LD      A,(DSKC)
        LD      C,A
        LD      HL,CCARD
        CP      (HL)
        JR      NZ,CPU1
        LD      (HL),0FFh
        LD      A,0FFh
        LD      (BUFSL),A
        LD      (BUFOK),A       ; (FF: BUF no esta en la cache)
CPU1:   LD      HL,CTAG
        LD      DE,5
        LD      B,0             ; 256 huecos
CPU2:   LD      A,(HL)
        CP      C
        JR      NZ,CPU3
        LD      (HL),0FFh
CPU3:   ADD     HL,DE
        DJNZ    CPU2
        RET

; SDMSG: el texto HL, la unidad, pista y sector, por la consola del proceso
SDMSG:  PUSH    HL
        CALL    TODADR          ; datapg+5: el proceso que corre; su consola en +0Eh
        LD      DE,5
        ADD     HL,DE
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        LD      E,0Eh
        ADD     HL,DE
        LD      A,(HL)
        CP      NMBCNS
        JR      C,SDM1
        XOR     A
SDM1:   LD      (MCON),A
        POP     HL
        CALL    MPSTR
        LD      A,(DRV)
        ADD     A,'A'
        CALL    MPCH
        LD      HL,MSGPT
        CALL    MPSTR
        LD      HL,(TRK)
        CALL    MPHX16
        LD      HL,MSGSC
        CALL    MPSTR
        LD      HL,(SEC)
        CALL    MPHX16
        LD      HL,MSGFIN
MPSTR:  LD      A,(HL)
        OR      A
        RET     Z
        CALL    MPCH
        INC     HL
        JR      MPSTR
MPHX16: LD      A,H
        CALL    MPHEX
        LD      A,L
MPHEX:  PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    MPNIB
        POP     AF
MPNIB:  AND     15
        ADD     A,90h
        DAA
        ADC     A,40h
        DAA
MPCH:   PUSH    HL
        PUSH    DE
        PUSH    BC
        LD      C,A
        LD      A,(MCON)
        LD      D,A
        CALL    CONOUT
        POP     BC
        POP     DE
        POP     HL
        RET
MCON:   DEFB    0
SDCRC:  DEFB    0FFh
MSGRD:  DEFB    13,10,'SD: read error on ',0
MSGWR:  DEFB    13,10,'SD: write error on ',0
MSGPT:  DEFB    ': track ',0
MSGSC:  DEFB    'h, sector ',0
MSGFIN: DEFB    'h',13,10,0

SDTIPO: LD      (DSKC),A
        LD      HL,HCARD        ; SDSC mientras no diga otra cosa
        ADD     A,L
        LD      L,A
        JR      NC,SDT0
        INC     H
SDT0:   LD      (HL),0
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
        DEFB    SIOBC,1, SIOBC,1Eh                  ; B: RX y TX por int., estado afecta al vector
        DEFB    SIOAC,1, SIOAC,1Ah                  ; A: RX y TX por int.
SIOINN  EQU     ($-SIOINI)/2
TXINI:  DEFB    0,0,0,0,SIOAD,SIOAC
        DEFB    0,0,0,0,SIOBD,SIOBC

VECS:   DEFW    ITXB,IEXB,IRXB,ISPB,ITXA,IEXA,IRXA,ISPA    ; FFE0-FFEE
        DEFW    INULL,ITICK,INULL,INULL                    ; FFF0-FFF6 (CTC 0-3)

MSG:    DEFB    13,10,'ZEPHYRUS XIOS 1.4 (OLIVEROS 2026): 5 consoles, ',0
MSGB:   DEFB    ' banks, drives A-P',13,10,0
MSGC:   DEFB    ' KB disk cache',13,10,0
MSGS:   DEFB    'A:STARTUP.SUB',13,10,0
MSGL:   DEFB    'LST: to a file (A:MPM.CFG, H:LSTFILE)',13,10,0
MSGG:   DEFB    'G: RAM disk, ',0
MSGG0:  DEFB    'G: no RAM disk (all memory in use)',13,10,0
MSGK:   DEFB    ' KB',13,10,0

SIOPUT: PUSH    AF              ; (y a la pantalla de la consola 0)
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      C,A
        LD      A,(VTPG)
        OR      A
        JR      Z,SIOP0
        LD      D,0
        LD      HL,VTPUT
        CALL    BKCALL
SIOP0:  POP     HL
        POP     DE
        POP     BC
SIOP1:  IN      A,(SIOAC)
        AND     4
        JR      Z,SIOP1
        POP     AF
        OUT     (SIOAD),A
        RET


; ------------------------------------------------------------- discos (en la parte con bancos:
; el BDOS los llama con el banco 0 puesto)
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
        LD      A,E
        LD      (SELE),A        ; bit 0 = 0: primera seleccion (la unidad se registra)
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
        JR      NZ,SELD0
        LD      A,(NRPG)        ; disco en RAM: solo si hay paginas
        OR      A
        RET     Z
        JR      SELD1
SELD0:  JR      NC,SELD1
        LD      (DSKC),A        ; SD: al registrar la unidad (DSKRESET despues de
        LD      A,(SELE)        ; cambiar la tarjeta) se olvida su cache
        RRA
        PUSH    BC
        CALL    NC,CPURGE
        POP     BC
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
        CALL    BUFPTR          ; BUF (aqui) -> DMA del programa
        PUSH    HL
        CALL    UDMA
        POP     HL
        JR      NZ,RD2
        LD      BC,128          ; directo: su pagina en la ventana 0
        CALL    CPYC
        XOR     A
        RET
RD2:    LD      (XSRC),HL       ; si no, en dos mitades por BOUNCE (memoria alta)
        LD      HL,(DMA)
        LD      (XDST),HL
        CALL    XRD64
        CALL    XRD64
        XOR     A
        RET

WRITE:  LD      A,C             ; tipo: 0 normal, 1 directorio, 2 bloque nuevo
        LD      (WTYPE),A
        CALL    TODCHK
        CALL    DSKADR
        LD      A,(DSKC)
        CP      3
        JR      NC,ERR1         ; flash: solo lectura
        CALL    UNCHK           ; GMODE: 1 el bloque entero, 2 un bloque sin usar
        CALL    GETBLK
        RET     NZ
        CALL    BUFPTR          ; DMA del programa -> BUF
        PUSH    HL
        CALL    UDMA
        POP     HL
        JR      NZ,WR0
        EX      DE,HL
        LD      BC,128
        CALL    CPYC
        JR      WR00
WR0:    LD      (XDST),HL       ; si no, en dos mitades por BOUNCE
        LD      HL,(DMA)
        LD      (XSRC),HL
        CALL    XWR64
        CALL    XWR64
WR00:
        LD      A,(DSKC)
        CP      2
        JP      Z,RAMWR         ; disco en RAM
        LD      HL,(RECN)       ; escritura diferida: BUF queda con cambios y va
        LD      DE,512+128      ; a la tarjeta al pasar a otro bloque (FLCHK).
        OR      A               ; El directorio (los 128 registros despues de la
        SBC     HL,DE           ; pista de sistema), en el acto: MP/M manda C = 1
        JR      C,WR1           ; tambien con los datos, no sirve para saberlo
        LD      A,1
        LD      (BDIRTY),A
        JP      CWRREC          ; el registro tambien a la cache
WR1:    CALL    SDWRX
        JP      Z,CWRREC        ; escrito: el registro tambien a la cache
        CALL    CWRERR          ; fallo: olvidar el bloque (BUF ya no es la tarjeta)
ERR1:   LD      A,1
        OR      A
        RET

; UNCHK: GMODE para WRITE. MP/M pone el bit 1 de C en el primer registro de un
; bloque de asignacion nuevo (2 KB, 16 registros): mientras se escriban sus
; registros en orden, lo que hay en la tarjeta no importa y no se lee antes.
; Pero solo al empezar cada bloque de 512 de la SD: si un programa lee otro
; archivo entre dos registros (ZIP), BUF se va a la tarjeta y hay que volver a
; leerlo, o el registro anterior se pierde.
UNCHK:  LD      A,1
        LD      (GMODE),A
        LD      A,(WTYPE)
        AND     2
        JR      Z,UNC1
        LD      A,(DRV)
        LD      (UNDRV),A
        LD      HL,(RECN)
        LD      (UNREC),HL
        LD      A,16
        LD      (UNCNT),A
UNC1:   LD      A,(UNCNT)
        OR      A
        RET     Z
        LD      A,(DRV)
        LD      HL,UNDRV
        CP      (HL)
        JR      NZ,UNC0
        LD      HL,(RECN)
        LD      DE,(UNREC)
        OR      A
        SBC     HL,DE
        JR      NZ,UNC0
        INC     DE
        LD      (UNREC),DE
        LD      HL,UNCNT
        DEC     (HL)
        LD      A,(OFS)         ; sin leer, solo el primer registro de los 512
        OR      A               ; bytes: si entre medio BUF fue a la tarjeta (se
        LD      A,1             ; leyo otro archivo), los otros tres hay que
        JR      NZ,UNC2         ; leerlos o se pierde lo ya escrito
        INC     A
UNC2:   LD      (GMODE),A
        RET
UNC0:   XOR     A
        LD      (UNCNT),A
        RET
UNDRV:  DEFB    0
UNREC:  DEFW    0
UNCNT:  DEFB    0

; GBNEW: BUF pasa a ser el bloque BLK sin leerlo (sin usar); su copia en la
; cache, si habia una, ya no vale.
GBNEW:  LD      A,(NCPG)
        OR      A
        JR      Z,GBN1
        CALL    CLOOK
        JR      NZ,GBN1
        CALL    TAGADR
        LD      (HL),0FFh
GBN1:   LD      A,0FFh
        LD      (BUFSL),A
        LD      (BUFOK),A       ; (FF: BUF no esta en la cache)
        LD      A,(DSKC)
        LD      (CCARD),A
        LD      HL,(BLK)
        LD      (CBLK),HL
        LD      HL,(BLK+2)
        LD      (CBLK+2),HL
        XOR     A
        RET

; FLCHK: si BUF tiene cambios y el pedido (DSKC, BLK) es otro bloque, BUF a la
; tarjeta antes. Z = bien.
FLCHK:  LD      A,(BDIRTY)
        OR      A
        RET     Z
        LD      A,(DSKC)
        LD      HL,CCARD
        CP      (HL)
        JR      NZ,FLUSH
        LD      HL,(BLK)
        LD      DE,(CBLK)
        OR      A
        SBC     HL,DE
        JR      NZ,FLUSH
        LD      HL,(BLK+2)
        LD      DE,(CBLK+2)
        SBC     HL,DE
        RET     Z
; FLUSH: BUF (tarjeta CCARD, bloque CBLK) a la tarjeta, si tiene cambios.
; Conserva DSKC y BLK del pedido. Z = bien.
FLUSH:  LD      A,(BDIRTY)
        OR      A
        RET     Z
        XOR     A
        LD      (BDIRTY),A      ; (antes: SDREIN -> CPURGE -> FLUSH no se repite)
        LD      A,(DSKC)
        PUSH    AF
        LD      HL,(BLK)
        PUSH    HL
        LD      HL,(BLK+2)
        PUSH    HL
        LD      A,(CCARD)
        LD      (DSKC),A
        LD      HL,(CBLK)
        LD      (BLK),HL
        LD      HL,(CBLK+2)
        LD      (BLK+2),HL
        LD      A,(FLQ)
        OR      A
        JR      NZ,FLU1
        CALL    SDWRX
        JR      FLU2
FLU1:   CALL    SDWR            ; (desde H:ZLOADER: sin reintento ni mensaje)
FLU2:   PUSH    AF
        CALL    NZ,CWRERR
        POP     AF
        POP     HL
        LD      (BLK+2),HL
        POP     HL
        LD      (BLK),HL
        POP     HL              ; (H = DSKC)
        LD      A,H
        LD      (DSKC),A
        RET
; FLUSHQ: para el servicio 42 (H:ZLOADER, con MXDisk tomado)
FLUSHQ: LD      A,1
        LD      (FLQ),A
        CALL    FLUSH
        LD      A,0
        LD      (FLQ),A
        RET
WTYPE:  DEFB    0
BDIRTY: DEFB    0               ; BUF tiene registros que la tarjeta todavia no
FLQ:    DEFB    0

; UDMA: para copiar el registro directo entre BUF y el DMA del programa, sin
; BOUNCE ni cambiar de banco dos veces por mitad. Z: CPAGE = la pagina del
; programa donde cae su DMA y DE = el DMA en la ventana 0 (CPYC). NZ: no se
; puede (DMA en la memoria comun, el registro cruza de pagina, sin segmento).
; El banco es el que pondria SWTUSER de XDOS: su segmento en (USEGA) (FF:
; ninguno; al cargar un programa es el del hijo, no el del TMP) y la tabla de
; descriptores en ((UTABA)), 4 bytes cada uno, el banco en +3. UDINI saca las
; dos direcciones del codigo de SWTUSER al arrancar.
USEGA:  DEFW    0
UTABA:  DEFW    0
UDINI:  LD      HL,(SWTUSER+1)  ; CALL x / LD A,(USEG) / ... / LD HL,(TAB)
        PUSH    HL
        INC     HL
        INC     HL
        INC     HL
        LD      A,(HL)
        INC     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        POP     HL
        CP      3Ah
        RET     NZ
        LD      BC,16h
        ADD     HL,BC
        LD      A,(HL)
        CP      2Ah
        RET     NZ
        INC     HL
        LD      C,(HL)
        INC     HL
        LD      B,(HL)
        LD      (UTABA),BC
        LD      (USEGA),DE
        RET
UDMA:   LD      HL,(DMA)
        LD      A,H
        CP      0C0h
        JR      NC,UDMN
        AND     3Fh
        CP      3Fh
        JR      NZ,UDM1
        LD      A,L
        CP      81h
        JR      NC,UDMN         ; (DMA AND 3FFF) + 128 > 4000h
UDM1:   LD      HL,(USEGA)      ; el segmento que pondria SWTUSER
        LD      A,H
        OR      L
        JR      Z,UDMN          ; (no se encontro al arrancar)
        LD      A,(HL)
        CP      0FFh
        JR      Z,UDMN          ; ninguno: SWTUSER no cambia de banco
        ADD     A,A
        ADD     A,A
        LD      E,A
        LD      D,0
        LD      HL,(UTABA)
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        ADD     HL,DE
        INC     HL
        INC     HL
        INC     HL
        LD      A,(HL)          ; banco (como SELMEM: descriptor + 3)
        CP      MAXBNK+1
        JR      NC,UDMN
        LD      E,A             ; BNKPG + 3*banco + ventana
        ADD     A,A
        ADD     A,E
        LD      E,A
        LD      A,(DMA+1)
        RLCA
        RLCA
        AND     3
        ADD     A,E
        LD      E,A
        LD      D,0
        LD      HL,BNKPG
        ADD     HL,DE
        LD      A,(HL)
        LD      (CPAGE),A
        LD      DE,(DMA)
        LD      A,D
        AND     3Fh
        LD      D,A
        XOR     A
        RET
UDMN:   OR      0FFh
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


; WRSYS: servicio 43 (BKCALL). B = unidad, DE = registro, los datos en DIRBF.
; Sin GETBLK ni la cache (CPYC prende las interrupciones, y aqui no se puede):
; el bloque se lee a BUF, se cambia el registro y se escribe; su copia en la
; cache, si habia, se olvida.
WRSYS:  LD      A,B
        CP      NDRV
        JR      NC,WRS9
        LD      (DRV),A
        LD      A,D             ; pista = registro / 512, sector = registro % 512
        RRA
        AND     7Fh
        LD      L,A
        LD      H,0
        LD      (TRK),HL
        LD      A,D
        AND     1
        LD      D,A
        LD      (SEC),DE
        CALL    DSKADR
        LD      A,(DSKC)
        CP      2
        JR      NC,WRS9         ; solo en una SD
        LD      A,1             ; BUF a la tarjeta si tenia cambios (sin
        LD      (FLQ),A         ; mensaje: aqui no se puede escribir en la consola)
        CALL    FLUSH
        LD      A,0
        LD      (FLQ),A
        LD      A,0FFh          ; BUF ya no es ningun bloque
        LD      (CCARD),A
        LD      (BUFSL),A
        LD      (BUFOK),A
        CALL    SDRD
        JR      NZ,WRS9
        CALL    BUFPTR
        EX      DE,HL
        LD      HL,DIRBF
        LD      BC,128
        LDIR
        CALL    SDWR
        JR      NZ,WRS9
        LD      A,(NCPG)
        OR      A
        JR      Z,WRS1
        CALL    CLOOK
        JR      NZ,WRS1
        CALL    TAGADR
        LD      (HL),0FFh
WRS1:   XOR     A
        RET
WRS9:   LD      A,1
        RET

; ZMPB / ZDRB / ZMNB: los servicios 11, 36 y 10 de ZIOS (BKCALL desde ZEMU).
; ZMPB: unidad C -> A = tarjeta, HL = disco virtual
ZMPB:   LD      A,C
        CALL    ZMPADR
        EX      DE,HL
        RET
; ZDRB: unidad C -> A = tarjeta, HL = DSM de su DPB
ZDRB:   LD      A,C
        CALL    ZMPADR
        LD      HL,DPBSD+5
        CP      2
        JR      C,ZDB1
        LD      HL,DPBRM+5
        JR      Z,ZDB1
        LD      HL,DPBFL+5
ZDB1:   LD      E,(HL)
        INC     HL
        LD      D,(HL)
        EX      DE,HL
        RET
; ZMNB: la unidad D pasa a la tarjeta E, disco virtual (ZHL)
ZMNB:   PUSH    DE
        LD      A,D
        CALL    ZMPADR          ; HL -> DMW
        PUSH    HL
        LD      HL,(ZHL)        ; disco * 32
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        EX      (SP),HL
        POP     BC
        LD      (HL),C
        INC     HL
        LD      (HL),B
        POP     DE
        LD      HL,DCARD
        LD      C,D
        LD      B,0
        ADD     HL,BC
        LD      (HL),E
        RET
; ZMPADR: unidad A -> A = tarjeta, DE = disco virtual, HL -> su DMW
ZMPADR: LD      E,A
        LD      D,0
        LD      HL,DCARD
        ADD     HL,DE
        LD      B,(HL)
        LD      HL,DMW
        ADD     HL,DE
        ADD     HL,DE
        PUSH    HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        LD      A,5             ; DMW = disco * 32
ZMP1:   SRL     D
        RR      E
        DEC     A
        JR      NZ,ZMP1
        POP     HL
        LD      A,B
        RET

; variables del disco (solo las usa la parte con bancos)
DCARD:  DEFS    NDRV
DMW:    DEFS    2*NDRV
CMNPG:  DEFB    0
DRV:    DEFB    0
TRK:    DEFW    0
SEC:    DEFW    0
DSKC:   DEFB    0
OFS:    DEFB    0
RECN:   DEFW    0
BLK:    DEFS    4
ARG:    DEFS    4
CCARD:  DEFB    0FFh
CBLK:   DEFS    4
HCARD:  DEFB    0,0
SELE:   DEFB    0
JTBL:   DEFW    0
DBGE:   DEFW    0
DBGR:   DEFB    0

BUF:    DEFS    512             ; bloque de 512 de la SD (en el banco 0)
        DEFS    XPAD            ; relleno que pone mkspr.py (ver alli)
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
; Consolas 0-3: virtuales, en la SIO A (Ctrl-F1..F4 elige la que se ve, como en
; Linux); consola 4: la SIO B. El bufer de entrada de la SIO A es de la consola
; que se ve (al cambiar se vacia). D = consola
; KDRAIN: lo que llego por la SIO A pasa por KEYIN (de a uno, con las
; interrupciones prendidas entre uno y otro, para que la SIO no pierda nada)
KDRAIN: LD      A,(RXPEND)
        OR      A
        RET     Z
KDR1:   DI
        LD      HL,KDONE
        CALL    BKCALL
        EI
        JR      NC,KDR1         ; NC: proceso uno
        DI
        CALL    TXSTA           ; (si cambio de consola o de vista: a redibujar)
        EI
        RET
CONST:  CALL    KDRAIN
        CALL    ISTMP           ; el TMP (indicador de ordenes): historial
        JP      Z,TCONST
CONSTR: LD      A,D
        CP      4
        JR      C,CSTV
        LD      A,(SIOBM)       ; la 4: la SIO B, nada o virtual
        OR      A
        JR      Z,CST1
        DEC     A
        RET     Z
        LD      A,4
CSTV:   LD      HL,RXCNT        ; consolas virtuales: cada una tiene lo suyo
        ADD     A,L
        LD      L,A
        JR      NC,CST0
        INC     H
CST0:   LD      A,(HL)
        OR      A
        RET     Z
        LD      A,0FFh
        RET
CST1:   LD      A,(HDB)
        LD      HL,TLB
        CP      (HL)
CSTR:   LD      A,0
        RET     Z
        DEC     A
        RET

CONIN:  CALL    ISTMP
        JP      Z,TCONIN
CONINR: CALL    KDRAIN
        LD      A,I
        DI
        PUSH    AF
        CALL    CONSTR
        OR      A
        JR      NZ,CIN2
        POP     AF
        JP      PO,CIN1
        EI
CIN1:   PUSH    DE
        LD      C,POLL
        LD      A,D
        ADD     A,A
        INC     A
        LD      E,A             ; dispositivo 2D+1: entrada de la consola D
        CALL    XDOS
        POP     DE
        JR      CONINR
CIN2:   LD      A,D
        CP      4
        JR      C,CIN3
        LD      A,(SIOBM)
        OR      A
        JR      Z,CIN4
CIN3:
        LD      HL,VRXGET
        CALL    BKCALL
        JR      CIN5
CIN4:   LD      HL,HDB          ; consola 4: el bufer de la SIO B
        LD      A,(HL)
        LD      C,A
        INC     A
        AND     3Fh
        LD      (HL),A
        LD      A,C
        ADD     A,RXB AND 0FFh
        LD      L,A
        LD      H,RXB SHR 8
        LD      A,(HL)
CIN5:   LD      C,A             ; (los 8 bits: UTF-8)
        POP     AF
        LD      A,C
        RET     PO
        EI
        RET

; Salida por interrupcion: cada canal tiene un bufer circular. Si el transmisor
; esta parado el caracter sale directo; si no, va al bufer y la interrupcion de
; "transmisor vacio" manda el siguiente. Con el bufer lleno el proceso espera su
; bandera (FLTXA/FLTXB), que pone la interrupcion al liberar un lugar.
; Estructura: +0 cabeza, +1 cola, +2 transmitiendo, +3 alguien espera,
;             +4 puerto de datos, +5 puerto de control, +6 bufer
COST1:  LD      HL,TXB          ; LISTST: hay lugar en la SIO B: A = FF
        LD      A,(HL)
        INC     HL
        LD      L,(HL)          ; (cola + 1) & TXMSK <> cabeza
        INC     L
        XOR     L
        AND     TXMSK
        RET     Z               ; lleno: A = 0
        LD      A,0FFh
        RET

CONOUT: LD      A,D
        CP      4
        JR      C,VCOUT
        LD      A,(SIOBM)
        OR      A
        JR      Z,COUT1
        DEC     A
        RET     Z               ; CONSOLE4=OFF: se pierde
        JR      VCOUT
COUT1:  LD      HL,TXB
        LD      E,FLTXB
; TXPUT: caracter C al canal HL; E = su bandera
TXPUT:  LD      A,I
        DI
        PUSH    AF
TXP1:   PUSH    HL
        CALL    TXTRY
        POP     HL
        JR      NZ,TXP9
        PUSH    HL              ; lleno: marcar que se espera y esperar
        INC     HL
        INC     HL
        INC     HL
        LD      (HL),1
        POP     HL
        POP     AF
        PUSH    AF
        JP      PO,TXPW
        EI
TXPW:   PUSH    HL
        PUSH    BC
        PUSH    DE
        LD      C,FLAGWT
        CALL    XDOS
        POP     DE
        POP     BC
        POP     HL
        DI
        JR      TXP1
TXP9:   POP     AF
        RET     PO
        EI
        RET
; TXTRY: caracter C al canal HL, con las interrupciones apagadas. NZ: listo;
; Z: el bufer esta lleno. Conserva BC y DE (no HL); usa poca pila (la del
; BDOS es corta).
TXTRY:  INC     HL
        INC     HL
        LD      A,(HL)          ; transmitiendo?
        OR      A
        JR      NZ,TT2
        LD      (HL),1          ; no: sale directo
        INC     HL
        INC     HL
        LD      A,C
        LD      C,(HL)
        OUT     (C),A
        LD      C,A
        OR      0FFh
        RET
TT2:    DEC     HL
        DEC     HL
        PUSH    BC
        LD      A,(HL)          ; cabeza
        INC     HL
        LD      B,(HL)          ; cola
        INC     B
        XOR     B
        AND     TXMSK
        JR      Z,TT9           ; lleno
        DEC     B
        LD      A,B
        INC     A
        AND     TXMSK
        LD      (HL),A          ; nueva cola
        LD      A,B             ; bufer[cola vieja] = caracter
        ADD     A,5
        ADD     A,L
        LD      L,A
        JR      NC,TT3
        INC     H
TT3:    LD      (HL),C
        OR      0FFh
TT9:    POP     BC
        RET

; VCOUT: consola virtual D (0-3), caracter C. Siempre va a su pantalla en
; memoria (VTPUT); si es la que se ve, tambien a la SIO A. Las de atras nunca
; esperan. La que se ve espera mientras se redibuja o sale la linea de estado.
VCOUT:  LD      A,I
        DI
        PUSH    AF
VCO:    LD      A,(ACTVC)
        CP      D
        JR      NZ,VCBG
VCRLR:  LD      HL,(0)          ; quien escribe (para la linea de estado): el
        LD      (LASTPD),HL     ; arranque pone aqui donde esta el que corre
        LD      A,(VIEWING)     ; se miraba hacia atras: volver al dia
        OR      A
        JR      NZ,VCSN
        LD      A,(GENACT)
        OR      A
        JR      NZ,VC0
        LD      HL,VQN          ; la que se ve: a la cola de su pantalla (se pasan
        LD      A,(HL)          ; juntos, con una sola llamada al banco 0) y a la SIO
        CP      VQMAX
        JR      NC,VC0B
        INC     (HL)
        ADD     A,VQ AND 0FFh
        LD      L,A
        LD      H,VQ SHR 8
        LD      (HL),C
        LD      A,(TXA+2)       ; al bufer de la SIO A sin TXTRY (es lo de
        OR      A               ; cada caracter); parada: TXTRY la arranca
        JR      Z,VCT0
        LD      HL,(TXA)        ; L = cabeza, H = cola
        LD      A,H
        INC     A
        AND     TXMSK
        CP      L
        JR      Z,VC1           ; lleno
        LD      (TXA+1),A
        LD      A,H
        ADD     A,(TXA+6) AND 0FFh
        LD      L,A
        LD      H,TXA SHR 8
        LD      (HL),C
VCX:    POP     AF
        RET     PO
        EI
        RET
VCT0:   LD      HL,TXA
        CALL    TXTRY
        JR      VCX
VCBG:   LD      HL,VTPUT        ; una de atras: solo a su pantalla
        CALL    BKCALL
        JR      VCX
VCSN:   LD      HL,VSNAP
        CALL    BKCALL
        CALL    TXSTA
        JR      VCO
VC0:    DEC     A               ; 1: redibujando (lee la pantalla: esperar antes)
        JR      NZ,VC0B
        CALL    VCWAIT
        JR      VCO
VC0B:   LD      HL,VQFL         ; la cola llena o la linea de estado saliendo
        CALL    BKCALL
        LD      HL,VQN
        LD      (HL),1
        LD      A,C
        LD      (VQ),A
VC1:    LD      A,(SWCNT)
        LD      B,A
VC2:    LD      A,(GENACT)
        OR      A
        JR      NZ,VC3
        LD      HL,TXA
        CALL    TXTRY
        JR      NZ,VCX
VC3:    CALL    VCWAIT          ; (con las interrupciones prendidas puede
        LD      A,(ACTVC)       ; cambiar la consola)
        CP      D
        JR      NZ,VCX
        LD      A,(SWCNT)
        CP      B
        JR      Z,VC2           ; si cambio, el redibujo ya lo muestra
        JR      VCX
VCWAIT: LD      A,1
        LD      (TXA+3),A
        EI
        PUSH    BC
        PUSH    DE
        LD      C,FLAGWT
        LD      E,FLTXA
        CALL    XDOS
        INC     A               ; FF: otro proceso ya la esperaba: un tic
        JR      NZ,VCW1
        LD      C,141
        LD      DE,1
        CALL    XDOS
VCW1:   POP     DE
        POP     BC
        DI
        RET

; LIST: la impresora (LST:) sale por la SIO B, la misma linea de la consola 1
; (un terminal, el NUNTIUS o un cable a oli que la capture).
LIST:   LD      A,(LSTMD)
        OR      A
        JP      Z,COUT1         ; a la SIO B
; al anillo de 16 KB de la pagina LSTPG (lo vacia H:LSTFILE en el archivo)
LST0:   LD      A,I
        DI
        PUSH    AF
        LD      HL,LSTPB
        CALL    BKCALL
        JR      Z,LSTF          ; lleno: esperar un tic
        POP     AF
        RET     PO
        EI
        RET
LSTF:   POP     AF
        JP      PO,LSTF1
        EI
LSTF1:  PUSH    BC
        LD      C,141
        LD      DE,1
        CALL    XDOS
        POP     BC
        JR      LST0

POLLDEV: LD     A,C
        CP      2*NMBCNS
        JP      NC,NADA
        SRL     A
        LD      D,A
        JR      C,CPOLL         ; impar: entrada de la consola D
        LD      A,0FFh          ; par: salida (se espera con banderas)
        RET

CPOLL:  LD      A,(RXPEND)      ; algo por pasar por KEYIN: que despierte (y
        OR      A               ; lo pase, KDRAIN)
        JP      Z,CONSTR
        LD      A,0FFh
        RET
MAXCON: LD      A,NMBCNS
        RET

; ------------------------------------------------------------- reloj
STCLK:  LD      A,0FFh
        LD      (TICKN),A
        RET
SPCLK:  XOR     A
        LD      (TICKN),A
        RET
; RTSOFF / RTSON: RTS de la SIO A apagado (WR5 = E8h) o prendido (EAh, como lo
; deja ZIOS). Con control de flujo en el PC (picocom --flow h) el PC deja de
; mandar mientras esta apagado: alrededor del despachador, que corre con las
; interrupciones apagadas, y de KEYIN. Deja las interrupciones apagadas.
RTSOFF: LD      A,0E8h
        JR      RTS1
RTSON:  IN      A,(SIOAC)       ; (no si la SIO ya tiene otro: RR0 bit 0)
        RRA
        RET     C
        LD      A,(RTSHLD)      ; (ni con RAWQ casi lleno: lo bajo IRXA)
        OR      A
        RET     NZ
        LD      A,0EAh
RTS1:   PUSH    AF              ; (las dos SIO: la B tambien puede ser una consola)
        LD      A,5
        DI
        OUT     (SIOAC),A
        OUT     (SIOBC),A
        POP     AF
        OUT     (SIOAC),A
        OUT     (SIOBC),A
        RET
EXITRG: LD      A,(PREEMP)
        OR      A
        RET     NZ
EIRET:  EI
        RET
IDLE:   CALL    RTSON
        EI
        HALT
IDLRT:  RET

; ------------------------------------------------------------- interrupciones
; Recepcion de la SIO: al bufer circular (si se llena se pierde el caracter).
; La SIO A pasa por KEYIN (Ctrl-F1..F4).
IRXA:   LD      (SVSP),SP       ; (en la pila de las interrupciones: la del
        LD      SP,ISTK         ; proceso puede ser la corta del BDOS)
        PUSH    AF
        PUSH    HL
        PUSH    DE
        PUSH    BC
        IN      A,(SIOAD)       ; todo va derecho al anillo RAWQ, solo con la
        LD      C,A             ; ventana 1 (unos 150 ciclos): KEYIN tarda mas
        LD      A,(RAWA)        ; que un caracter a 115200 y va despues, fuera
        LD      (RXACT),A       ; de la interrupcion (KDRAIN). En modo crudo
        CP      2               ; RXACT no es cero: llego algo en este tic.
        JR      Z,IRX9          ; (con XFER en la SIO B el anillo es suyo)
        OR      A
        LD      A,(VTAPG)
        JR      NZ,IRXQ         ; modo crudo: lo lee XFER, no KEYIN
        LD      (RXPEND),A      ; (no cero)
IRXQ:   OUT     (PGPORT+1),A
        LD      HL,(RAWT)       ; cola (0-1FF)
        PUSH    HL
        INC     HL
        LD      A,H
        AND     1
        LD      H,A
        LD      DE,(RAWH)
        OR      A
        SBC     HL,DE
        ADD     HL,DE           ; (Z queda de SBC)
        POP     DE
        JR      Z,IRXR1         ; lleno: se pierde
        LD      (RAWT),HL
        LD      A,(RAWA)        ; casi lleno (448 de 512, no en modo crudo):
        OR      A               ; RTS abajo hasta que RAWGET lo deje en menos
        JR      NZ,IRXR0        ; de 256 (RTSHLD); el PC espera
        LD      DE,(RAWH)
        SBC     HL,DE
        BIT     0,H
        JR      Z,IRXR0
        LD      A,L
        CP      0C0h
        JR      C,IRXR0
        LD      A,5
        OUT     (SIOAC),A
        LD      A,0E8h
        OUT     (SIOAC),A
        LD      (RTSHLD),A
IRXR0:  LD      HL,(RAWT)       ; (la cola vieja: DE se uso)
        DEC     HL
        LD      A,H
        AND     1
        LD      H,A
        LD      DE,RAWQ
        ADD     HL,DE
        LD      (HL),C
IRXR1:  LD      A,(CURPG1)
        OUT     (PGPORT+1),A
IRX9:   POP     BC
        POP     DE
        POP     HL
        POP     AF
        LD      SP,(SVSP)
        EI
        RETI
IRXB:   LD      (SVSP),SP
        LD      SP,ISTK
        PUSH    AF
        PUSH    HL
        PUSH    DE
        PUSH    BC
        IN      A,(SIOBD)
        LD      C,A
        LD      A,(RAWA)        ; modo crudo en la SIO B: al anillo RAWQ, como
        CP      2               ; la SIO A (sin BKCALL)
        JR      NZ,IRXB1
        LD      (RXACT),A
        LD      A,(VTAPG)
        JR      IRXQ
IRXB1:  LD      A,C
        LD      HL,TLB
        LD      DE,RXB
        CALL    RXQ
        JR      IRX9
; RXQ: caracter A al bufer DE (64 bytes), HL = su cola (la cabeza en HL-1)
RXQ:    PUSH    AF
        LD      A,(HL)
        ADD     A,E
        LD      E,A
        POP     AF
        LD      (DE),A
        LD      A,(HL)
        INC     A
        AND     3Fh
        DEC     HL
        CP      (HL)
        INC     HL
        RET     Z               ; lleno
        LD      (HL),A
        RET
; Recepcion especial (error): descartar y reponer
ISPA:   PUSH    AF
        IN      A,(SIOAD)
        LD      A,30h
        OUT     (SIOAC),A
        JP      IRET
ISPB:   PUSH    AF
        IN      A,(SIOBD)
        LD      A,30h
        OUT     (SIOBC),A
        JP      IRET
; Transmisor vacio: el siguiente caracter del bufer. Si alguien esperaba lugar,
; se le pone su bandera (con el marco completo, como el tic).
ITXA:   LD      (SVSP),SP
        LD      SP,ISTK
        PUSH    AF
        PUSH    HL
        LD      HL,TXA
        CALL    TXNEXT
        LD      A,FLTXA
        JR      ITX1
ITXB:   LD      (SVSP),SP
        LD      SP,ISTK
        PUSH    AF
        PUSH    HL
        LD      HL,TXB
        CALL    TXNEXT
        LD      A,FLTXB
ITX1:   POP     HL
        JR      NZ,ITX2
        POP     AF
        LD      SP,(SVSP)
        EI
        RETI
ITX2:   LD      (IFLGN),A
        POP     AF
        LD      SP,(SVSP)
        JP      IFLG

; TXNEXT: HL = canal. NZ si alguien esperaba lugar (y ya no espera).
TXNEXT: PUSH    BC
        PUSH    DE
        LD      D,H
        LD      E,L
        LD      A,(DE)          ; cabeza
        INC     HL
        CP      (HL)
        JR      NZ,TXN1
        LD      A,E             ; vacio: en la SIO A, el redibujo o la linea de
        CP      TXA AND 0FFh    ; estado lo vuelven a llenar
        JR      NZ,TXN0
        LD      A,(GENACT)
        LD      HL,STATDUE
        OR      (HL)
        LD      HL,TXA+1
        JR      Z,TXN0
        LD      HL,GENFILL
        CALL    BKCALL
        LD      HL,TXA+1
        LD      A,(DE)
        CP      (HL)
        JR      NZ,TXN1
TXN0:   INC     HL              ; vacio: el transmisor se para
        LD      (HL),0
        INC     HL
        INC     HL
        INC     HL
        LD      C,(HL)
        LD      A,28h           ; reponer "Tx int pending"
        OUT     (C),A
        JR      TXN8
TXN1:   LD      HL,6            ; bufer[cabeza]
        ADD     HL,DE
        ADD     A,L
        LD      L,A
        JR      NC,TXN2
        INC     H
TXN2:   LD      A,(HL)
        LD      HL,4
        ADD     HL,DE
        LD      C,(HL)
        OUT     (C),A
        LD      A,(DE)
        INC     A
        AND     TXMSK
        LD      (DE),A
TXN8:   LD      HL,3
        ADD     HL,DE
        LD      A,E
        CP      TXA AND 0FFh
        JR      NZ,TXN9
        LD      A,(GENACT)      ; mientras se genera, el que espera sigue esperando
        OR      A
        LD      A,0
        JR      NZ,TXN10
TXN9:   LD      A,(HL)          ; alguien espera: se le avisa cuando queda poco
        OR      A               ; en el bufer (no a cada caracter)
        JR      Z,TXN10
        LD      A,(DE)
        LD      B,A
        INC     DE
        LD      A,(DE)
        DEC     DE
        SUB     B
        AND     TXMSK
        CP      9
        LD      A,0
        JR      NC,TXN10
        LD      (HL),A
        DEC     A
TXN10:  OR      A
        POP     DE
        POP     BC
        RET
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

; Tic del CTC (canal 1). IFLG: el mismo marco para poner la bandera IFLGN.
ITICK:  PUSH    AF
        XOR     A
        LD      (IFLGN),A
        POP     AF
IFLG:   LD      (SVHL),HL
        POP     HL
        LD      (SVRET),HL
        PUSH    AF
        LD      (SVSP),SP
        LD      SP,ISTK
        CALL    RTSOFF          ; va al despachador, que apaga las interrupciones
        PUSH    DE
        PUSH    BC
        LD      A,0FFh
        LD      (PREEMP),A
        LD      A,(IFLGN)
        OR      A
        JR      Z,ITK0
        LD      E,A             ; bandera de la salida de una SIO
        LD      C,FLAGSET
        CALL    XDOS
        JP      ITDONE
ITK0:   LD      A,(KTMO)        ; teclado: ESC sin el resto de la secuencia
        OR      A
        JR      Z,ITK0B
        DEC     A
        LD      (KTMO),A
        JR      NZ,ITK0B
        LD      HL,KFLUSH
        CALL    BKCALL
        CALL    TXSTA
ITK0B:  LD      HL,TXA          ; por si se perdio una interrupcion de transmision
        LD      E,FLTXA
        CALL    TXKICK
        LD      HL,TXB
        LD      E,FLTXB
        CALL    TXKICK
        LD      HL,TDIV         ; 120 Hz -> 60 Hz
        DEC     (HL)
        JR      NZ,ITNOD        ; los tics de en medio no despachan
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
IT1:    LD      HL,(SVRET)      ; el tic cayo en IDLE (la CPU sin trabajo)?
        LD      DE,IDLRT
        OR      A
        SBC     HL,DE
        JR      NZ,IT1A
        LD      HL,IDLEC
        INC     (HL)
IT1A:   LD      HL,CNTSEC
        DEC     (HL)
        JR      NZ,ITDONE
        LD      (HL),TPS
        LD      A,(IDLEC)
        LD      (IDLES),A
        XOR     A
        LD      (IDLEC),A
        LD      HL,(SECS)       ; segundos desde el arranque (para TODCHK)
        INC     HL
        LD      (SECS),HL
        LD      A,(STATON)      ; la linea de estado, cada segundo
        OR      A
        JR      Z,IT2
        LD      (STATDUE),A
        CALL    TXSTA
        JR      Z,IT2
        LD      C,FLAGSET
        LD      E,FLTXA
        CALL    XDOS
IT2:
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
; ITDONE: al despachador, salvo si en el ultimo tic llego algo en modo crudo:
; el despachador de MP/M corre con las interrupciones apagadas y la SIO pierde
; bytes de un bloque de XMODEM. Entonces vuelve directo al proceso (EIRET).
ITDONE: LD      HL,(PDISP+1)
        LD      A,(RXACT)
        OR      A
        JR      Z,ITD1
ITNOD:  LD      A,(RXPEND)      ; uno por tic aunque nadie lea (Ctrl-F), en los
        OR      A               ; tics que no despachan (no se suma al despachador)
        JR      Z,ITN1
        LD      HL,KDONE
        CALL    BKCALL
        CALL    TXSTA
ITN1:   CALL    RTSON           ; sin despachador: el PC puede seguir
        LD      HL,EIRET
ITD1:   LD      (DSPV),HL
        XOR     A
        LD      (RXACT),A
        LD      (PREEMP),A
        POP     BC
        POP     DE
        LD      HL,(SVSP)
        LD      SP,HL
        POP     AF
        LD      HL,(SVRET)
        PUSH    HL
        LD      HL,(DSPV)       ; al despachador (o a EIRET)
        PUSH    HL
        LD      HL,(SVHL)
        RETI

; TXSTA: si la SIO A esta parada, arrancarla (redibujo o linea de estado).
; NZ si alguien esperaba lugar.
TXSTA:  LD      HL,TXA+2
        LD      A,(HL)
        OR      A
        JR      Z,TXS1
        XOR     A
        RET
TXS1:   LD      (HL),1
        LD      HL,TXA
        JP      TXNEXT

; BKCALL: llama a la rutina HL de la parte con bancos (ventana 2 del banco 0)
; con la pagina VTPG en la ventana 0 y la pila en ella. Con las interrupciones
; apagadas. Pasan BC y DE; vuelven A y las banderas. Conserva BC, DE e IX.
BKCALL: LD      (BKSV),SP
        LD      A,(BNKPG+2)
        OUT     (PGPORT+2),A
        LD      A,(VTPG)
        OUT     (PGPORT),A
        LD      A,(VTAPG)
        OUT     (PGPORT+1),A
        LD      SP,BKSTK
        PUSH    IX
        PUSH    BC
        PUSH    DE
        CALL    JPHL
        POP     DE
        POP     BC
        POP     IX
        LD      (BKA),A
        LD      A,(CURPG2)
        OUT     (PGPORT+2),A
        LD      A,(CURPG0)
        OUT     (PGPORT),A
        LD      A,(CURPG1)
        OUT     (PGPORT+1),A
        LD      SP,(BKSV)
        LD      A,(BKA)
        RET
JPHL:   JP      (HL)

; TXKICK: si el canal HL figura transmitiendo pero el transmisor ya esta vacio,
; manda el siguiente (y pone la bandera E si alguien esperaba lugar).
TXKICK: PUSH    HL
        INC     HL
        INC     HL
        LD      A,(HL)
        OR      A
        JR      Z,TXK9
        INC     HL
        INC     HL
        INC     HL
        LD      C,(HL)
        IN      A,(C)
        AND     4
        JR      Z,TXK9
        POP     HL
        CALL    TXNEXT
        RET     Z
        LD      C,FLAGSET
        JP      XDOS
TXK9:   POP     HL
        RET

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
        LD      (CURPG1),A
        OUT     (PGPORT+1),A
        INC     HL
        LD      A,(HL)
        LD      (CURPG2),A      ; antes del OUT: BKCALL la repone
        OUT     (PGPORT+2),A
        RET

; XRD64 / XWR64: 64 bytes entre BUF (banco 0) y el DMA del programa (su banco),
; pasando por BOUNCE en la memoria alta. XSRC y XDST avanzan.
XRD64:  CALL    XCP1
        CALL    SWTUSER
        CALL    XCP2
        JP      SWTSYS
XWR64:  CALL    SWTUSER
        CALL    XCP1
        CALL    SWTSYS
XCP2:   LD      HL,BOUNCE       ; BOUNCE -> (XDST)
        LD      DE,(XDST)
        LD      BC,64
        LDIR
        LD      (XDST),DE
        RET
XCP1:   LD      HL,(XSRC)       ; (XSRC) -> BOUNCE
        LD      DE,BOUNCE
        LD      BC,64
        LDIR
        LD      (XSRC),HL
        RET
XSRC:   DEFW    0
XDST:   DEFW    0

; PGQRY: paginas del banco 0 preguntandole a ZIOS (servicio 1). Va en la memoria
; comun, con la pila en ella, porque la ventana que se pregunta cambia un momento.
PGQRY:  LD      (BKSV),SP
        LD      SP,PGQSTK+24
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
        LD      SP,(BKSV)
        RET
PGQSTK: DEFS    24

; TODADR: HL = TOD de XDOS (dia de 16 bits, hora, minuto, segundo en BCD)
TODADR: LD      HL,(SYSDAT)
        LD      L,252
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        RET



; ISTMP: Z si el proceso que corre es un TMP (nombre "Tmp..."). Los TMP corren
; en el banco 0, asi que el historial de ordenes vive en la parte con bancos.
; Conserva DE.
ISTMP:  PUSH    DE
        LD      HL,(RLRA)       ; rlr: el proceso que corre
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
        JP      Z,ZDT
        CP      31
        JP      Z,ZTK
        CP      10
        JP      Z,ZMNT
        CP      11
        JR      Z,ZQMP
        CP      36
        JR      Z,ZDRV
        CP      34
        JP      Z,ZI2C
        CP      40
        JP      Z,ZVC
        CP      41
        JP      Z,ZRAW
        CP      42
        JP      Z,ZFL
        CP      43
        JP      Z,ZWS
        CP      44
        JP      Z,ZCPU
        CP      45
        JP      Z,ZOUT
        CP      46
        JP      Z,ZBLK
ZERR:   LD      A,0FFh
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
; 11: mapa de unidades, 3 bytes por unidad (tarjeta, disco virtual) en (HL)
ZQMP:   LD      DE,(ZHL)
        LD      C,0
ZQ1:    LD      HL,ZMPB         ; (en la parte con bancos: A = tarjeta, HL = disco)
        CALL    ZBK
        EX      DE,HL
        LD      (HL),A
        INC     HL
        LD      (HL),E
        INC     HL
        LD      (HL),D
        INC     HL
        EX      DE,HL
        INC     C
        LD      A,C
        CP      NDRV
        JR      NZ,ZQ1
        XOR     A
        JR      ZRET
; 36: H = unidad -> A = tarjeta, DE = DSM, B = 0
ZDRV:   LD      A,(ZHL+1)
        CP      NDRV
        JR      NC,ZERR
        LD      C,A
        LD      HL,ZDRB         ; A = tarjeta, HL = DSM
        CALL    ZBK
        EX      DE,HL
        POP     BC
        POP     HL              ; (DE de quien llama: se devuelve DSM)
        POP     HL
        LD      B,0
        RET
; 10: B = 0, D = unidad, E = tarjeta SD (0/1), HL = disco virtual. Solo para
; unidades que ya estan en una SD. Antes se libera la unidad (BDOS 37): si
; alguien tiene archivos abiertos en ella, A = FF y no cambia nada.
ZMNT:   LD      A,B
        OR      A
        JP      NZ,ZERR
        LD      A,E
        CP      2
        JP      NC,ZERR
        LD      A,D
        CP      NDRV
        JP      NC,ZERR
        LD      C,D
        LD      HL,ZMPB         ; A = su tarjeta
        CALL    ZBK
        CP      2
        JP      NC,ZERR
        PUSH    DE
        LD      HL,1            ; vector de la unidad D
        INC     D
ZMN1:   DEC     D
        JR      Z,ZMN2
        ADD     HL,HL
        JR      ZMN1
ZMN2:   EX      DE,HL
        LD      C,37
        CALL    5
        POP     DE
        OR      A
        JP      NZ,ZERR
        LD      HL,ZMNB         ; la unidad D en la tarjeta E, disco (ZHL)
        CALL    ZBK
        XOR     A
        JP      ZRET

; 34: I2C. B = 0 escribir, 1 leer, 2 probar; D = direccion; E = bytes
; (0 = 256); HL = bufer. A = 0 bien, 1 sin respuesta (NAK), FF funcion invalida.
ZI2C:   LD      A,B             ; (el bus va en la parte con bancos: un BKCALL
        CP      3               ; por byte, con las interrupciones apagadas)
        JP      NC,ZERR
        LD      C,A
        LD      HL,I2CBEG       ; inicio y direccion (D, con el bit de C)
        CALL    ZBK
        JR      NZ,ZINAK
        LD      A,C
        CP      2
        JR      Z,ZIOK
        LD      HL,(ZHL)
        LD      B,E
        OR      A
        JR      NZ,ZIRD
ZIWR:   LD      E,(HL)
        INC     HL
        PUSH    HL
        LD      HL,I2CWB
        CALL    ZBK
        POP     HL
        JR      NZ,ZINAK
        DJNZ    ZIWR
        JR      ZIOK
ZIRD:   LD      E,0             ; el ultimo byte se contesta con NAK
        LD      A,B
        DEC     A
        JR      NZ,ZIR1
        INC     E
ZIR1:   PUSH    HL
        LD      HL,I2CRB
        CALL    ZBK
        POP     HL
        LD      (HL),A
        INC     HL
        DJNZ    ZIRD
ZIOK:   LD      HL,ISTOP
        CALL    ZBK
        XOR     A
        JP      ZRET
ZINAK:  LD      HL,ISTOP
        CALL    ZBK
        LD      A,1
        OR      A
        JP      ZRET
; 43 (propio): el registro de 128 bytes de HL a la unidad B, registro DE contado
; desde el principio de la unidad (tambien la pista de sistema: H:SETBOOT, que
; tiene MXDisk, asi nadie usa DIRBF). A = 0 bien.
ZWS:    LD      HL,(ZHL)
        LD      DE,DIRBF
        LD      BC,128
        LDIR
        POP     BC
        POP     DE
        PUSH    DE
        PUSH    BC
        LD      HL,WRSYS
        CALL    ZBK
        JP      ZRET
; 44 (propio): A = tics sin trabajo en el ultimo segundo (de 60; H:TOP)
ZCPU:   LD      A,(IDLES)
        JP      ZRET
; 45 (propio): el caracter E a la consola D (H:TALK)
ZOUT:   LD      C,E
        CALL    CONOUT
        XOR     A
        JP      ZRET
; 46 (propio): DE caracteres desde HL a la consola del programa, directo al
; XIOS: sin el BDOS (ni ^S, ni tabuladores, ni columna). Para los programas que
; dibujan la pantalla (MD, VI, CAT...): la mitad de ciclos por caracter.
ZBLK:   PUSH    DE
        CALL    ZCON
        POP     DE
        LD      B,C             ; B = consola
        LD      HL,(ZHL)
ZBL1:   LD      A,D
        OR      E
        JP      Z,ZRET          ; (A = 0)
        PUSH    HL
        PUSH    DE
        PUSH    BC
        LD      D,B
        LD      C,(HL)
        CALL    CONOUT
        POP     BC
        POP     DE
        POP     HL
        INC     HL
        DEC     DE
        JR      ZBL1
; ZCON: C = la consola del proceso que corre
ZCON:   LD      HL,(RLRA)
        LD      A,(HL)
        INC     HL
        LD      H,(HL)
        LD      L,A
        LD      DE,0Eh
        ADD     HL,DE
        LD      C,(HL)
        RET
; 42 (propio): lo que espera en BUF a la tarjeta (H:ZLOADER, con MXDisk)
ZFL:    LD      HL,FLUSHQ       ; (A = 0)
        CALL    ZBK
        JP      ZRET
; 40 (propio): ver la consola virtual E (0-4; H:VC)
ZVC:    LD      HL,VSWE
        CALL    ZBK
        DI
        CALL    TXSTA
        EI
        XOR     A
        JP      ZRET
; 41 (propio): modo crudo de la consola del programa, para H:XFER. B = 0
; prender (la consola tiene que ser la que se ve), 1 apagar, 2 recibir un
; byte (DE = tics de espera; A = byte, carry si no llego), 3 mandar E.
ZRAW:   PUSH    DE
        CALL    ZCON            ; C = la consola del proceso
        POP     DE
        LD      A,B
        CP      2
        JR      NC,ZRW1X
        LD      HL,ZRAWB        ; 0 prender, 1 apagar: en la parte con bancos
        CALL    ZBK
        JP      ZRET
ZRW1X:  DEC     A
ZRW2:   DEC     A
        JR      NZ,ZRW3
ZRW2A:  DI                      ; 2: recibir
        LD      HL,RAWGET
        CALL    BKCALL
        EI
        JR      NC,ZRW2B
        LD      A,D
        OR      E
        SCF
        JP      Z,ZRET          ; no llego
        DEC     DE
        PUSH    DE
        LD      C,141
        LD      DE,1
        CALL    5
        POP     DE
        JR      ZRW2A
ZRW2B:  OR      A
        JP      ZRET
ZRW3:   DEC     A               ; 4: A = la pagina del anillo (XFER lo lee
        JR      Z,ZRW3A         ; directo, con las interrupciones apagadas)
        LD      A,(VTAPG)
        JP      ZRET
ZRW3A:  LD      A,(RAWA)        ; 3: mandar
        DEC     A
        LD      HL,TXA
        LD      D,FLTXA
        JR      Z,ZRW3B
        LD      HL,TXB
        LD      D,FLTXB
ZRW3B:  LD      C,E
        LD      E,D
        CALL    TXPUT
        XOR     A
        JP      ZRET
; ZBK: BKCALL con las interrupciones apagadas; A y Z de la rutina
ZBK:    DI
        CALL    BKCALL
        EI
        OR      A
        RET



ZDT:    CALL    TODADR          ; copia de la hora de XDOS sin que el tic la cambie
        LD      DE,ZTOD
        LD      BC,5
        DI
        LDIR
        LD      HL,ZDTB         ; dia -> fecha, en la parte con bancos
        CALL    BKCALL
        EI
        LD      DE,(ZHL)        ; buffer: seg, min, hora, dia, mes, anio
        LD      HL,ZTOD+4
        LD      B,3
ZDT1:   LD      A,(HL)          ; seg, min, hora (al reves en el TOD)
        LD      (DE),A
        DEC     HL
        INC     DE
        DJNZ    ZDT1
        LD      HL,ZTOD+5       ; dia, mes, anio
        LD      BC,3
        LDIR
        XOR     A
        JP      ZRET
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
ZTOD:   DEFS    8               ; TOD de XDOS (5) y la fecha: dia, mes, anio

; ------------------------------------------------------------- datos (comun)
TICKN:  DEFB    0
TICKS:  DEFS    4               ; tics desde el arranque (servicio 31 de ZIOS)
IFLGN:  DEFB    0               ; bandera que pone IFLG (0 = es el tic)

SECS:   DEFW    0               ; segundos desde el arranque
PREEMP: DEFB    0
RXPEND: DEFB    0               ; hay algo en RAWQ por pasar por KEYIN
RTSHLD: DEFB    0               ; RTS abajo hasta que RAWQ baje de 256
RXACT:  DEFB    0               ; modo crudo: llego algo desde el ultimo tic
DSPV:   DEFW    0               ; a donde sigue el fin del tic
TDIV:   DEFB    2
TDIVN:  DEFB    2
CNTSEC: DEFB    TPS
CNTMIN: DEFB    60
SVHL:   DEFW    0
SVRET:  DEFW    0
SVSP:   DEFW    0
RXCNT:  DEFS    5               ; caracteres tecleados en cada consola virtual
SIOBM:  DEFB    0               ; consola 4: 0 la SIO B, 1 nada (OFF), 2 virtual
LASTPD: DEFW    0               ; proceso que escribio ultimo en la consola que se ve
RLRA:   DEFW    0               ; donde esta el proceso que corre (datapg+5)
IDLEC:  DEFB    0               ; tics del segundo en que la CPU no hacia nada
IDLES:  DEFB    TPS             ; los del segundo anterior
HDB:    DEFB    0
TLB:    DEFB    0
CURPG0: DEFB    0
VTPG:   DEFB    0               ; pagina de las pantallas de las consolas virtuales
VTAPG:  DEFB    0               ; y la de sus atributos
ACTVC:  DEFB    0               ; consola que se ve en la SIO A
VIEWING: DEFB   0               ; se esta mirando hacia atras (Shift-RePag)
RAWA:   DEFB    0               ; modo crudo (H:XFER): 1 en la SIO A, 2 en la B
GENACT: DEFB    0               ; la SIO A manda: 1 el redibujo, 2 la linea de estado
STATDUE: DEFB   0               ; toca la linea de estado
STATON: DEFB    0               ; linea de estado (A:MPM.CFG STATUS=ON)
SWCNT:  DEFB    0               ; cambios de consola
KTMO:   DEFB    0               ; tics para dar por terminada una secuencia ESC
BKSV:   DEFW    0
BKA:    DEFB    0
BNKPG:  DEFS    24              ; 3 paginas por banco, bancos 0-7
DMA:    DEFW    0

FIRMA:  DEFB    0
ZMAP    EQU     BUF             ; SYSINIT usa BUF para el mapa de ZIOS y su pila
LSTK    EQU     BUF+512
        DEFB    0               ; (el SPR termina con datos)
        END
