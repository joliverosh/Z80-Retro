; XFER.COM - MP/M II ZEPHYRUS: pasa archivos por XMODEM y YMODEM por la consola
; del programa, sin sacar la SD.
;   XFER R ARCHIVO.EXT   recibe por XMODEM (128 o 1K, CRC o suma; en oli: sx o sx -k)
;   XFER R [d:]          recibe por YMODEM uno o varios archivos con su nombre (sb)
;   XFER S ARCHIVO.EXT   manda por XMODEM (en oli: rx ARCHIVO)
;   XFER S d:*.COM       manda por YMODEM los que coinciden, con su nombre (rb)
; Usa el servicio 41 del XIOS (modo crudo: los bytes pasan tal cual, sin las
; teclas de las consolas virtuales ni la linea de estado). La consola tiene que
; ser la que se ve en el terminal. (C) OLIVEROS 2026
BDOS    EQU     5
FCB1    EQU     5Ch
FCB2    EQU     6Ch
DMA0    EQU     80h
SOH     EQU     01h
STX     EQU     02h
EOT     EQU     04h
ACK     EQU     06h
NAK     EQU     15h
CAN     EQU     18h
TPS     EQU     60              ; tics por segundo
MAXN    EQU     128             ; nombres que junta XFER S con comodines

        ORG     100h
        LD      SP,PILA
        LD      C,12            ; MP/M? (BDOS 12: H = 1)
        CALL    BDOS
        LD      A,H
        DEC     A
        LD      DE,MNOMPM
        JP      NZ,FIN
        CALL    TABCRC
        LD      HL,FCB2         ; FCB propio
        LD      DE,FCB
        LD      BC,12
        LDIR
        CALL    FCBZ            ; el resto en cero (FCB esta fuera del .COM)
        LD      A,(FCB1+1)
        AND     5Fh
        CP      'R'
        JR      Z,RECIBE
        CP      'S'
        JP      Z,MANDA
USO:    LD      DE,MUSO
        JP      FIN

; FCBZ: FCB+12..35 en cero
FCBZ:   LD      HL,FCB+12
        LD      B,24
FZ1:    LD      (HL),0
        INC     HL
        DJNZ    FZ1
        RET

; ============================================================= recibir
RECIBE: LD      A,(FCB+1)       ; sin nombre: YMODEM
        CP      ' '
        JP      Z,YREC
        CALL    CREAR
        LD      DE,MREC
        CALL    PRINT
        CALL    CRUDO
        JP      NZ,NOVIS
        LD      A,'C'
        LD      (MODO),A
        CALL    PRIMER          ; A = primer byte del primer bloque
        JP      C,RTMO
        LD      HL,0FFFFh       ; XMODEM: sin limite de registros
        LD      (RESTAN),HL
        CALL    DATOS
        JP      NZ,RFALLA
        CALL    CERRAR
        LD      DE,MOKR
        JP      FINCNT

; CREAR: borra y crea FCB. Si no puede, termina.
CREAR:  LD      DE,FCB
        LD      C,19
        CALL    BDOS
        CALL    FCBZ
        LD      DE,FCB
        LD      C,22
        CALL    BDOS
        INC     A
        RET     NZ
        CALL    NORMAL
        LD      DE,MNOCREA
        JP      FIN
CERRAR: LD      DE,FCB
        LD      C,16
        JP      BDOS
BORRAR: LD      DE,FCB          ; un archivo a medias no queda (un A:MPM.SYS
        LD      C,19            ; cortado no arrancaria)
        JP      BDOS

; PRIMER: pide el primer bloque (MODO: 'C' = CRC; tras 6 intentos pasa a suma,
; salvo YMODEM) cada 3 s, 20 veces. A = primer byte; carry si nada.
PRIMER: LD      B,20
PR1:    PUSH    BC
        LD      A,B
        CP      8               ; (tras 12 intentos con C, suma)
        JR      NZ,PR2
        LD      A,(YMOD)
        OR      A
        JR      NZ,PR2
        LD      A,NAK
        LD      (MODO),A
PR2:    LD      A,(MODO)
        CALL    PUTB
        LD      DE,3*TPS
        CALL    GETB
        POP     BC
        RET     NC
        DJNZ    PR1
        SCF
        RET

; DATOS: los bloques 1, 2... hasta EOT, al archivo FCB. A = primer byte del
; primero. RESTAN = registros que faltan (YMODEM, por el tamano). Z = bien.
DATOS:  LD      B,A             ; (el primer byte)
        LD      A,1
        LD      (BLQ),A
        XOR     A
        LD      (ERRS),A
        LD      A,B
        JR      DT1B
