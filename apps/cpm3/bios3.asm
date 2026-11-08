;==================================================================================
; BIOS de CP/M 3 (CP/M Plus, version con bancos) para la Z80-Retro (peterw8102)
; sobre los servicios de ZIOS.
;
; Se ensambla con zmac (--rel7) y se enlaza con LINK de Digital Research:
;     LINK BNKBIOS3[B]=BIOS3,SCB
; y GENCPM lo junta con RESBDOS3.SPR y BNKBDOS3.SPR en CPM3.SYS.
;
; CSEG = memoria comun (C000-FDFF, la pagina 3 de la aplicacion).
; DSEG = parte en el banco 0 (sistema).
;
; Mapa de memoria (ventanas de 16K):
;   banco 0 (sistema): P0 P1 P2   (las paginas con las que ZLoader arranca la
;                                  aplicacion; ahi quedan BNKBDOS, la parte con
;                                  bancos del BIOS, hash, ALV y buffers de dir.)
;   banco 1 (TPA):     T0 T1 T2   (pedidas a ZIOS con el servicio 2)
;   banco 2 (buffers): X  P1 P2   (una pagina mas: buffers de datos de GENCPM
;                                  en 0000-2FFF y copia del CCP en 3000-3FFF)
;   comun:  C000-FDFF  (FE00-FFFF es de ZIOS: entrada de servicios y vectores)
;
; Todas las llamadas a ZIOS se hacen con CALL 0FE00h (no RST 30h) porque el
; vector de RST 30h vive en la pagina 0 de cada banco.
;==================================================================================

import zapi.asm

          extrn  @civec,@covec,@aivec,@aovec,@lovec
          extrn  @mxtpa,@date,@hour,@min,@sec

ZIOS      EQU    0FE00h       ; Entrada de los servicios de ZIOS
PGPORT    EQU    60h          ; Registros de pagina: 60h-63h = ventanas 0-3
NDRV      EQU    8            ; Unidades A-H
CCPBUF    EQU    3000h        ; Copia del CCP en el banco 2
CCPLEN    EQU    1000h        ; Hasta 4K de CCP
CCPMAX    EQU    CCPLEN/128   ; Registros de CCP.COM que se leen
BDOSF     EQU    5
CR        EQU    0Dh
LF        EQU    0Ah

RTC_ID    EQU    0D0h         ; DS1307 en el bus I2C (servicio 34)

;==================================================================================
          CSEG
;==================================================================================

; ----- Vector de entrada del BIOS (33 entradas) -----
BIOS:     JP     BOOT         ;  0 arranque en frio
WBOOTE:   JP     WBOOT        ;  1 arranque en caliente
          JP     CONST        ;  2
          JP     CONIN        ;  3
          JP     CONOUT       ;  4
          JP     LIST         ;  5
          JP     AUXOUT       ;  6
          JP     AUXIN        ;  7
          JP     HOME         ;  8
          JP     SELDSK       ;  9
          JP     SETTRK       ; 10
          JP     SETSEC       ; 11
          JP     SETDMA       ; 12
          JP     READ         ; 13
          JP     WRITE        ; 14
          JP     LISTST       ; 15
          JP     SECTRN       ; 16
          JP     CONOST       ; 17
          JP     AUXIST       ; 18
          JP     AUXOST       ; 19
          JP     DEVTBL       ; 20
          JP     DEVINI       ; 21
          JP     DRVTBL       ; 22
          JP     MULTIO       ; 23
          JP     FLUSH        ; 24
          JP     MOVE         ; 25
          JP     TIME         ; 26
          JP     SELMEM       ; 27
          JP     SETBNK       ; 28
          JP     XMOVE        ; 29
          JP     USERF        ; 30
          JP     0            ; 31 reservado
          JP     0            ; 32 reservado

; ---------------------------------------------------------------------------
; Tablas que tienen que estar en memoria comun
; ---------------------------------------------------------------------------

; Tabla de dispositivos de caracteres (DEVICE.COM). El numero de dispositivo
; es el mismo que el de ZIOS (B en los servicios 4/5/6):
;   0 SIOA  canal A de la SIO
;   1 CRT   consola de ZIOS (video+teclado si estan, si no el canal A)
;   2 SIOB  canal B de la SIO (si ZIOS lo tiene en modo serie general)
; Bit 15 del vector de redireccion = dispositivo 0, bit 14 = 1, bit 13 = 2.
MB_IO     EQU    3+8          ; entrada+salida, serie, velocidad fija
CHRTBL:   DB     'SIOA  ',MB_IO,0
          DB     'CRT   ',MB_IO,0
          DB     'SIOB  ',MB_IO,0
          DB     0
NCHR      EQU    3

; Tabla de unidades (DRVTBL). GENCPM la localiza por la instruccion LD HL,nn
; que tiene que ser la PRIMERA de DRVTBL.
DTBL:     DW     DPH0,DPH1,DPH2,DPH3,DPH4,DPH5,DPH6,DPH7
          DW     0,0,0,0,0,0,0,0

; DPB: el mismo formato que el CP/M 2.2 de apps/cpm22 (discos virtuales de 4 MB,
; bloques de 2K, 512 entradas de directorio, una pista de 64K reservada) mas
; los campos de CP/M 3 para sectores fisicos de 512 bytes. Tienen que estar en
; memoria comun (la funcion 31 del BDOS devuelve su direccion al programa).
; GENCPM dimensiona ALV y hash con DPBSD (el mayor); SELDSK cambia el DPB de
; la unidad al hacer login segun lo que diga ZIOS (servicio 36).
DPBSD:    DW     512          ; SPT: registros de 128 bytes por pista (64K)
          DB     4            ; BSH  bloques de 2K
          DB     15           ; BLM
          DB     0            ; EXM
          DW     2015         ; DSM  (4 MB - 64K reservados) / 2K - 1
          DW     511          ; DRM  512 entradas
          DB     0FFh,0       ; AL0, AL1: 8 bloques de directorio
          DW     8000h        ; CKS  disco fijo, sin vector de comprobacion
          DW     1            ; OFF  1 pista reservada (64K de sistema)
          DB     2            ; PSH  sectores fisicos de 512 bytes
          DB     3            ; PHM
; Discos en memoria de ZIOS (G: RAM, H: flash): 128 entradas, sin pistas
; reservadas; DSM y EXM se rellenan en SELDSK.
DPBRAM:   DW     512
          DB     4,15,1
          DW     0,127
          DB     0C0h,0
          DW     8000h,0
          DB     2,3
DPBFSH:   DW     512
          DB     4,15,1
          DW     0,127
          DB     0C0h,0
          DW     8000h,0
          DB     2,3

ZCALL     EQU    ZIOS         ; llamada a los servicios de ZIOS

; ---------------------------------------------------------------------------
; E/S de caracteres (todo en memoria comun: algunos programas llaman al BIOS
; directamente desde la TPA).
; ---------------------------------------------------------------------------

; CONST / AUXIST: 0FFh si algun dispositivo seleccionado tiene caracter.
CONST:    LD     HL,(@civec)
          JR     INSTAT
AUXIST:   LD     HL,(@aivec)
INSTAT:   CALL   FINDRDY
          LD     A,0
          RET    NC
          DEC    A
          RET

; FINDRDY: busca el primer dispositivo del vector HL con un caracter listo.
; Devuelve CY y B = dispositivo, o NC si ninguno.
FINDRDY:  LD     B,0
_frl:     LD     A,H
          OR     L
          RET    Z            ; (NC) ya no quedan bits
          ADD    HL,HL        ; bit 15 al acarreo
          JR     NC,_frn
          LD     A,B
          CP     NCHR
          JR     NC,_frn      ; dispositivo que ZIOS no tiene
          PUSH   HL
          PUSH   BC
          LD     C,A_CHKCH
          CALL   ZCALL
          POP    BC
          POP    HL
          OR     A
          SCF
          RET    NZ           ; listo: CY, B = dispositivo
_frn:     INC    B
          JR     _frl

; CONIN / AUXIN: espera un caracter del primer dispositivo listo.
CONIN:    LD     HL,(@civec)
          JR     CHRIN
AUXIN:    LD     HL,(@aivec)
CHRIN:    LD     A,H
          OR     L
          LD     A,1Ah        ; Sin dispositivo: fin de fichero
          RET    Z
_cil:     PUSH   HL
          CALL   FINDRDY
          POP    HL
          JR     NC,_cil
          LD     C,A_RXCHR    ; B = dispositivo
          JP     ZCALL        ; caracter en A

; CONOUT / LIST / AUXOUT: el caracter en C a todos los dispositivos del vector.
CONOUT:   LD     HL,(@covec)
          JR     CHROUT
LIST:     LD     HL,(@lovec)
          JR     CHROUT
AUXOUT:   LD     HL,(@aovec)
CHROUT:   LD     E,C
          LD     B,0
_col:     LD     A,H
          OR     L
          RET    Z
          ADD    HL,HL
          JR     NC,_con
          LD     A,B
          CP     NCHR
          JR     NC,_con
          PUSH   HL
          PUSH   DE
          PUSH   BC
          LD     C,A_TXCHR
          CALL   ZCALL
          POP    BC
          POP    DE
          POP    HL
_con:     INC    B
          JR     _col

; Estado de salida: siempre listo (ZIOS espera por su cuenta).
LISTST:
CONOST:
AUXOST:   LD     A,0FFh
          RET

DEVTBL:   LD     HL,CHRTBL
          RET

DEVINI:                       ; Las velocidades las fija ZLoader/ZIOS
USERF:    RET

DRVTBL:   LD     HL,DTBL      ; DEBE ser la primera instruccion (GENCPM)
          RET

SETBNK:   LD     (DBNK),A
          RET

; PMSG: escribe en la consola el texto acabado en 0 apuntado por HL.
PMSG:     LD     A,(HL)
          OR     A
          RET    Z
          PUSH   HL
          LD     C,A
          CALL   CONOUT
          POP    HL
          INC    HL
          JR     PMSG

; ---------------------------------------------------------------------------
; Gestion de memoria
; ---------------------------------------------------------------------------

; BNKENT: HL -> entrada de BNKTAB del banco A (3 paginas). Solo toca A, HL.
BNKENT:   PUSH   DE
          LD     E,A
          ADD    A,A
          ADD    A,E          ; A*3
          LD     E,A
          LD     D,0
          LD     HL,BNKTAB
          ADD    HL,DE
          POP    DE
          RET

; SELMEM: selecciona el banco A en las ventanas 0-2. Conserva todo salvo A.
; El cambio se hace con ZIOS para que quede en su mapa de paginas (PAGE_MP):
; ZIOS repone ese mapa al volver de cada servicio y en la interrupcion del CTC.
;
; El servicio 29 (A_PGMAP3) toma las paginas en B (banco 0), E (banco 1) y D
; (banco 2). Una version previa de ZIOS v5 leia el banco 1 de C (que es el
; numero de servicio); por eso el banco 1 se vuelve a fijar con el servicio 1.
; Con el ZIOS actual esa segunda llamada es redundante pero inofensiva.
SELMEM:   LD     (CURBNK),A
          PUSH   BC
          PUSH   DE
          PUSH   HL
          CALL   BNKENT
          LD     B,(HL)       ; ventana 0
          INC    HL
          LD     E,(HL)       ; ventana 1
          INC    HL
          LD     D,(HL)       ; ventana 2
          PUSH   DE
          LD     C,A_PGMAP3
          CALL   ZCALL
          POP    DE
          LD     D,E          ; pagina de la ventana 1
          LD     E,1
          LD     C,A_PGSEL
          CALL   ZCALL
          POP    HL
          POP    DE
          POP    BC
          RET

; XMOVE: B = banco destino, C = banco origen para el siguiente MOVE.
XMOVE:    LD     A,C
          LD     (XSB),A
          LD     A,B
          LD     (XDB),A
          LD     A,1
          LD     (XFLAG),A
          RET

; MOVE: HL = destino, DE = origen, BC = cuenta. Devuelve HL y DE avanzados.
MOVE:     LD     A,(XFLAG)
          OR     A
          JR     NZ,_xmv
          EX     DE,HL
          LDIR
          EX     DE,HL
          RET
_xmv:     XOR    A
          LD     (XFLAG),A
          ; y sigue en XCOPY con los bancos de XMOVE

; XCOPY: copia BC bytes del banco (XSB) direccion DE al banco (XDB) direccion
; HL. Devuelve DE y HL avanzados. Las direcciones C000-FFFF son comunes.
; Mapea directamente (con las interrupciones desactivadas) la pagina de origen
; en la ventana 1 y la de destino en la ventana 2, copia como mucho 128 bytes
; (o hasta el final de cualquiera de las dos paginas) y repone las ventanas 1
; y 2 del banco actual. Este codigo, sus datos y la pila estan en memoria comun.
XCOPY:    LD     (XCNT),BC
          LD     (XSRC),DE
          LD     (XDST),HL
          LD     A,B
          OR     C
          RET    Z
_xl:      LD     DE,(XSRC)    ; --- origen ---
          LD     A,(XSB)
          CALL   PHYS
          LD     (XSPG),A
          LD     (XSPTR),IX
          LD     (XLIM),IY
          LD     DE,(XDST)    ; --- destino ---
          LD     A,(XDB)
          CALL   PHYS
          LD     (XDPG),A
          OR     A
          JR     Z,_xd1
          LD     BC,4000h     ; el destino va por la ventana 2
          ADD    IX,BC
_xd1:     LD     (XDPTR),IX
          LD     BC,(XCNT)    ; n = min(cuenta, 128, limites)
          LD     HL,128
          CALL   MINBC
          LD     HL,(XLIM)
          CALL   MINBC
          PUSH   IY
          POP    HL
          CALL   MINBC
          LD     (XN),BC
          LD     HL,(XSPTR)
          LD     DE,(XDPTR)
          DI
          LD     A,(XSPG)
          OR     A
          JR     Z,_xc1
          OUT    (PGPORT+1),A
_xc1:     LD     A,(XDPG)
          OR     A
          JR     Z,_xc2
          OUT    (PGPORT+2),A
_xc2:     LDIR
          LD     A,(CURBNK)   ; reponer las ventanas 1 y 2 del banco actual
          CALL   BNKENT
          INC    HL
          LD     A,(HL)
          OUT    (PGPORT+1),A
          INC    HL
          LD     A,(HL)
          OUT    (PGPORT+2),A
          EI
          LD     BC,(XN)      ; avanzar
          LD     HL,(XSRC)
          ADD    HL,BC
          LD     (XSRC),HL
          LD     HL,(XDST)
          ADD    HL,BC
          LD     (XDST),HL
          LD     HL,(XCNT)
          OR     A
          SBC    HL,BC
          LD     (XCNT),HL
          JR     NZ,_xl
          LD     DE,(XSRC)
          LD     HL,(XDST)
          RET

; MINBC: BC = min(BC, HL) sin signo. Conserva HL.
MINBC:    PUSH   HL
          OR     A
          SBC    HL,BC
          POP    HL
          RET    NC
          LD     B,H
          LD     C,L
          RET

; PHYS: direccion DE del banco A.
;   Comun (>= C000): A = 0, IX = DE, IY = 10000h - DE.
;   Si no:  A = pagina fisica, IX = 4000h + (DE and 3FFFh) (en la ventana 1),
;           IY = 4000h - (DE and 3FFFh).
PHYS:     PUSH   HL
          PUSH   BC
          LD     C,A
          LD     A,D
          CP     0C0h
          JR     C,_ph1
          LD     IX,0
          ADD    IX,DE
          LD     HL,0
          OR     A
          SBC    HL,DE
          PUSH   HL
          POP    IY
          XOR    A
          JR     _ph9
_ph1:     LD     A,C
          CALL   BNKENT
          LD     A,D
          RLCA
          RLCA
          AND    3            ; ventana del banco (0-2)
          LD     C,A
          LD     B,0
          ADD    HL,BC
          LD     A,D
          AND    3Fh
          LD     B,A
          LD     C,E          ; BC = desplazamiento en la pagina
          PUSH   HL
          LD     HL,4000h
          OR     A
          SBC    HL,BC
          PUSH   HL
          POP    IY           ; limite
          LD     HL,4000h
          ADD    HL,BC
          PUSH   HL
          POP    IX           ; direccion en la ventana 1
          POP    HL
          LD     A,(HL)       ; pagina fisica
_ph9:     POP    BC
          POP    HL
          RET

; ---------------------------------------------------------------------------
; Arranque en frio. CPMLDR salta aqui con el banco 0 (las paginas iniciales de
; la aplicacion) seleccionado.
; ---------------------------------------------------------------------------
BOOT:     LD     SP,STACK
          ; Paginas para el banco 1 (TPA) y el banco 2
          LD     HL,BNKTAB+3
          LD     B,4
_bal:     PUSH   BC
          PUSH   HL
          LD     C,A_PGALC
          CALL   ZCALL
          POP    HL
          POP    BC
          OR     A
          JP     Z,NOMEM
          LD     (HL),A
          INC    HL
          DJNZ   _bal         ; T0 T1 T2 X  -> BNKTAB+3..+6
          ; Paginas actuales de las ventanas 1 y 2 (servicio 1: devuelve la
          ; anterior). Se pone una de las nuevas y se repone la de antes.
          LD     E,1
          CALL   GETPG
          LD     (BNKTAB+1),A
          LD     (BNKTAB+7),A
          LD     E,2
          CALL   GETPG
          LD     (BNKTAB+2),A
          LD     (BNKTAB+8),A
          ; La de la ventana 0 no se puede leer asi (ZIOS corre en la ventana 0
          ; durante el servicio). Se busca: se escribe una firma en 0040h y se
          ; mira por la ventana 1 que pagina de RAM la tiene.
          CALL   FINDP0
          JP     Z,NOMEM
          LD     (BNKTAB),A
          XOR    A
          LD     (CURBNK),A
          ; Vectores de redireccion: consola a CRT, AUX a SIOB, LST a SIOA
          LD     HL,4000h
          LD     (@civec),HL
          LD     (@covec),HL
          LD     HL,2000h
          LD     (@aivec),HL
          LD     (@aovec),HL
          LD     HL,8000h
          LD     (@lovec),HL
          LD     HL,SIGNON
          CALL   PMSG
          XOR    A
          LD     (CCPOK),A
          ; y sigue como un arranque en caliente (cargando CCP.COM del disco)

; ---------------------------------------------------------------------------
; Arranque en caliente
; ---------------------------------------------------------------------------
WBOOT:    LD     SP,STACK
          CALL   SETJMP       ; banco 1 y saltos de la pagina 0
          LD     A,(CCPOK)
          OR     A
          JR     Z,LDCCP
          ; CCP desde la copia del banco 2
          LD     A,2
          LD     (XSB),A
          DEC    A
          LD     (XDB),A
          LD     DE,CCPBUF
          LD     HL,0100h
          LD     BC,CCPLEN
          CALL   XCOPY
          JP     0100h

; LDCCP: carga A:CCP.COM en 0100h (banco 1) con llamadas al BDOS y lo copia
; al banco 2 para los siguientes arranques en caliente.
LDCCP:    XOR    A
          LD     HL,CCPFCB+12 ; EX, S1, S2, RC
          LD     (HL),A
          INC    HL
          LD     (HL),A
          INC    HL
          LD     (HL),A
          INC    HL
          LD     (HL),A
          LD     (CCPFCB+32),A ; registro actual
          LD     DE,CCPFCB
          LD     C,15         ; abrir
          CALL   BDOSF
          INC    A
          JR     Z,NOCCP
          LD     DE,0100h
          LD     C,26         ; DMA
          CALL   BDOSF
          LD     E,CCPMAX
          LD     C,44         ; varios registros de una vez
          CALL   BDOSF
          LD     DE,CCPFCB
          LD     C,20         ; leer (al llegar al final devuelve 1: normal)
          CALL   BDOSF
          LD     E,1
          LD     C,44
          CALL   BDOSF
          LD     A,1
          LD     (XSB),A
          INC    A
          LD     (XDB),A
          LD     DE,0100h
          LD     HL,CCPBUF
          LD     BC,CCPLEN
          CALL   XCOPY
          LD     A,1
          LD     (CCPOK),A
          JP     0100h

NOCCP:    LD     HL,MNOCCP
          CALL   PMSG
          CALL   CONIN
          JR     WBOOT

; NOMEM: no se pudo preparar la memoria: volver a ZLoader.
NOMEM:    LD     HL,MNOMEM
          CALL   PMSG
          LD     C,A_EXIT
          JP     ZCALL

; SETJMP: selecciona el banco 1 y pone los saltos de la pagina 0.
SETJMP:   LD     A,1
          CALL   SELMEM
          LD     A,0C3h       ; JP
          LD     (0000h),A
          LD     HL,WBOOTE
          LD     (0001h),HL
          LD     (0005h),A
          LD     HL,(@mxtpa)
          LD     (0006h),HL
          LD     (0030h),A    ; RST 30h -> servicios de ZIOS (como en CP/M 2.2)
          LD     HL,ZIOS
          LD     (0031h),HL
          RET

; GETPG: pagina actual de la ventana E (1 o 2). Pone la pagina X un momento.
GETPG:    PUSH   DE
          LD     A,(BNKTAB+6)
          LD     D,A
          LD     C,A_PGSEL
          CALL   ZCALL        ; A = pagina anterior
          POP    DE
          PUSH   AF
          LD     D,A
          LD     C,A_PGSEL
          CALL   ZCALL        ; reponerla
          POP    AF
          RET

; FINDP0: pagina fisica de la ventana 0. Devuelve A = pagina y NZ, o Z si no
; la encuentra. Usa 0040h-0047h del banco 0 (libres) y la ventana 1, y mira
; las paginas de RAM que dice ZIOS (servicio 35: incluye la RAM de expansion).
FINDP0:   LD     C,A_MEMINV   ; A = paginas de RAM instaladas (desde la 20h)
          CALL   ZCALL
          OR     A
          JR     NZ,_fpm
          LD     A,20h
_fpm:     ADD    A,20h
          JR     NC,_fpn
          LD     A,0FFh       ; (la FFh es la memoria de video: no se mira)
_fpn:     LD     (FPEND),A
          LD     HL,0040h
          LD     B,8
          LD     A,R
_fp0:     LD     (HL),A
          ADD    A,37
          INC    HL
          DJNZ   _fp0
          LD     A,20h        ; primera pagina de RAM
_fp1:     LD     (FPPG),A
          LD     D,A
          LD     E,1
          LD     C,A_PGSEL
          CALL   ZCALL        ; candidata en la ventana 1
          CALL   CMP40
          JR     NZ,_fp2
          ; Coincide: cambiar la firma y ver que cambia tambien alli
          LD     HL,0040h
          LD     A,(HL)
          CPL
          LD     (HL),A
          CALL   CMP40
          JR     Z,_fp3       ; es esta
_fp2:     LD     A,(FPEND)
          LD     B,A
          LD     A,(FPPG)
          INC    A
          CP     B
          JR     C,_fp1
          CALL   _fpr
          XOR    A            ; Z: no encontrada
          RET
_fp3:     CALL   _fpr
          LD     A,(FPPG)
          OR     A            ; NZ (es >= 20h)
          RET
_fpr:     LD     A,(BNKTAB+1)  ; reponer la ventana 1
          LD     D,A
          LD     E,1
          LD     C,A_PGSEL
          JP     ZCALL
CMP40:    LD     HL,0040h
          LD     DE,4040h
          LD     B,8
_cm1:     LD     A,(DE)
          CP     (HL)
          RET    NZ
          INC    HL
          INC    DE
          DJNZ   _cm1
          RET                 ; Z

; ---------------------------------------------------------------------------
; Datos en memoria comun
; ---------------------------------------------------------------------------
SIGNON:   DB     CR,LF,'CP/M 3 con bancos para Z80-Retro (ZIOS)',CR,LF,0
MNOCCP:   DB     CR,LF,'BIOS: falta A:CCP.COM - pulse una tecla',0
MNOMEM:   DB     CR,LF,'BIOS: no hay paginas de memoria para los bancos',CR,LF,0

CCPFCB:   DB     1,'CCP     COM',0,0,0,0
          DW     0,0,0,0,0,0,0,0
          DB     0,0,0,0

; Paginas fisicas de cada banco (ventanas 0, 1, 2)
BNKTAB:   DB     0,0,0        ; banco 0
          DB     0,0,0        ; banco 1
          DB     0,0,0        ; banco 2
CURBNK:   DB     0
DBNK:     DB     0            ; banco del DMA de disco (SETBNK)
XSB:      DB     0            ; XMOVE: banco origen
XDB:      DB     0            ;        banco destino
XFLAG:    DB     0
XSPG:     DB     0
XDPG:     DB     0
XSPTR:    DW     0
XDPTR:    DW     0
XCNT:     DW     0
XSRC:     DW     0
XDST:     DW     0
XLIM:     DW     0
XN:       DW     0
CCPOK:    DB     0
FPPG:     DB     0
FPEND:    DB     0

          DS     96
STACK:

;==================================================================================
          DSEG                ; Banco 0
;==================================================================================

; DPH de las unidades A-H. GENCPM rellena ALV, buffers y tabla de hash (0FFFEh).
DPHM      MACRO
          DW     0            ; XLT: sin traduccion
          DB     0,0,0,0,0,0,0,0,0
          DB     0            ; MF
          DW     DPBSD
          DW     0FFFEh       ; CSV (CKS=8000h: tamano 0)
          DW     0FFFEh       ; ALV
          DW     0FFFEh       ; DIRBCB
          DW     0FFFEh       ; DTABCB
          DW     0FFFEh       ; HASH
          DB     0            ; HBANK
          ENDM

DPH0:     DPHM
DPH1:     DPHM
DPH2:     DPHM
DPH3:     DPHM
DPH4:     DPHM
DPH5:     DPHM
DPH6:     DPHM
DPH7:     DPHM

; ---------------------------------------------------------------------------
; E/S de disco (solo la llama el BDOS, con el banco 0 seleccionado)
; ---------------------------------------------------------------------------
SELDSK:   LD     HL,0
          LD     A,C
          CP     NDRV
          RET    NC
          LD     (ADRV),A
          LD     L,A
          ADD    HL,HL
          LD     BC,DTBL
          ADD    HL,BC
          LD     A,(HL)
          INC    HL
          LD     H,(HL)
          LD     L,A          ; HL = DPH
          BIT    0,E
          RET    NZ           ; ya conocida
          ; Primer acceso (login): que hay en la unidad (servicio 36)
          PUSH   HL
          LD     A,(ADRV)
          LD     H,A
          LD     C,A_DRVINF
          CALL   ZCALL        ; A = tipo, DE = DSM, B = solo lectura
          PUSH   AF
          LD     A,(ADRV)
          LD     HL,ROTAB
          ADD    A,L
          LD     L,A
          LD     A,H
          ADC    A,0
          LD     H,A
          LD     (HL),B       ; marca de solo lectura
          POP    AF
          LD     HL,DPBSD
          CP     2
          JR     C,_sdph      ; tarjeta SD
          CP     0FFh
          JR     Z,_sno       ; disco en memoria que no esta
          LD     HL,DPBRAM
          CP     2
          JR     Z,_smd
          LD     HL,DPBFSH
_smd:     PUSH   HL
          LD     BC,4
          ADD    HL,BC
          LD     (HL),1       ; EXM = 1 con DSM < 256
          LD     A,D
          OR     A
          JR     Z,_sex
          LD     (HL),0       ; EXM = 0 con DSM >= 256
_sex:     INC    HL
          LD     (HL),E       ; DSM
          INC    HL
          LD     (HL),D
          POP    HL
_sdph:    EX     DE,HL        ; DE = DPB
          POP    HL           ; DPH
          PUSH   HL
          LD     BC,12        ; campo DPB del DPH
          ADD    HL,BC
          LD     (HL),E
          INC    HL
          LD     (HL),D
          POP    HL
          RET
_sno:     POP    HL
          LD     HL,0
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
MULTIO:   RET                 ; Cada READ/WRITE trae su DMA: se ignora la cuenta
FLUSH:    XOR    A            ; No hay buffers propios
          RET

; READ / WRITE: un sector fisico de 512 bytes.
;   Direccion logica de ZIOS (servicios 13/15): H = unidad, L = 0,
;   DE = pista*128 + sector (sectores de 512 bytes dentro del disco de 4 MB).
READ:     LD     A,A_DSKRD
          JR     RWCOM
WRITE:    LD     A,(ADRV)     ; disco de solo lectura (flash): codigo 2
          LD     HL,ROTAB
          ADD    A,L
          LD     L,A
          LD     A,H
          ADC    A,0
          LD     H,A
          LD     A,(HL)
          OR     A
          LD     A,2
          RET    NZ
          LD     A,A_DSKWR
RWCOM:    LD     (RWFN),A
          LD     A,3          ; intentos
_rwt:     LD     (TRIES),A
          CALL   RWONE
          OR     A
          RET    Z
          LD     A,(TRIES)
          DEC    A
          JR     NZ,_rwt
          CALL   PRTERR
          LD     A,1
          RET

RWONE:    CALL   SETZDMA      ; DMA directo o buffer intermedio
          LD     A,(BOUNCE)
          OR     A
          JR     Z,_rw1
          LD     A,(RWFN)
          CP     A_DSKWR
          JR     NZ,_rw1
          ; Escritura con buffer intermedio: copiar primero el sector
          LD     A,(DBNK)
          LD     (XSB),A
          XOR    A
          LD     (XDB),A
          LD     DE,(DMA)
          LD     HL,BNCBUF
          LD     BC,512
          CALL   XCOPY
_rw1:     LD     HL,(TRK)
          LD     H,L
          LD     L,0
          SRL    H
          RR     L            ; HL = pista * 128
          LD     DE,(SECT)
          ADD    HL,DE
          EX     DE,HL
          LD     A,(ADRV)
          LD     H,A
          LD     L,0
          LD     A,(RWFN)
          LD     C,A
          CALL   ZCALL
          ; ZIOS v5: la escritura en la SD devuelve A = 5 si fue bien (la
          ; respuesta de datos de la tarjeta); los discos en memoria y las
          ; lecturas devuelven 0.
          CP     5
          JR     NZ,_rw2
          LD     A,(RWFN)
          CP     A_DSKWR
          LD     A,5
          JR     NZ,_rw2
          XOR    A
_rw2:     OR     A
          RET    NZ           ; error
          LD     A,(BOUNCE)
          OR     A
          RET    Z            ; A = 0
          LD     A,(RWFN)
          CP     A_DSKRD
          LD     A,0
          RET    NZ
          ; Lectura con buffer intermedio: copiar al destino
          XOR    A
          LD     (XSB),A
          LD     A,(DBNK)
          LD     (XDB),A
          LD     DE,BNCBUF
          LD     HL,(DMA)
          LD     BC,512
          CALL   XCOPY
          XOR    A
          RET

; SETZDMA: indica a ZIOS donde va el sector.
;  - banco 0 (el seleccionado) o memoria comun: servicio 12 (direccion normal;
;    ZIOS ya sabe cruzar de una pagina a la siguiente del banco).
;  - otro banco: servicio 30 con la pagina fisica, si el sector no cruza el
;    final de la pagina; si lo cruza, buffer intermedio en el banco 0.
SETZDMA:  XOR    A
          LD     (BOUNCE),A
          LD     HL,(DMA)
          LD     A,(DBNK)
          OR     A
          JR     Z,_sz1
          LD     A,H
          CP     0C0h
          JR     NC,_sz1
          AND    3Fh
          CP     3Eh
          JR     C,_sz2       ; desplazamiento < 3E00h: cabe en la pagina
          JR     NZ,_szb
          LD     A,L
          OR     A
          JR     NZ,_szb      ; 3E01h-3FFFh: cruza
_sz2:     LD     A,(DBNK)
          LD     D,H
          LD     E,L
          CALL   PHYS         ; A = pagina, IX = 4000h + desplazamiento
          PUSH   IX
          POP    HL
          LD     B,A
          LD     A,H
          SUB    40h
          LD     H,A          ; HL = desplazamiento
          LD     C,A_EDMA
          JP     ZCALL
_szb:     LD     A,1
          LD     (BOUNCE),A
          LD     HL,BNCBUF
_sz1:     LD     C,A_DSKDM
          JP     ZCALL

; PRTERR: avisa en la consola del error de la tarjeta.
PRTERR:   LD     HL,MERR1
          CALL   PMSG
          LD     A,(ADRV)
          ADD    A,'A'
          LD     C,A
          CALL   CONOUT
          LD     HL,MERR2
          CALL   PMSG
          LD     HL,(TRK)
          CALL   PHEX16
          LD     HL,MERR3
          CALL   PMSG
          LD     HL,(SECT)
          CALL   PHEX16
          LD     HL,MERR4
          JP     PMSG

PHEX16:   LD     A,H
          CALL   PHEX8
          LD     A,L
PHEX8:    PUSH   AF
          RRCA
          RRCA
          RRCA
          RRCA
          CALL   PHEX4
          POP    AF
PHEX4:    AND    0Fh
          ADD    A,90h
          DAA
          ADC    A,40h
          DAA
          PUSH   HL
          LD     C,A
          CALL   CONOUT
          POP    HL
          RET

MERR1:    DB     CR,LF,'BIOS: error de lectura/escritura en la SD, unidad ',0
MERR2:    DB     ': pista ',0
MERR3:    DB     ' sector ',0
MERR4:    DB     CR,LF,0

; ---------------------------------------------------------------------------
; TIME: C = 0 leer el reloj al SCB, C = 0FFh poner el reloj desde el SCB.
; Conserva HL y DE. @DATE = dias desde el 31/12/1977 (1 = 1/1/1978).
; ---------------------------------------------------------------------------
TIME:     PUSH   HL
          PUSH   DE
          LD     A,C
          OR     A
          JR     NZ,TSET
          LD     HL,TBUF
          LD     C,A_DTIME
          CALL   ZCALL
          LD     A,(TBUF+ZT_SEC)
          LD     (@sec),A
          LD     A,(TBUF+ZT_MIN)
          LD     (@min),A
          LD     A,(TBUF+ZT_HOUR)
          LD     (@hour),A
          ; Ano: 78-99 -> 1978-1999, 00-77 -> 2000-2077. YOFF = ano - 1978
          LD     A,(TBUF+ZT_YEAR)
          CALL   BCD2BIN
          SUB    78
          JR     NC,_ty1
          ADD    A,100
_ty1:     LD     (YOFF),A
          ; dias de los anos completos
          LD     HL,0
          LD     B,A
          LD     C,0          ; C = ano en curso (desplazamiento)
          INC    B
_ty2:     DEC    B
          JR     Z,_ty3
          LD     A,C
          CALL   YLEN         ; DE = 365/366
          ADD    HL,DE
          INC    C
          JR     _ty2
_ty3:     ; meses completos
          LD     A,(TBUF+ZT_MNTH)
          CALL   BCD2BIN
          LD     B,A
          LD     C,1
_ty4:     LD     A,C
          CP     B
          JR     NC,_ty5
          CALL   MLEN         ; E = dias del mes C
          LD     D,0
          ADD    HL,DE
          INC    C
          JR     _ty4
