; BAUD.COM - velocidad de los canales de la SIO, como la orden BAUD de ZLoader,
; desde CP/M 2.2 (ZIOS) o MP/M II ZEPHYRUS (el XIOS imita los servicios).
;   BAUD            muestra la velocidad guardada de cada canal
;   BAUD A 9600     la cambia ahora y la guarda en la NVRAM del DS1307
; Usa el servicio 34 de ZIOS (I2C, para la NVRAM). El cambio inmediato: en CP/M
; con el servicio 32; en MP/M programando la SIO directamente.
; (C) OLIVEROS 2026
BDOS    EQU     5
TAIL    EQU     80h
RTC     EQU     0D0h            ; DS1307
NVREG   EQU     08h             ; la NVRAM empieza en el registro 8
NV_SIOA EQU     1               ; WR4 del canal A (0 = por omision)
NV_SIOB EQU     2
NV_CTC0 EQU     3               ; constante del CTC 0 (0 = 3)
NV_CLK  EQU     5               ; bit 0: CPU a 14,7456 MHz
NV_SIOFL EQU    6               ; bit 0: el canal A usa el CTC; bit 1: el B
CF_PI   EQU     20h             ; canal B reservado para la Raspberry Pi
W_X16   EQU     01000100b
W_X32   EQU     10000100b
W_X64   EQU     11000100b

        ORG     100h
        CALL    NVLEE
        JP      NZ,ENVR
        LD      HL,TAIL         ; la linea termina en 0 (MP/M no lo pone)
        LD      E,(HL)
        LD      D,0
        ADD     HL,DE
        INC     HL
        LD      (HL),D
        LD      HL,TAIL
        LD      B,(HL)
        INC     HL
        CALL    BLANCO
        JP      Z,MUESTRA
        ; canal
        SUB     'A'
        CP      2
        JP      NC,EUSO
        LD      (CANAL),A
        INC     HL
        DEC     B
        CALL    BLANCO
        JP      Z,EUSO
        ; velocidad: buscarla en la tabla
        LD      (TXT),HL
        LD      HL,TASAS
BUSCA:  LD      A,(HL)
        OR      A
        JP      Z,EUSO
        PUSH    HL
        LD      DE,(TXT)
CMP1:   LD      A,(HL)
        OR      A
        JR      Z,CMP2
        LD      A,(DE)
        CP      (HL)
        JR      NZ,CMP2
        INC     HL
        INC     DE
        JR      CMP1
CMP2:   LD      A,(HL)          ; fin del nombre y fin de la palabra?
        OR      A
        JR      NZ,CMP3
        LD      A,(DE)
        CP      ' '+1
        JR      C,HALLO
CMP3:   POP     HL
        CALL    SALTA
        JR      BUSCA
HALLO:  POP     HL
        CALL    SALTA0          ; HL -> WR4, TC
        LD      A,(HL)
        LD      (WR4),A
        INC     HL
        LD      A,(HL)
        LD      (TC),A
        ; con el CTC: el otro canal no puede usar otra constante (es una sola)
        OR      A
        JR      Z,GUARDA
        LD      A,(NVRAM+NV_SIOFL)
        LD      C,A
        LD      A,(CANAL)
        OR      A
        LD      A,C
        JR      NZ,OTRO
        RRCA                    ; canal A: mirar el bit del B
OTRO:   AND     1
        JR      Z,GUARDA
        LD      A,(NVRAM+NV_CTC0)
        OR      A
        JR      NZ,OTRO2
        LD      A,3
OTRO2:  LD      C,A
        LD      A,(TC)
        CP      C
        JP      NZ,ECTC
GUARDA: LD      A,(CANAL)       ; WR4 en la NVRAM
        LD      HL,NVRAM+NV_SIOA
        OR      A
        JR      Z,G1
        INC     HL
G1:     LD      A,(WR4)
        LD      (HL),A
        LD      A,(CANAL)       ; bandera "usa el CTC"
        INC     A
        LD      C,A             ; 1 = canal A, 2 = canal B
        LD      A,(NVRAM+NV_SIOFL)
        OR      C
        LD      B,A
        LD      A,(TC)
        OR      A
        LD      A,B
        JR      NZ,G2
        XOR     C
G2:     LD      (NVRAM+NV_SIOFL),A
        LD      A,(TC)
        OR      A
        JR      Z,G3
        LD      (NVRAM+NV_CTC0),A
G3:     CALL    NVGRABA
        JP      NZ,ENVR
        LD      DE,MLISTO
        CALL    PRT
        LD      A,(CANAL)
        ADD     A,'A'
        CALL    PCH
        LD      DE,MLISTO2
        CALL    PRT
        LD      HL,(TXT)        ; la velocidad, como se escribio
PV1:    LD      A,(HL)
        CP      ' '+1
        JR      C,PV2
        CALL    PCH
        INC     HL
        JR      PV1
PV2:
        LD      A,(TC)
        OR      A
        LD      DE,MPUENTE
        CALL    NZ,PRT
        LD      DE,MCAMBIO
        CALL    PRT
        LD      BC,0            ; esperar a que salga el texto
ESP:    EX      (SP),HL
        EX      (SP),HL
        EX      (SP),HL
        EX      (SP),HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,ESP
        LD      C,12            ; MP/M (H = 1): la SIO se programa aqui mismo
        CALL    BDOS
        LD      A,H
        DEC     A
        JR      Z,AHORA
        LD      A,(WR4)         ; CP/M: servicio 32 de ZIOS (WR4 -> modo 1/2/3)
        RLCA
        RLCA
        AND     3
        LD      D,A
        LD      A,(TC)
        LD      E,A
        LD      A,(CANAL)
        LD      B,A
        LD      C,32
        RST     30h
        RET
; Bajo MP/M: CTC 0 si hace falta y el canal con los valores del XIOS (WR4
; primero, despues WR1 con interrupciones de RX y TX, WR3 y WR5)
AHORA:  DI
        LD      A,(TC)
        OR      A
        JR      Z,AH1
        LD      A,07h
        OUT     (40h),A
        LD      A,(TC)
        OUT     (40h),A
AH1:    LD      C,83h           ; control del canal A
        LD      DE,0E11Ah       ; WR3, WR1
        LD      A,(CANAL)
        OR      A
        JR      Z,AH2
        LD      C,82h
        LD      DE,0C11Eh
AH2:    LD      A,4
        OUT     (C),A
        LD      A,(WR4)
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
        EI
        RET

; ---- mostrar los dos canales
MUESTRA: LD     B,0
MU1:    PUSH    BC
        LD      DE,MCANAL
        CALL    PRT
        POP     BC
        PUSH    BC
        LD      A,B
        ADD     A,'A'
        CALL    PCH
        LD      DE,MDOSP
        CALL    PRT
        POP     BC
        PUSH    BC
        LD      HL,NVRAM+NV_SIOA ; WR4 guardado (0 = por omision)
        LD      A,B
        OR      A
        JR      Z,MU2
        INC     HL
MU2:    LD      A,(HL)
        OR      A
        JR      NZ,MU3
        LD      A,W_X64         ; por omision x64; B con la Pi, x32
        INC     B
        DEC     B
        JR      Z,MU3
        LD      A,(NVRAM)
        AND     CF_PI
        LD      A,W_X64
        JR      Z,MU3
        LD      A,W_X32
MU3:    LD      D,A
        POP     BC
        PUSH    BC
        LD      E,0             ; usa el CTC?
        LD      A,(NVRAM+NV_SIOFL)
        INC     B
        DEC     B
        JR      Z,MU4
        RRCA
MU4:    AND     1
        JR      Z,MU5
        LD      A,(NVRAM+NV_CTC0)
        OR      A
        JR      NZ,MU4B
        LD      A,3
MU4B:   LD      E,A
MU5:    LD      HL,TASAS        ; buscar el par (WR4, TC)
MU6:    LD      A,(HL)
        OR      A
        JR      Z,MU8
        PUSH    HL
        CALL    SALTA0
        LD      A,(HL)
        CP      D
        JR      NZ,MU7
        INC     HL
        LD      A,(HL)
        CP      E
        JR      NZ,MU7
        POP     HL              ; nombre
MU6B:   LD      A,(HL)
        OR      A
        JR      Z,MU9
        CALL    PCH
        INC     HL
        JR      MU6B
