; XFER.COM - MP/M II ZEPHYRUS: pasa archivos por XMODEM (128 bytes, CRC o suma)
; por la consola del programa, sin sacar la SD.
;   XFER R ARCHIVO.EXT    recibe (en oli: sx ARCHIVO)
;   XFER S ARCHIVO.EXT    manda  (en oli: rx ARCHIVO)
; Usa el servicio 41 del XIOS (modo crudo: los bytes pasan tal cual, sin las
; teclas de las consolas virtuales ni la linea de estado). La consola tiene que
; ser la que se ve en el terminal. (C) OLIVEROS 2026
BDOS    EQU     5
FCB1    EQU     5Ch
FCB2    EQU     6Ch
SOH     EQU     01h
EOT     EQU     04h
ACK     EQU     06h
NAK     EQU     15h
CAN     EQU     18h
TPS     EQU     60              ; tics por segundo

        ORG     100h
        LD      SP,PILA
        LD      C,12            ; MP/M? (BDOS 12: H = 1)
        CALL    BDOS
        LD      A,H
        DEC     A
        LD      DE,MNOMPM
        JP      NZ,FIN
        LD      A,(FCB2+1)      ; hace falta el archivo
        CP      ' '
        JP      Z,USO
        LD      HL,FCB2         ; FCB propio
        LD      DE,FCB
        LD      BC,12
        LDIR
        LD      A,(FCB1+1)
        AND     5Fh
        CP      'R'
        JR      Z,RECIBE
        CP      'S'
        JP      Z,MANDA
USO:    LD      DE,MUSO
        JP      FIN

; ------------------------------------------------------------- recibir
RECIBE: LD      DE,FCB
        LD      C,19            ; borrar si existe
        CALL    BDOS
        LD      DE,FCB
        LD      C,22            ; crear
        CALL    BDOS
        INC     A
        LD      DE,MNOCREA
        JP      Z,FIN
        LD      DE,MREC
        CALL    PRINT
        CALL    CRUDO
        JP      NZ,NOVIS
        LD      A,1
        LD      (BLQ),A
        LD      A,'C'           ; primero pide CRC, despues suma
        LD      (MODO),A
        LD      B,20            ; 20 intentos de 3 s
R1:     PUSH    BC
        LD      A,B
        CP      14              ; tras 6 intentos con 'C', NAK (suma)
        JR      NZ,R1B
        LD      A,NAK
        LD      (MODO),A
R1B:    LD      A,(MODO)
        CALL    PUTB
        LD      DE,3*TPS
        CALL    GETB
        POP     BC
        JR      NC,R2
        DJNZ    R1
        JP      RTMO
R2:     LD      HL,ERRS
        LD      (HL),0
RBLQ:   CP      SOH             ; A = primer byte del bloque
        JR      Z,R3
        CP      EOT
        JP      Z,RFIN
        CP      CAN
        JP      Z,RCAN
        JP      RMAL
R3:     CALL    GET1            ; numero y su complemento
        JP      C,RMAL
        LD      (NUM),A
        CALL    GET1
        JP      C,RMAL
        LD      B,A
        LD      A,(NUM)
        ADD     A,B
        INC     A
        JP      NZ,RMAL
        LD      HL,BUF          ; los 128 bytes
        LD      B,128
R4:     CALL    GET1
        JP      C,RMAL
        LD      (HL),A
        INC     HL
        DJNZ    R4
        CALL    CHEQ            ; HL = CRC o suma de BUF
        LD      A,(MODO)
        CP      'C'
        JR      NZ,R5
        CALL    GET1
        JP      C,RMAL
        CP      H
        JP      NZ,RMAL
R5:     CALL    GET1
        JP      C,RMAL
        CP      L
        JP      NZ,RMAL
        LD      A,(NUM)         ; el que tocaba, o el anterior repetido
        LD      HL,BLQ
        CP      (HL)
        JR      Z,R6
        INC     A
        CP      (HL)
        JR      Z,RACK
        JP      RCANC           ; fuera de orden
R6:     LD      DE,BUF          ; grabar
        LD      C,26
        CALL    BDOS
        LD      DE,FCB
        LD      C,21
        CALL    BDOS
        OR      A
        JP      NZ,RDISCO
        LD      HL,BLQ
        INC     (HL)
        LD      HL,(CUENTA)
        INC     HL
        LD      (CUENTA),HL
        XOR     A
        LD      (ERRS),A
RACK:   LD      A,ACK
        CALL    PUTB
RSIG:   LD      DE,10*TPS
        CALL    GETB
        JP      NC,RBLQ
        JR      RMAL2
RMAL:   CALL    PURGA           ; error: esperar silencio y pedirlo otra vez
RMAL2:  LD      HL,ERRS
        INC     (HL)
        LD      A,(HL)
        CP      10
        JP      NC,RCANC
        LD      A,NAK
        CALL    PUTB
        JR      RSIG
RFIN:   LD      A,ACK
        CALL    PUTB
        CALL    NORMAL
        LD      DE,FCB
        LD      C,16
        CALL    BDOS
        LD      DE,MOKR
        JP      FINCNT
RCANC:  CALL    CANCEL
RCAN:   CALL    NORMAL
        LD      DE,FCB          ; lo recibido queda
        LD      C,16
        CALL    BDOS
        LD      DE,MCAN
        JP      FIN
RTMO:   CALL    NORMAL
        LD      DE,FCB
        LD      C,19
        CALL    BDOS
        LD      DE,MTMO
        JP      FIN