_ty5:     LD     A,(TBUF+ZT_DATE)
          CALL   BCD2BIN
          LD     E,A
          LD     D,0
          ADD    HL,DE
          LD     (@date),HL
          POP    DE
          POP    HL
          RET

; Poner la hora: @DATE -> dia/mes/ano y escribir el DS1307
TSET:     LD     HL,(@date)
          ; dia de la semana (1 = domingo; el 1/1/1978 fue domingo)
          PUSH   HL
          DEC    HL
          LD     DE,7000
_ts0:     OR     A
          SBC    HL,DE
          JR     NC,_ts0
          ADD    HL,DE
          LD     DE,7
_ts0b:    OR     A
          SBC    HL,DE
          JR     NC,_ts0b
          ADD    HL,DE
          LD     A,L
          INC    A
          LD     (TBUF+7),A   ; DOW
          POP    HL
          ; anos
          LD     C,0
_ts1:     LD     A,C
          CALL   YLEN
          PUSH   HL
          OR     A
          SBC    HL,DE        ; quedan > YLEN ?
          JR     C,_ts2
          JR     Z,_ts2
          POP    AF           ; descartar
          INC    C
          JR     _ts1
_ts2:     POP    HL
          LD     A,C
          LD     (YOFF),A
          ; meses
          LD     C,1
_ts3:     CALL   MLEN
          LD     D,0
          PUSH   HL
          OR     A
          SBC    HL,DE
          JR     C,_ts4
          JR     Z,_ts4
          POP    AF
          INC    C
          JR     _ts3
_ts4:     POP    HL           ; L = dia
          LD     A,L
          CALL   BIN2BCD
          LD     (TBUF+ZT_DATE),A
          LD     A,C
          CALL   BIN2BCD
          LD     (TBUF+ZT_MNTH),A
          LD     A,(YOFF)
          ADD    A,78
          CP     100
          JR     C,_ts5
          SUB    100
_ts5:     CALL   BIN2BCD
          LD     (TBUF+ZT_YEAR),A
          ; Registros 0-6 del DS1307 con el servicio 34 de ZIOS (I2C):
          ; registro inicial, seg, min, hora, dia semana, dia, mes, ano
          XOR    A
          LD     (I2CB),A
          LD     A,(@sec)
          AND    7Fh          ; CH = 0: reloj en marcha
          LD     (I2CB+1),A
          LD     A,(@min)
          LD     (I2CB+2),A
          LD     A,(@hour)
          AND    3Fh          ; modo 24 horas
          LD     (I2CB+3),A
          LD     A,(TBUF+7)
          LD     (I2CB+4),A
          LD     A,(TBUF+ZT_DATE)
          LD     (I2CB+5),A
          LD     A,(TBUF+ZT_MNTH)
          LD     (I2CB+6),A
          LD     A,(TBUF+ZT_YEAR)
          LD     (I2CB+7),A
          LD     B,0          ; escribir
          LD     D,RTC_ID
          LD     E,8
          LD     HL,I2CB
          LD     C,A_I2C
          CALL   ZCALL
          POP    DE
          POP    HL
          RET

; YLEN: DE = dias del ano con desplazamiento A desde 1978 (bisiesto si
; (A and 3) = 2: 1980, 1984, ... 2000 tambien es bisiesto).
YLEN:     LD     DE,365
          AND    3
          CP     2
          RET    NZ
          INC    DE
          RET

; MLEN: E = dias del mes C (1-12) del ano YOFF.
MLEN:     PUSH   HL
          LD     HL,MDAYS-1
          LD     A,C
          ADD    A,L
          LD     L,A
          LD     A,H
          ADC    A,0
          LD     H,A
          LD     E,(HL)
          POP    HL
          LD     A,C
          CP     2
          RET    NZ
          LD     A,(YOFF)
          AND    3
          CP     2
          RET    NZ
          INC    E
          RET
MDAYS:    DB     31,28,31,30,31,30,31,31,30,31,30,31

BCD2BIN:  PUSH   BC
          LD     B,A
          AND    0F0h
          RRCA
          LD     C,A          ; decenas*8
          RRCA
          RRCA                ; decenas*2
          ADD    A,C          ; decenas*10
          LD     C,A
          LD     A,B
          AND    0Fh
          ADD    A,C
          POP    BC
          RET

BIN2BCD:  PUSH   BC
          LD     B,0
_b2b:     SUB    10
          JR     C,_b2c
          INC    B
          JR     _b2b
_b2c:     ADD    A,10
          LD     C,A
          LD     A,B
          RLCA
          RLCA
          RLCA
          RLCA
          OR     C
          POP    BC
          RET

; ---------------------------------------------------------------------------
; Datos del banco 0
; ---------------------------------------------------------------------------
ADRV:     DB     0
TRK:      DW     0
SECT:     DW     0
DMA:      DW     0
RWFN:     DB     0
TRIES:    DB     0
BOUNCE:   DB     0
YOFF:     DB     0
TBUF:     DS     Z_BUFSZ
I2CB:     DS     8
ROTAB:    DS     NDRV         ; 1 = unidad de solo lectura
BNCBUF:   DS     512          ; buffer intermedio para sectores que cruzan pagina

          END