DT1:    LD      DE,10*TPS       ; el siguiente bloque
        CALL    GETB
        JR      C,DTMAL2
DT1B:   CALL    RBODY           ; 0 bloque, 1 EOT, 2 CAN, 3 mal
        OR      A
        JR      Z,DT2
        DEC     A
        JR      Z,DTFIN
        DEC     A
        JR      Z,DTCAN
        JR      DTMAL2
DT2:    LD      A,(NUM)         ; el que tocaba, o el anterior repetido
        LD      HL,BLQ
        CP      (HL)
        JR      Z,DT3
        INC     A
        CP      (HL)
        JR      Z,DTACK
        LD      A,(NUM)         ; fuera de orden: se anota (para el mensaje) y
        LD      (MALN),A        ; cuenta como error: NAK y que lo mande otra vez
        LD      A,(HL)
        LD      (MALE),A
        CALL    PURGA
        JR      DTMAL2
DT3:    CALL    GRABAR
        JR      NZ,DTDISCO
        LD      HL,BLQ
        INC     (HL)
        LD      HL,(CUENTA)
        INC     HL
        LD      (CUENTA),HL
        XOR     A
        LD      (ERRS),A
DTACK:  LD      A,ACK
        CALL    PUTB
        JR      DT1
DTMAL2: LD      HL,ERRS
        INC     (HL)
        LD      A,(HL)
        CP      10
        JR      NC,DTCANC
        LD      A,NAK
        CALL    PUTB
        JR      DT1
DTFIN:  LD      A,ACK
        CALL    PUTB
        XOR     A
        RET
DTDISCO: CALL   CANCEL
        LD      A,2
        OR      A
        RET
DTCANC: CALL    CANCEL
DTCAN:  LD      A,1
        OR      A
        RET

; GRABAR: los registros de BUF (LEN/128, no mas que RESTAN) al archivo. Z = bien.
GRABAR: LD      A,(LEN+1)       ; 128 -> 1, 1024 -> 8
        OR      A
        LD      B,1
        JR      Z,GR1
        LD      B,8
GR1:    LD      HL,BUF
GR2:    PUSH    BC
        PUSH    HL
        LD      HL,(RESTAN)
        LD      A,H
        OR      L
        JR      Z,GR8           ; (YMODEM: el relleno del ultimo bloque no va)
        DEC     HL
        LD      (RESTAN),HL
        POP     DE
        PUSH    DE
        LD      C,26
        CALL    BDOS
        LD      DE,FCB
        LD      C,21
        CALL    BDOS
        OR      A
        JR      NZ,GR9
GR8:    POP     HL
        LD      DE,128
        ADD     HL,DE
        POP     BC
        DJNZ    GR2
        XOR     A
        RET
GR9:    POP     HL
        POP     BC
        OR      A
        RET

RFALLA: DEC     A               ; 1 cancelado, 2 disco
        PUSH    AF
        CALL    NORMAL
        CALL    BORRAR
        POP     AF
        LD      DE,MCAN
        JR      NZ,RF2
        CALL    PRINT
        LD      A,(MALE)        ; hubo bloques fuera de orden? cuales
        OR      A
        LD      DE,MFIN
        JP      Z,FIN
        LD      DE,MSEQ
        CALL    PRINT
        LD      HL,(MALN)
        LD      H,0
        CALL    DECIM
        LD      DE,MSEQ2
        CALL    PRINT
        LD      HL,(MALE)
        LD      H,0
        CALL    DECIM
        LD      DE,MSEQ3
        JP      FIN
RF2:
        LD      DE,MDISCO
        JP      FIN
RTMO:   CALL    NORMAL
        CALL    BORRAR
        LD      DE,MTMO
        JP      FIN

; RBODY: un bloque cuyo primer byte es A. Devuelve A = 0 bloque bien (NUM, LEN,
; BUF), 1 EOT, 2 CAN, 3 mal (despues de esperar silencio).
RBODY:  CP      SOH
        LD      HL,128
        JR      Z,RB1
        CP      STX
        LD      HL,1024
        JR      Z,RB1
        CP      EOT
        LD      A,1
        RET     Z
        CP      CAN-1+1
        JP      NZ,RBMAL
        LD      A,2
        RET
RB1:    LD      (LEN),HL
        CALL    GET1            ; numero y su complemento
        JP      C,RBMAL
        LD      (NUM),A
        CALL    GET1
        JP      C,RBMAL
        LD      B,A
        LD      A,(NUM)
        ADD     A,B
        INC     A
        JP      NZ,RBMAL
        LD      HL,BUF          ; los datos y el CRC (2) o la suma (1)
        LD      BC,(LEN)
        INC     BC
        LD      A,(MODO)
        CP      'C'
        JR      NZ,RB2
        INC     BC
RB2:    CALL    RAWBLK          ; lo que ya esta en el anillo, de una vez
        LD      A,B
        OR      C
        JR      Z,RB3
        CALL    GET1            ; y esperar el que sigue
        JP      C,RBMAL
        LD      (HL),A
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,RB2
RB3:    CALL    CHEQ            ; HL = CRC o suma, DE: despues de los datos
        LD      A,(MODO)
        CP      'C'
        JR      NZ,RB4
        LD      A,(DE)
        INC     DE
        CP      H
        JP      NZ,RBMAL
RB4:    LD      A,(DE)
        CP      L
        JP      NZ,RBMAL
        XOR     A
        RET

; RAWBLK: copia del anillo de la SIO A (pagina VTAPG en la ventana 1, como lo
; hace el XIOS: cabeza en 7CFC, cola en 7CFE, datos en 7E00, 512 bytes) a (HL),
; hasta BC bytes, de a 4 con las interrupciones apagadas. Avanza HL y BC.
; (Leer de a uno por el servicio 41 no alcanza para un bloque de 1K a 115200.)
RAWBLK: LD      A,B
        OR      C
        RET     Z
        PUSH    DE
RK0:    LD      A,4
        LD      (RKN),A
        DI
        LD      A,(VTAPG)
        OUT     (61h),A
RK1:    LD      DE,(7CFCh)      ; cabeza
        PUSH    HL
        LD      HL,(7CFEh)      ; cola
        OR      A
        SBC     HL,DE
        JR      Z,RK8           ; vacio
        LD      HL,7E00h
        ADD     HL,DE
        LD      A,(HL)
        POP     HL
        LD      (HL),A
        INC     HL
        INC     DE
        LD      A,D
        AND     1
        LD      D,A
        LD      (7CFCh),DE
        DEC     BC
        LD      A,B
        OR      C
        JR      Z,RK9
        LD      A,(RKN)
        DEC     A
        LD      (RKN),A
        JR      NZ,RK1
        LD      A,(0FFD4h)      ; un respiro: la ventana 1 del proceso (CURPG1)
        OUT     (61h),A
        EI
        JR      RK0
RK8:    POP     HL
RK9:    LD      A,(0FFD4h)
        OUT     (61h),A
        EI
        POP     DE
        RET
RKN:    DEFB    0
VTAPG:  DEFB    0
RBMAL:  CALL    PURGA           ; esperar silencio
        LD      A,3
        RET

; ------------------------------------------------------------- YMODEM
YREC:   LD      A,1
        LD      (YMOD),A
        LD      A,'C'
        LD      (MODO),A
        LD      A,(FCB)         ; la unidad pedida (0 = la de siempre)
        LD      (YDRV),A
        LD      DE,MRECY
        CALL    PRINT
        CALL    CRUDO
        JP      NZ,NOVIS
YR0:    CALL    PRIMER          ; el bloque 0: nombre y tamano
        JP      C,YRTMO
        CALL    RBODY
        OR      A
        JR      Z,YR1
        CP      2
        JP      Z,YRCAN
        JR      YR0             ; mal: pedirlo otra vez
YR1:    LD      A,(NUM)
        OR      A
        JR      NZ,YR0
        LD      A,(BUF)         ; nombre vacio: no hay mas
        OR      A
        JR      Z,YRFIN
        CALL    YNOMBRE         ; BUF -> FCB, RESTAN
        CALL    CREAR
        LD      A,ACK
        CALL    PUTB
        CALL    PRIMER          ; 'C' otra vez: los datos
        JP      C,YRTMO2
        CALL    DATOS
        JP      NZ,RFALLA
        CALL    CERRAR
        LD      HL,(ARCH)
        INC     HL
        LD      (ARCH),HL
        JR      YR0
YRFIN:  LD      A,ACK
        CALL    PUTB
        CALL    NORMAL
        LD      DE,MOKY
        CALL    PRINT
        LD      HL,(ARCH)
        CALL    DECIM
        LD      DE,MARCH
        JP      FINCNT
YRCAN:  CALL    NORMAL
        LD      DE,MCAN
        JP      FIN
YRTMO:  CALL    NORMAL
        LD      DE,MTMO
        JP      FIN
YRTMO2: CALL    NORMAL
        CALL    BORRAR
        LD      DE,MTMO
        JP      FIN

; YNOMBRE: el bloque 0 (nombre\0tamano...) -> FCB (8.3 en mayusculas, sin el
; camino) y RESTAN = registros (tamano / 128, para arriba; sin tamano, sin limite)
YNOMBRE: LD     HL,BUF          ; sin el camino: despues de la ultima '/'
        LD      DE,BUF
YN1:    LD      A,(HL)
        OR      A
        JR      Z,YN2
        INC     HL
        CP      '/'
        JR      NZ,YN1
        LD      D,H
        LD      E,L
        JR      YN1
YN2:    PUSH    HL              ; (HL: el 0 tras el nombre)
        LD      A,(YDRV)
        LD      (FCB),A
        LD      HL,FCB+1        ; espacios
        LD      B,11
YN3:    LD      (HL),' '
        INC     HL
        DJNZ    YN3
        EX      DE,HL           ; HL = nombre
        LD      DE,FCB+1
        LD      B,8
YN4:    LD      A,(HL)
        OR      A
        JR      Z,YN8
        INC     HL
        CP      '.'
        JR      Z,YN6
        CALL    MAYUS
        LD      C,A
        LD      A,B
        OR      A
        JR      Z,YN4           ; (demasiado largo: se corta)
        LD      A,C
        LD      (DE),A
        INC     DE
        DEC     B
        JR      YN4
YN6:    LD      DE,FCB+9        ; la extension
        LD      B,3
YN7:    LD      A,(HL)
        OR      A
        JR      Z,YN8
        INC     HL
        CALL    MAYUS
        LD      C,A
        LD      A,B
        OR      A
        JR      Z,YN7
        LD      A,C
        LD      (DE),A
        INC     DE
        DEC     B
        JR      YN7
YN8:    POP     HL              ; el tamano, en decimal, despues del 0
        INC     HL
        LD      A,(HL)
        CP      '0'
        JR      C,YN99
        CP      '9'+1
        JR      NC,YN99
        LD      DE,0            ; DEBC = tamano (32 bits)
        LD      BC,0
YN9:    LD      A,(HL)
        SUB     '0'
        JR      C,YN10
        CP      10
        JR      NC,YN10
        INC     HL
        PUSH    HL
        PUSH    AF
        CALL    POR10           ; DEBC *= 10
        POP     AF
        ADD     A,C
        LD      C,A
        JR      NC,YN9B
        INC     B
        JR      NZ,YN9B
        INC     DE
YN9B:   POP     HL
        JR      YN9
YN10:   LD      HL,127          ; registros = (tamano + 127) / 128
        ADD     HL,BC
        LD      B,H
        LD      C,L
        JR      NC,YN11
        INC     DE
YN11:   LD      A,C             ; DEBC >> 7: (DE:B) << 1 y el bit 7 de C
        RLA
        RL      B
        RL      E
        LD      H,E
        LD      L,B
        LD      (RESTAN),HL
        RET
YN99:   LD      HL,0FFFFh
        LD      (RESTAN),HL
        RET
POR10:  LD      H,B             ; DEBC *= 10 (x8 + x2)
        LD      L,C
        PUSH    DE
        CALL    X2
        PUSH    DE
        PUSH    BC
        CALL    X2
        CALL    X2
        POP     HL              ; + x2
        ADD     HL,BC
        LD      B,H
        LD      C,L
        POP     HL
        ADC     HL,DE
        EX      DE,HL
        POP     HL
        RET
X2:     SLA     C
        RL      B
        RL      E
        RL      D
        RET
MAYUS:  CP      'a'
        RET     C
        CP      'z'+1
        RET     NC
        SUB     20h
        RET

; ============================================================= mandar
MANDA:  LD      HL,FCB+1        ; con '?' (comodines): YMODEM
        LD      B,11
MD0:    LD      A,(HL)
        CP      '?'
        JP      Z,YSEND
        INC     HL
        DJNZ    MD0
        LD      DE,FCB
        LD      C,15            ; abrir
        CALL    BDOS
        INC     A
        LD      DE,MNOHAY
        JP      Z,FIN
        LD      DE,MSND
        CALL    PRINT
        CALL    CRUDO
        JP      NZ,NOVIS
        CALL    ESPERA          ; 'C' o NAK del que recibe
        JP      C,SCAN0
        LD      (MODO),A
        CALL    SDATOS
        PUSH    AF
        CALL    CERRAR          ; (MP/M lleva la cuenta de los abiertos)
        POP     AF
        JP      NZ,SCAN0
        CALL    NORMAL
        LD      DE,MOKS
        JP      FINCNT
SCAN0:  CALL    NORMAL
        LD      DE,MCAN
        JP      FIN

; ESPERA: hasta 60 s al que recibe. A = 'C' o NAK; carry si nada o CAN.
ESPERA: LD      B,60
ES1:    PUSH    BC
        LD      DE,TPS
        CALL    GETB
        POP     BC
        JR      C,ES2
        CP      'C'
        RET     Z
        CP      NAK
        RET     Z
        CP      CAN
        SCF
        RET     Z
ES2:    DJNZ    ES1
        SCF
        RET

; SDATOS: el archivo FCB abierto, en bloques de 128 (y de 1K con YMODEM: en
; YMOD, de a 8 registros si quedan), hasta EOT. Z = bien.
SDATOS: LD      A,1
        LD      (BLQ),A
SD1:    LD      HL,BUF          ; hasta 8 registros a BUF
        LD      B,8
        LD      A,(YMOD)
        OR      A
        JR      NZ,SD2
        LD      B,1
SD2:    LD      C,0             ; C = leidos
SD3:    PUSH    BC
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
        JR      NZ,SD4
        LD      DE,128
        ADD     HL,DE
        INC     C
        DJNZ    SD3
SD4:    LD      A,C
        OR      A
        JR      Z,SEOT
        CP      8               ; 8: un bloque de 1K; si no, de a 128
        JR      NZ,SD5
        LD      HL,1024
        LD      (LEN),HL
        LD      A,STX
        LD      HL,BUF
        CALL    SBLK
        RET     NZ
        JR      SD1
SD5:    LD      HL,BUF
SD6:    PUSH    BC
        PUSH    HL
        LD      DE,128
        LD      (LEN),DE
        LD      A,SOH
        CALL    SBLK
        POP     HL
        POP     BC
        RET     NZ
        LD      DE,128
        ADD     HL,DE
        DEC     C
        JR      NZ,SD6
        JR      SD1
SEOT:   LD      B,10            ; EOT hasta que lo acepten
SE1:    PUSH    BC
        LD      A,EOT
        CALL    PUTB
        LD      DE,5*TPS
        CALL    GETB
        POP     BC
        JR      C,SE2
        CP      ACK
        RET     Z
SE2:    DJNZ    SE1
        XOR     A
        RET

; SBLK: manda el bloque A (SOH/STX) de LEN bytes en HL con numero BLQ y espera
; ACK (10 intentos). Z = bien; NZ = cancelado.
SBLK:   LD      (TIPO),A
        LD      (SPTR),HL
        XOR     A
        LD      (ERRS),A
SB1:    LD      A,(TIPO)
        CALL    PUTB
        LD      A,(BLQ)
        CALL    PUTB
        CPL
        CALL    PUTB
        LD      HL,(SPTR)
        LD      BC,(LEN)
SB2:    LD      A,(HL)
        CALL    PUTB
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,SB2
        LD      HL,(SPTR)
        CALL    CHEQH
        LD      A,(MODO)
        CP      'C'
        JR      NZ,SB3
        LD      A,H
        CALL    PUTB
SB3:    LD      A,L
        CALL    PUTB
        LD      DE,10*TPS
        CALL    GETB
        JR      C,SB4
        CP      ACK
        JR      Z,SB5
        CP      CAN
        JR      Z,SB6
SB4:    LD      HL,ERRS         ; NAK o nada: otra vez
        INC     (HL)
        LD      A,(HL)
        CP      10
        JR      C,SB1
        CALL    CANCEL
SB6:    LD      A,1
        OR      A
        RET
SB5:    LD      HL,BLQ
        INC     (HL)
        LD      HL,(CUENTA)
        INC     HL
        LD      (CUENTA),HL
        XOR     A
        RET

; YSEND: los archivos que coinciden con FCB (comodines), por YMODEM
YSEND:  LD      A,1
        LD      (YMOD),A
        LD      DE,DMA0
        LD      C,26
        CALL    BDOS
        LD      HL,NOMS         ; juntar los nombres primero (buscar y abrir
        LD      (NPTR),HL       ; a la vez no se puede)
        LD      DE,FCB
        LD      C,17
YS1:    CALL    BDOS
        INC     A
        JR      Z,YS3
        DEC     A               ; entrada A del registro de directorio
        RRCA
        RRCA
        RRCA
        AND     60h
        ADD     A,DMA0+1
        LD      L,A
        LD      H,0
        LD      DE,(NPTR)
        LD      BC,11
        LDIR
        LD      (NPTR),DE
        LD      HL,(NNOM)
        INC     HL
        LD      (NNOM),HL
        LD      A,L
        CP      MAXN
        JR      NC,YS3
        LD      DE,FCB
        LD      C,18
        JR      YS1
YS3:    LD      HL,(NNOM)
        LD      A,H
        OR      L
        LD      DE,MNOHAY
        JP      Z,FIN
        LD      DE,MSNDY
        CALL    PRINT
        CALL    CRUDO
        JP      NZ,NOVIS
        LD      A,(FCB)
        LD      (YDRV),A
        LD      HL,NOMS
        LD      (NPTR),HL
YS4:    CALL    ESPERA          ; 'C': el bloque 0
        JP      C,SCAN0
        LD      A,'C'
        LD      (MODO),A
        LD      HL,(NNOM)
        LD      A,H
        OR      L
        JR      Z,YSFIN
        DEC     HL
        LD      (NNOM),HL
        LD      HL,(NPTR)       ; el siguiente nombre al FCB
        LD      A,(YDRV)
        LD      (FCB),A
        LD      DE,FCB+1
        LD      BC,11
        LDIR
        LD      (NPTR),HL
        LD      HL,FCB+1        ; sin los atributos
        LD      B,11
YS5:    RES     7,(HL)
        INC     HL
        DJNZ    YS5
        CALL    FCBZ
        LD      DE,FCB
        LD      C,15
        CALL    BDOS
        INC     A
        JP      Z,YS4           ; (se borro mientras tanto: saltarlo)
        LD      DE,FCB          ; tamano: registros (BDOS 35)
        LD      C,35
        CALL    BDOS
        CALL    FCBZ2
        CALL    BLQ0            ; nombre y tamano al bloque 0
        XOR     A
        LD      (BLQ),A
        LD      HL,128
        LD      (LEN),HL
        LD      A,SOH
        LD      HL,BUF
        CALL    SBLK
        JP      NZ,SCAN0
        CALL    ESPERA          ; 'C': los datos
        JP      C,SCAN0
        CALL    SDATOS
        PUSH    AF
        CALL    CERRAR          ; (MP/M lleva la cuenta de los abiertos)
        POP     AF
        JP      NZ,SCAN0
        LD      HL,(ARCH)
        INC     HL
        LD      (ARCH),HL
        JR      YS4
YSFIN:  LD      HL,BUF          ; bloque 0 vacio: no hay mas
        LD      DE,BUF+1
        LD      BC,127
        LD      (HL),0
        LDIR
        XOR     A
        LD      (BLQ),A
        LD      HL,128
        LD      (LEN),HL
        LD      A,SOH
        LD      HL,BUF
        CALL    SBLK
YSFIN0: CALL    NORMAL
        LD      DE,MOKSY
        CALL    PRINT
        LD      HL,(ARCH)
        CALL    DECIM
        LD      DE,MARCH
        JP      FINCNT

; FCBZ2: el registro actual en cero despues de BDOS 35 (para leer desde el 0)
FCBZ2:  XOR     A
        LD      (FCB+32),A
        LD      HL,(FCB+33)     ; los registros, para el bloque 0
        LD      (NREG),HL
        LD      A,(FCB+35)
        LD      (NREG+2),A
        RET

; BLQ0: BUF = "nombre.ext" 0 "tamano" 0 (en minusculas, como en el PC)
BLQ0:   LD      HL,BUF
        LD      DE,BUF+1
        LD      BC,127
        LD      (HL),0
        LDIR
        LD      HL,FCB+1
        LD      DE,BUF
        LD      B,8
BQ1:    LD      A,(HL)
        INC     HL
        CP      ' '
        JR      Z,BQ2
        CALL    MINUS
        LD      (DE),A
        INC     DE
BQ2:    DJNZ    BQ1
        LD      A,(FCB+9)
        CP      ' '
        JR      Z,BQ4
        LD      A,'.'
        LD      (DE),A
        INC     DE
        LD      HL,FCB+9
        LD      B,3
BQ3:    LD      A,(HL)
        INC     HL
        CP      ' '
        JR      Z,BQ3B
        CALL    MINUS
        LD      (DE),A
        INC     DE
BQ3B:   DJNZ    BQ3
BQ4:    INC     DE              ; (el 0)
        PUSH    DE              ; tamano = registros * 128, en decimal
        LD      HL,(NREG)       ; HL.A = registros (24 bits) -> DEHL bytes
        LD      A,(NREG+2)
        LD      E,A
        LD      D,0
        LD      B,7
BQ5:    ADD     HL,HL
        RL      E
        RL      D
        DJNZ    BQ5
        POP     IX
        JP      DEC32           ; DEHL en decimal en (IX)
MINUS:  CP      'A'
        RET     C
        CP      'Z'+1
        RET     NC
        ADD     A,20h
        RET

; DEC32: DEHL (32 bits) en decimal ASCII en (IX), sin ceros a la izquierda
DEC32:  LD      IY,POT10
        LD      C,0             ; C: ya hubo un digito
DC1:    LD      B,'0'
DC2:    PUSH    HL              ; DEHL - potencia
        PUSH    DE
        LD      A,L
        SUB     (IY+0)
        LD      L,A
        LD      A,H
        SBC     A,(IY+1)
        LD      H,A
        LD      A,E
        SBC     A,(IY+2)
        LD      E,A
        LD      A,D
        SBC     A,(IY+3)
        LD      D,A
        JR      C,DC3
        INC     SP
        INC     SP
        INC     SP
        INC     SP
        INC     B
        JR      DC2
DC3:    POP     DE
        POP     HL
        LD      A,B
        CP      '0'
        JR      NZ,DC4
        LD      A,C
        OR      A
        JR      NZ,DC4
        LD      A,(IY+0)        ; la ultima potencia (1) siempre se escribe
        DEC     A
        JR      NZ,DC5
DC4:    LD      (IX+0),B
        INC     IX
        LD      C,1
DC5:    LD      A,(IY+0)
        DEC     A
        OR      (IY+1)
        OR      (IY+2)
        OR      (IY+3)
        RET     Z
        INC     IY
        INC     IY
        INC     IY
        INC     IY
        JR      DC1
POT10:  DEFW    0CA00h,3B9Ah, 0E100h,05F5h, 9680h,0098h, 4240h,000Fh
        DEFW    86A0h,0001h, 2710h,0, 1000-0+0,0, 100,0, 10,0, 1,0

; ------------------------------------------------------------- rutinas
CRUDO:  LD      B,4             ; la pagina del anillo (RAWBLK)
        LD      C,41
        RST     30h
        LD      (VTAPG),A
        LD      B,0             ; modo crudo: Z si se pudo
        LD      C,41
        RST     30h
        OR      A
        RET
NORMAL: LD      B,1
        LD      C,41
        RST     30h
        RET
NOVIS:  LD      DE,MNOVIS
        JP      FIN
PUTB:   PUSH    BC
        PUSH    DE
        PUSH    HL
        PUSH    AF
        LD      E,A
        LD      B,3
        LD      C,41
        RST     30h
        POP     AF
        POP     HL
        POP     DE
        POP     BC
        RET
; GETB: un byte, esperando hasta DE tics; carry si no llego. Primero lo busca
; unas veces sin esperar: lo que manda el PC suele llegar enseguida, y esperar
; un tic entero por cada bloque es lo que mas demora.
GETB:   PUSH    BC
        PUSH    HL
        PUSH    DE
        LD      B,40
GB1:    PUSH    BC
        LD      DE,0
        LD      B,2
        LD      C,41
        RST     30h
        POP     BC
        JR      NC,GB2
        DJNZ    GB1
        POP     DE
        PUSH    DE
        LD      B,2
        LD      C,41
        RST     30h
GB2:    POP     DE
        POP     HL
        POP     BC
        RET
GET1:   PUSH    DE              ; un byte con 1 s de espera
        LD      DE,TPS
        CALL    GETB
        POP     DE
        RET
PURGA:  LD      DE,TPS          ; hasta 1 s sin nada
        CALL    GETB
        JR      NC,PURGA
        RET
CANCEL: LD      A,CAN
        CALL    PUTB
        CALL    PUTB
        JP      PURGA

; CHEQ / CHEQH: HL = CRC-16 (CCITT, con tabla) o L = suma de LEN bytes en BUF / HL
CHEQ:   LD      HL,BUF
CHEQH:  EX      DE,HL           ; DE = datos
        LD      BC,(LEN)
        LD      HL,0
        LD      A,(MODO)
        CP      'C'
        JR      NZ,CHS
CHC:    LD      A,(DE)          ; crc = (crc << 8) ^ T[(crc >> 8) ^ byte]
        XOR     H
        PUSH    DE
        LD      E,A
        LD      D,TCRCH SHR 8
        LD      A,(DE)
        XOR     L
        LD      H,A
        INC     D
        LD      A,(DE)
        LD      L,A
        POP     DE
        INC     DE
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,CHC
        RET
CHS:    LD      A,(DE)
        ADD     A,L
        LD      L,A
        INC     DE
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,CHS
        RET
; TABCRC: la tabla del CRC (TCRCH alto, TCRCH+256 bajo)
TABCRC: LD      C,0
TB1:    LD      H,C
        LD      L,0
        LD      B,8
TB2:    ADD     HL,HL
        JR      NC,TB3
        LD      A,H
        XOR     10h
        LD      H,A
        LD      A,L
        XOR     21h
        LD      L,A
TB3:    DJNZ    TB2
        LD      D,TCRCH SHR 8
        LD      E,C
        LD      A,H
        LD      (DE),A
        INC     D
        LD      A,L
        LD      (DE),A
        INC     C
        JR      NZ,TB1
        RET

PRINT:  LD      C,9
        JP      BDOS
FINCNT: CALL    PRINT           ; y cuantos bloques
        LD      HL,(CUENTA)
        CALL    DECIM
        LD      DE,MBLQ
FIN:    LD      C,9
        CALL    BDOS
        LD      C,0
        JP      BDOS
DECIM:  XOR     A
        LD      (CERO),A
        LD      BC,-10000
        CALL    DIG
        LD      BC,-1000
        CALL    DIG
        LD      BC,-100
        CALL    DIG
        LD      BC,-10
        CALL    DIG
        LD      A,L
        ADD     A,'0'
        JP      CHAR
DIG:    LD      A,'0'-1
DG1:    INC     A
        ADD     HL,BC
        JR      C,DG1
        SBC     HL,BC
        LD      D,A
        LD      A,(CERO)
        OR      A
        LD      A,D
        JR      NZ,CHAR
        CP      '0'
        RET     Z
        LD      (CERO),A
CHAR:   PUSH    HL
        LD      E,A
        LD      C,2
        CALL    BDOS
        POP     HL
        RET

MUSO:   DEFB    'Usage: XFER R file    receive by XMODEM  (on the PC: sx file, or sx -k)',13,10
        DEFB    '       XFER R [d:]    receive by YMODEM  (on the PC: sb file1 file2 ...)',13,10
        DEFB    '       XFER S file    send by XMODEM     (on the PC: rx file)',13,10
        DEFB    '       XFER S d:*.*   send by YMODEM     (on the PC: rb)$'
MNOMPM: DEFB    'XFER needs MP/M II ZEPHYRUS$'
MNOCREA: DEFB   'Cannot create the file$'
MNOHAY: DEFB    'File not found$'
MNOVIS: DEFB    'XFER must run on the console shown on the terminal$'
MREC:   DEFB    'Ready to receive: start the XMODEM send (Ctrl-X Ctrl-X cancels)',13,10,'$'
MRECY:  DEFB    'Ready to receive: start the YMODEM send (Ctrl-X Ctrl-X cancels)',13,10,'$'
MSND:   DEFB    'Ready to send: start the XMODEM receive (Ctrl-X Ctrl-X cancels)',13,10,'$'
MSNDY:  DEFB    'Ready to send: start the YMODEM receive (Ctrl-X Ctrl-X cancels)',13,10,'$'
MOKR:   DEFB    13,10,'Received $'
MOKS:   DEFB    13,10,'Sent $'
MOKY:   DEFB    13,10,'Received $'
MOKSY:  DEFB    13,10,'Sent $'
MARCH:  DEFB    ' files, $'
MBLQ:   DEFB    ' blocks$'
MCAN:   DEFB    13,10,'Transfer cancelled$'
MTMO:   DEFB    13,10,'No answer from the other side$'
MDISCO: DEFB    13,10,'Disk full or write error$'
MSEQ:   DEFB    ' (block $'
MSEQ2:  DEFB    ' out of sequence, expected $'
MSEQ3:  DEFB    ')$'
MFIN:   DEFB    '$'
MALN:   DEFB    0
MALE:   DEFB    0
BLQ:    DEFB    0
NUM:    DEFB    0
MODO:   DEFB    0
ERRS:   DEFB    0
CERO:   DEFB    0
YMOD:   DEFB    0
YDRV:   DEFB    0
TIPO:   DEFB    0
CUENTA: DEFW    0
ARCH:   DEFW    0
NNOM:   DEFW    0
LEN:    DEFW    128
RESTAN: DEFW    0FFFFh
SPTR:   DEFW    0
NPTR:   DEFW    0
NREG:   DEFB    0,0,0
FCB:    DEFS    36
        DEFS    256             ; pila (el despachador de MP/M guarda ahi los
PILA:                           ; registros: hace falta lugar)
BUF:    DEFS    1024+3
        ORG     ($+255) AND 0FF00h
TCRCH:  DEFS    512
NOMS:   DEFS    MAXN*11
        END