MU7:    POP     HL
        CALL    SALTA
        JR      MU6
MU8:    LD      A,'?'
        CALL    PCH
MU9:    POP     BC
        INC     B
        LD      A,B
        CP      2
        JR      NZ,MU1
        LD      A,(NVRAM+NV_CLK)
        AND     1
        LD      DE,MDOBLE
        CALL    NZ,PRT
        LD      DE,MFIN
        JP      PRT

; ---- NVRAM por el servicio 34 (I2C). Z = bien.
NVLEE:  LD      HL,NVBUF        ; puntero de registro = 8
        LD      (HL),NVREG
        LD      B,0
        LD      D,RTC
        LD      E,1
        LD      C,34
        RST     30h
        OR      A
        RET     NZ
        LD      HL,NVRAM
        LD      B,1
        LD      D,RTC
        LD      E,16
        LD      C,34
        RST     30h
        OR      A
        RET
NVGRABA: LD     HL,NVRAM        ; suma de comprobacion: complementos de 0-14
        LD      BC,0F00h
NG1:    LD      A,(HL)
        CPL
        ADD     A,C
        LD      C,A
        INC     HL
        DJNZ    NG1
        LD      (HL),C
        LD      HL,NVBUF
        LD      B,0
        LD      D,RTC
        LD      E,17
        LD      C,34
        RST     30h
        OR      A
        RET

; ---- utilidades
BLANCO: LD      A,B             ; salta espacios; Z si no queda nada
        OR      A
        RET     Z
        LD      A,(HL)
        CP      ' '
        JR      NZ,BL1
        INC     HL
        DEC     B
        JR      BLANCO
BL1:    OR      A
        RET
SALTA0: LD      A,(HL)          ; HL -> despues del 0 del nombre
        INC     HL
        OR      A
        JR      NZ,SALTA0
        RET
SALTA:  CALL    SALTA0          ; HL -> la entrada siguiente
        INC     HL
        INC     HL
        RET
PCH:    PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      E,A
        LD      C,2
        CALL    BDOS
        POP     HL
        POP     DE
        POP     BC
        RET
PRT:    PUSH    BC
        PUSH    HL
        LD      C,9
        CALL    BDOS
        POP     HL
        POP     BC
        RET
EUSO:   LD      DE,MUSO
        JP      PRT
ENVR:   LD      DE,MNVR
        JP      PRT
ECTC:   LD      DE,MCTC
        JP      PRT

; velocidades con la CPU a 7,3728 MHz: nombre, WR4, constante del CTC (0 = sin CTC)
TASAS:  DEFB    '230400',0,W_X32,0
        DEFB    '115200',0,W_X64,0
        DEFB    '9600',0,W_X16,3
        DEFB    '4800',0,W_X16,6
        DEFB    '2400',0,W_X16,12
        DEFB    '1200',0,W_X16,24
        DEFB    '600',0,W_X16,48
        DEFB    '300',0,W_X16,96
        DEFB    0

MCANAL: DEFB    13,10,'Channel $'
MDOSP:  DEFB    ': $'
MDOBLE: DEFB    13,10,'(with the CPU at 14.7456 MHz all rates are doubled)$'
MFIN:   DEFB    13,10,'$'
MUSO:   DEFB    13,10,'Usage: BAUD [A|B rate]   230400 115200 9600 4800 2400 1200 600 300',13,10,'$'
MNVR:   DEFB    13,10,'Cannot read or write the DS1307 NVRAM',13,10,'$'
MCTC:   DEFB    13,10,'The other channel uses the CTC at another rate (both share one CTC clock)',13,10,'$'
MLISTO: DEFB    13,10,'Saved: channel $'
MLISTO2: DEFB   ' at $'
MPUENTE: DEFB   13,10,'At 9600 or less the SIO clock jumper must be on CLK0_OUT (P6 channel A, P3 channel B).$'
MCAMBIO: DEFB   13,10,'Changing now; set your terminal to match.',13,10,'$'

CANAL:  DEFB    0
WR4:    DEFB    0
TC:     DEFB    0
TXT:    DEFW    0
NVBUF:  DEFB    NVREG
NVRAM:  DEFS    16
        END