RDISCO: CALL    CANCEL
        CALL    NORMAL
        LD      DE,MDISCO
        JP      FIN

; ------------------------------------------------------------- mandar
MANDA:  LD      DE,FCB
        LD      C,15            ; abrir
        CALL    BDOS
        INC     A
        LD      DE,MNOHAY
        JP      Z,FIN
        LD      DE,MSND
        CALL    PRINT
        CALL    CRUDO
        JP      NZ,NOVIS
        LD      A,1
        LD      (BLQ),A
        LD      B,60            ; hasta 60 s esperando al que recibe
S1:     PUSH    BC
        LD      DE,TPS
        CALL    GETB
        POP     BC
        JR      C,S1B
        CP      'C'
        JR      Z,S2
        CP      NAK
        JR      Z,S2
        CP      CAN
        JP      Z,SCAN
S1B:    DJNZ    S1
        CALL    NORMAL
        LD      DE,MTMO
        JP      FIN
S2:     LD      (MODO),A
SLEE:   LD      DE,BUF          ; el registro siguiente
        LD      C,26
        CALL    BDOS
        LD      DE,FCB
        LD      C,20
        CALL    BDOS
        OR      A
        JR      NZ,SEOT
        XOR     A
        LD      (ERRS),A
SBLQ:   LD      A,SOH
        CALL    PUTB
        LD      A,(BLQ)
        CALL    PUTB
        CPL
        CALL    PUTB
        LD      HL,BUF
        LD      B,128
S3:     LD      A,(HL)
        CALL    PUTB
        INC     HL
        DJNZ    S3
        CALL    CHEQ
        LD      A,(MODO)
        CP      'C'
        JR      NZ,S4
        LD      A,H
        CALL    PUTB
S4:     LD      A,L
        CALL    PUTB
        LD      DE,10*TPS
        CALL    GETB
        JR      C,SOTRA
        CP      ACK
        JR      Z,SBIEN
        CP      CAN
        JP      Z,SCAN
SOTRA:  LD      HL,ERRS         ; NAK o nada: otra vez
        INC     (HL)
        LD      A,(HL)
        CP      10
        JR      C,SBLQ
        CALL    CANCEL
SCAN:   CALL    NORMAL
        LD      DE,MCAN
        JP      FIN
SBIEN:  LD      HL,BLQ
        INC     (HL)
        LD      HL,(CUENTA)
        INC     HL
        LD      (CUENTA),HL
        JR      SLEE
SEOT:   LD      B,10
SE1:    PUSH    BC
        LD      A,EOT
        CALL    PUTB
        LD      DE,5*TPS
        CALL    GETB
        POP     BC
        JR      C,SE2
        CP      ACK
        JR      Z,SE3
SE2:    DJNZ    SE1
SE3:    CALL    NORMAL
        LD      DE,MOKS
        JP      FINCNT

; ------------------------------------------------------------- rutinas
CRUDO:  LD      B,0             ; modo crudo: Z si se pudo
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
GETB:   PUSH    BC              ; DE = tics de espera; carry si no llego
        LD      B,2
        LD      C,41
        RST     30h
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
; CHEQ: HL = CRC-16 (CCITT) de BUF, o L = suma si MODO no es 'C'
CHEQ:   LD      HL,0
        LD      DE,BUF
        LD      C,128
        LD      A,(MODO)
        CP      'C'
        JR      NZ,CHS
CHC:    LD      A,(DE)
        XOR     H
        LD      H,A
        LD      B,8
CHC1:   ADD     HL,HL
        JR      NC,CHC2
        LD      A,H
        XOR     10h
        LD      H,A
        LD      A,L
        XOR     21h
        LD      L,A
CHC2:   DJNZ    CHC1
        INC     DE
        DEC     C
        JR      NZ,CHC
        RET
CHS:    LD      A,(DE)
        ADD     A,L
        LD      L,A
        INC     DE
        DEC     C
        JR      NZ,CHS
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
DECIM:  LD      BC,-10000
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

MUSO:   DEFB    'Usage: XFER R file   receive by XMODEM (on the PC: sx file)',13,10
        DEFB    '       XFER S file   send by XMODEM    (on the PC: rx file)$'
MNOMPM: DEFB    'XFER needs MP/M II ZEPHYRUS$'
MNOCREA: DEFB   'Cannot create the file$'
MNOHAY: DEFB    'File not found$'
MNOVIS: DEFB    'XFER must run on the console shown on the terminal$'
MREC:   DEFB    'Ready to receive: start the XMODEM send (Ctrl-X Ctrl-X cancels)',13,10,'$'
MSND:   DEFB    'Ready to send: start the XMODEM receive (Ctrl-X Ctrl-X cancels)',13,10,'$'
MOKR:   DEFB    13,10,'Received $'
MOKS:   DEFB    13,10,'Sent $'
MBLQ:   DEFB    ' blocks$'
MCAN:   DEFB    13,10,'Transfer cancelled$'
MTMO:   DEFB    13,10,'No answer from the other side$'
MDISCO: DEFB    13,10,'Disk full or write error$'
BLQ:    DEFB    0
NUM:    DEFB    0
MODO:   DEFB    0
ERRS:   DEFB    0
CERO:   DEFB    0
CUENTA: DEFW    0
FCB:    DEFS    36
BUF:    DEFS    128
        DEFS    64
PILA:
