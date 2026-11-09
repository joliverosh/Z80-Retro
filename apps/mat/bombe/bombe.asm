; =============================================================================
;  BOMBE.COM - la Bombe de Turing-Welchman en la Z80-Retro (CP/M)
;
;  Port de examples/bombe.s del SBC 6502, con bombe.py como referencia.
;  Rompe el parte meteorologico cifrado con Enigma a partir del crib
;  WETTERVORHERSAGEFUERDIENO: para un orden de rotores prueba las 17.576
;  posiciones; en cada una supone la pareja de la letra de prueba y sigue las
;  implicaciones del menu con el tablero diagonal de Welchman. Para (1 o 25
;  cables vivos) cuando la suposicion es coherente; la maquina de verificacion
;  saca las clavijas y descifra el mensaje.
;
;  BOMBE       el orden II-V-III (el que Bletchley le habria dado a esta Bombe)
;  BOMBE ALL   los 60 ordenes de los rotores I-V
; =============================================================================
        ORG 100h
        LD SP,STACK
        XOR A
        LD (ALLM),A
        LD A,(80h)              ; cola de la orden: ALL
        OR A
        JR Z,NOARG
        LD B,A
        LD HL,81h
ARG1:   LD A,(HL)
        CP 'A'
        JR NZ,ARG2
        LD (ALLM),A
ARG2:   INC HL
        DJNZ ARG1
NOARG:  LD DE,M_HELLO
        CALL PSTR
        LD HL,CIPHER
        CALL GROUPS
        LD DE,M_CRIB
        CALL PSTR
        LD HL,CRIB
        LD B,CRIBLEN
        CALL PLEN
        CALL CRLF
        LD DE,M_UNDER
        CALL PSTR
        LD HL,CIPHER
        LD B,CRIBLEN
        CALL PLEN
        CALL CRLF
        CALL MKMENU
        LD DE,M_MENU
        CALL PSTR
        LD A,(TEST)
        ADD A,'A'
        CALL PCH
        LD DE,M_WITH
        CALL PSTR
        LD A,(TEST)
        LD E,A
        LD D,0
        LD HL,ELEN
        ADD HL,DE
        LD L,(HL)
        LD H,0
        CALL PNUM
        LD DE,M_CONN
        CALL PSTR
        ; marcas en 0: GEN empieza en 1
        CALL CLRMK
        CALL INICIO
        LD A,(ALLM)
        OR A
        JR NZ,ALLO
        LD HL,ORDER0
        LD DE,ORD
        LD BC,3
        LDIR
        CALL DOORD
        JR DONE
ALLO:   XOR A
        LD (ORD),A
AL1:    XOR A
        LD (ORD+1),A
AL2:    XOR A
        LD (ORD+2),A
AL3:    LD A,(ORD)
        LD B,A
        LD A,(ORD+1)
        CP B
        JR Z,AL4
        LD C,A
        LD A,(ORD+2)
        CP B
        JR Z,AL4
        CP C
        JR Z,AL4
        CALL DOORD
AL4:    LD HL,ORD+2
        INC (HL)
        LD A,(HL)
        CP 5
        JR NZ,AL3
        LD HL,ORD+1
        INC (HL)
        LD A,(HL)
        CP 5
        JR NZ,AL2
        LD HL,ORD
        INC (HL)
        LD A,(HL)
        CP 5
        JR NZ,AL1
DONE:   LD DE,M_STOPS
        CALL PSTR
        LD HL,(NSTOP)
        CALL PNUM
        CALL CRLF
        CALL FIN
        JP 0

; ---------------------------------------------------------------- un orden
DOORD:  LD DE,M_ORDER
        CALL PSTR
        CALL PORD
        LD DE,M_COLON
        CALL PSTR
        XOR A
        LD (LP),A
DL1:    LD A,(LP)               ; avance: la letra del rotor izquierdo
        ADD A,'A'
        CALL PCH
        XOR A
        LD (MP),A
DL2:    CALL CORE
        CALL SBUILD
        XOR A
        LD (RP),A
DL3:    CALL UPDE
        XOR A
        LD (X0),A
        CALL PROP
        JR C,DL4
        LD A,(CNT)
        CP 1
        JR Z,DLS1
        CP 25
        JR NZ,DL4
        LD A,(TEST)             ; 25 vivos: el cable muerto es la respuesta
        ADD A,MARKH
        LD H,A
        LD L,0
        LD A,(GENV)
DLF:    CP (HL)
        JR NZ,DLF2
        INC L
        JR DLF
DLF2:   LD A,L
        JR DLS2
DLS1:   LD A,(X0)
DLS2:   CALL STOP
DL4:    LD HL,RP
        INC (HL)
        LD A,(HL)
        CP 26
        JR NZ,DL3
        LD HL,MP
        INC (HL)
        LD A,(HL)
        CP 26
        JR NZ,DL2
        LD HL,LP
        INC (HL)
        LD A,(HL)
        CP 26
        JR NZ,DL1
        JP CRLF

; STOP: A = pareja de la letra de prueba. Imprime la parada y la verificacion.
STOP:   LD (ST),A
        LD HL,(NSTOP)
        INC HL
        LD (NSTOP),HL
        CALL CRLF
        LD DE,M_STOP
        CALL PSTR
        CALL PORD
        LD A,' '
        CALL PCH
        CALL PPOS
        LD A,' '
        CALL PCH
        LD A,(TEST)
        ADD A,'A'
        CALL PCH
        LD A,'-'
        CALL PCH
        LD A,(ST)
        ADD A,'A'
        CALL PCH
        CALL CRLF
        ; ---- maquina de verificacion
        CALL PPOS
        LD DE,M_COLON
        CALL PSTR
        LD A,(ST)
        LD (X0),A
        CALL PROP
        JP C,CONTRA
        LD A,(CNT)
        CP 1
        JP NZ,CONTRA
        LD HL,PART              ; parejas: cada letra con una sola
        LD B,26
CK0:    LD (HL),0FFh
        INC HL
        DJNZ CK0
        LD C,0                  ; a
CK1:    LD A,C
        ADD A,MARKH
        LD H,A
        LD L,0                  ; x
CK2:    LD A,(GENV)
        CP (HL)
        JR NZ,CK3
        PUSH HL
        LD E,C
        LD D,0
        LD HL,PART
        ADD HL,DE
        LD A,(HL)
        POP DE                  ; E = x
        CP 0FFh
        JR Z,CK2B
        CP E
        JP NZ,CONTRA
CK2B:   LD (HL),E
        EX DE,HL
CK3:    INC L
        LD A,L
        CP 26
        JR NZ,CK2
        INC C
        LD A,C
        CP 26
        JR NZ,CK1
        LD DE,M_STECK
        CALL PSTR
        LD HL,PART              ; las parejas a < b, en orden
        LD C,0
CK4:    LD A,(HL)
        CP 0FFh
        JR Z,CK5
        CP C
        JR Z,CK5
        JR C,CK5
        PUSH AF
        LD A,C
        ADD A,'A'
        CALL PCH
        POP AF
        ADD A,'A'
        CALL PCH
        LD A,' '
        CALL PCH
CK5:    INC HL
        INC C
        LD A,C
        CP 26
        JR NZ,CK4
        CALL CRLF
        LD HL,PART              ; tablero de clavijas para la Enigma
        LD DE,PLUG
        LD C,0
CK6:    LD A,(HL)
        CP 0FFh
        JR NZ,CK7
        LD A,C
CK7:    LD (DE),A
        INC HL
        INC DE
        INC C
        LD A,C
        CP 26
        JR NZ,CK6
        CALL DECRYPT
        JP CRLF
CONTRA: LD DE,M_CONTRA
        JP PSTR

; ---------------------------------------------------------------- el menu
MKMENU: LD HL,ELEN
        LD B,26
MK0:    LD (HL),0
        INC HL
        DJNZ MK0
        LD C,0                  ; i
MK1:    LD HL,CRIB
        LD B,0
        ADD HL,BC
        LD A,(HL)
        SUB 'A'
        LD D,A                  ; a
        LD HL,CIPHER
        ADD HL,BC
        LD A,(HL)
        SUB 'A'
        LD E,A                  ; b
        CALL ADDE
        LD A,D
        LD D,E
        LD E,A
        CALL ADDE
        INC C
        LD A,C
        CP CRIBLEN
        JR NZ,MK1
        LD HL,ELEN              ; letra de prueba: la de mas conexiones (la primera)
        LD BC,0                 ; B = mejor cuenta, C = letra
        LD E,0
MK2:    LD A,(HL)
        CP B
        JR Z,MK3
        JR C,MK3
        LD B,A
        LD C,E
MK3:    INC HL
        INC E
        LD A,E
        CP 26
        JR NZ,MK2
        LD A,C
        LD (TEST),A
        RET
; ADDE: arista de la letra D a la letra E con desplazamiento C
ADDE:   PUSH DE
        PUSH BC
        PUSH DE
        LD E,D
        LD D,0
        LD HL,ELEN
        ADD HL,DE
        LD A,(HL)
        INC (HL)
        ADD A,A
        ADD A,A                 ; 4 bytes por arista
        LD L,A
        LD A,E
        ADD A,EDTH              ; una pagina por letra
        LD H,A
        POP DE
        INC L
        INC L
        LD (HL),C               ; i
        INC L
        LD A,E
        ADD A,MARKH
        LD (HL),A               ; pagina de marcas de b
        POP BC
        POP DE
        RET

; UPDE: puntero de cada arista a la tabla S_k, k = (r + i + 1) mod 26
UPDE:   LD C,0                  ; letra
UP1:    LD B,0
        LD HL,ELEN
        ADD HL,BC
        LD B,(HL)
        LD A,B
        OR A
        JR Z,UP4
        LD A,C
        ADD A,EDTH
        LD H,A
        LD L,2                  ; al campo i
UP2:    LD A,(RP)
        ADD A,(HL)
        INC A
UP3:    CP 26
        JR C,UP3B
        SUB 26
        JR UP3
UP3B:   RRCA
        RRCA
        RRCA
        LD D,A
        AND 0E0h                ; (k & 7) * 32
        DEC L
        DEC L
        LD (HL),A
        INC L
        LD A,D
        AND 1Fh                 ; k >> 3
        ADD A,SBH
        LD (HL),A
        INC L
        INC L
        INC L
        INC L
        INC L                   ; al i de la siguiente
        DJNZ UP2
UP4:    INC C
        LD A,C
        CP 26
        JR NZ,UP1
        RET

; ---------------------------------------------------------------- el revuelto
; ROWP: HL = tabla (DE) + t*1024 + k*32, con A = t y C = k
ROWP:   PUSH BC
        LD L,C
        LD H,0
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD HL,HL
        ADD A,A
        ADD A,A
        ADD A,H
        LD H,A
        ADD HL,DE
        POP BC
        RET
; CORE: M[x] con el rotor del medio en MP y el izquierdo en LP (reflector B)
CORE:   LD A,(MP)
        LD C,A
        LD A,(ORD+1)
        LD DE,FWT
        CALL ROWP
        LD (FWM),HL
        LD A,(ORD+1)
        LD DE,BWT
        CALL ROWP
        LD (BWM),HL
        LD A,(LP)
        LD C,A
        LD A,(ORD)
        LD DE,FWT
        CALL ROWP
        LD (FWL),HL
        LD A,(ORD)
        LD DE,BWT
        CALL ROWP
        LD (BWL),HL
        LD C,0
CO1:    LD A,C
        LD HL,(FWM)
        CALL LK
        LD HL,(FWL)
        CALL LK
        LD HL,REFB
        CALL LK16
        LD HL,(BWL)
        CALL LK
        LD HL,(BWM)
        CALL LK
        LD H,MH
        LD L,C
        LD (HL),A
        INC C
        LD A,C
        CP 26
        JR NZ,CO1
        RET
LK:     ADD A,L                 ; A = (HL + A), renglon de 32 alineado
        LD L,A
        LD A,(HL)
        RET
LK16:   LD E,A
        LD D,0
        ADD HL,DE
        LD A,(HL)
        RET
; SBUILD: S_k[x] = BW_r[k][ M[ FW_r[k][x] ] ] para las 26 posiciones k del rotor derecho
SBUILD: LD C,0
SB1:    LD A,(ORD+2)
        LD DE,BWT
        CALL ROWP
        LD (BWR),HL
        LD A,(ORD+2)
        LD DE,FWT
        CALL ROWP
        EX DE,HL                ; DE = FW_r[k]
        LD A,C
        RRCA
        RRCA
        RRCA
        LD B,A
        AND 1Fh
        ADD A,SBH
        LD IXH,A
        LD A,B
        AND 0E0h
        LD IXL,A
        LD B,26
SB2:    LD A,(DE)
        LD L,A
        LD H,MH
        LD A,(HL)
        LD HL,(BWR)
        ADD A,L
        LD L,A
        LD A,(HL)
        LD (IX+0),A
        INC IX
        INC DE
        DJNZ SB2
        INC C
        LD A,C
        CP 26
        JR NZ,SB1
        RET

; ---------------------------------------------------------------- la propagacion
; PROP: marcas desde "letra de prueba con X0". CY = se lleno el registro (26 vivos).
; La cola tiene una entrada por pareja (a,x): al sacarla se siguen las aristas de
; a con x y las de x con a (el tablero diagonal), y termina en FFh.
; Registros: IY = lectura de la cola, HL' = escritura.
PROP:   DI
        CALL PROP2
        EI
        RET
PROP2:  LD A,(GENV)
        INC A
        JR NZ,PG1
        CALL CLRMK
        LD A,1
PG1:    LD (GENV),A
        LD IXL,A
        XOR A
        LD (CNT),A
        LD IY,QUEUE
        EXX
        LD HL,QUEUE
        LD (HL),0FFh
        EXX
        LD A,(TEST)
        ADD A,MARKH
        LD D,A
        LD H,A
        LD A,(X0)
        LD E,A
        LD L,A
        LD A,(GENV)
        CALL ADDN
        RET C
PLOOP:  LD A,(IY+0)             ; a
        CP 0FFh
        RET Z                   ; cola vacia (CY = 0)
        LD C,(IY+1)             ; x
        INC IY
        INC IY
        CALL EXPAND
        RET C
        LD A,(IY-1)             ; y la diagonal: x con a
        LD C,(IY-2)
        CP C
        JR Z,PLOOP
        CALL EXPAND
        RET C
        JR PLOOP
; EXPAND: aristas de la letra A con la pareja C. Lee las aristas con POP: cada una
; es ptrL, ptrH (tabla S_k), i, pagina de marcas de b. Las interrupciones estan
; apagadas (PROP), y la pila de verdad se guarda en MSP.
EXPAND: LD L,A
        LD H,ELENH
        ADD A,EDTH
        LD B,(HL)
        INC B
        DEC B
        RET Z                   ; letra sin conexiones (CY = 0 por el ADD)
        LD H,A
        LD L,0
        LD (MSP),SP
        LD SP,HL
EL:     POP HL                  ; S_k
        LD A,L
        ADD A,C
        LD L,A
        LD L,(HL)               ; y
        POP DE                  ; D = pagina de b
        LD H,D
        LD A,(HL)
        CP IXL                  ; GEN
        JR Z,ELN                ; ya marcada (y su diagonal)
        LD (ESP),SP
        LD SP,(MSP)
        LD E,L
        PUSH BC
        LD A,IXL
        CALL ADDN
        POP BC
        RET C
        LD (MSP),SP
        LD SP,(ESP)
ELN:    DJNZ EL
        LD SP,(MSP)
        OR A
        RET
; ADDN: marca la celda (HL) = (b, y) y su diagonal (y, b) con A = GEN, encola
; la pareja y cuenta los cables de la letra de prueba. D = pagina de b, E = y.
; CY si el registro de prueba llego a 26.
ADDN:   LD (HL),A
        LD L,E
        LD A,D
        SUB MARKH
        LD D,A                  ; b
        LD A,E
        ADD A,MARKH
        LD H,A
        LD L,D
        LD A,(GENV)
        LD (HL),A               ; diagonal
        LD A,D
        EXX
        LD (HL),A
        INC HL
        EXX
        LD A,E
        EXX
        LD (HL),A
        INC HL
        LD (HL),0FFh
        EXX
        LD A,(TEST)
        CP D
        JR NZ,AN1
        LD HL,CNT
        INC (HL)
        CP E                    ; (A = TEST todavia)
        JR Z,AN3                ; b = y = prueba: una sola celda
        LD A,(HL)
        CP 26
        CCF
        RET
AN1:    CP E
        JR NZ,AN3
        LD HL,CNT
        INC (HL)
        LD A,(HL)
        CP 26
        CCF
        RET
AN3:    LD A,(CNT)
        CP 26
        CCF
        RET
CLRMK:  LD HL,MARK
        LD DE,MARK+1
        LD BC,26*256-1
        LD (HL),0
        LDIR
        RET

; ---------------------------------------------------------------- la Enigma
; DECRYPT: descifra CIPHER con ORD, posicion LP MP RP, anillos AAA y PLUG
DECRYPT: LD A,(LP)
        LD (EP),A
        LD A,(MP)
        LD (EP+1),A
        LD A,(RP)
        LD (EP+2),A
        LD HL,CIPHER
        LD B,0                  ; letras en el renglon
DC1:    LD A,(HL)
        OR A
        RET Z
        PUSH HL
        PUSH BC
        SUB 'A'
        CALL PRESS
        ADD A,'A'
        CALL PCH
        POP BC
        POP HL
        INC HL
        INC B
        LD A,B
        CP 50
        JR NZ,DC2
        CALL CRLF
        LD B,0
        JR DC1
DC2:    LD C,5                  ; espacio cada 5
DC3:    SUB C
        JR Z,DC4
        JR NC,DC3
        JR DC1
DC4:    LD A,(HL)
        OR A
        RET Z
        LD A,' '
        CALL PCH
        JR DC1
PRESS:  PUSH AF                 ; avance de los rotores (doble paso)
        LD A,(ORD+1)
        LD E,A
        LD D,0
        LD HL,NOTCH
        ADD HL,DE
        LD A,(EP+1)
        CP (HL)
        JR NZ,PR1
        CALL INC26M
        LD HL,EP
        CALL INC26
        JR PR2
PR1:    LD A,(ORD+2)
        LD E,A
        LD HL,NOTCH
        ADD HL,DE
        LD A,(EP+2)
        CP (HL)
        CALL Z,INC26M
PR2:    LD HL,EP+2
        CALL INC26
        POP AF
        CALL PLUGA
        LD B,2                  ; derecha a izquierda
        LD DE,FWT
        CALL ROT
        LD B,1
        CALL ROT
        LD B,0
        CALL ROT
        LD HL,REFB
        CALL LK16
        LD DE,BWT
        LD B,0
        CALL ROT
        LD B,1
        CALL ROT
        LD B,2
        CALL ROT
PLUGA:  LD HL,PLUG
        JP LK16
INC26M: LD HL,EP+1
INC26:  LD A,(HL)
        INC A
        CP 26
        JR NZ,I26
        XOR A
I26:    LD (HL),A
        RET
; ROT: A = tabla DE del rotor B (0 izq, 1 medio, 2 der) en su posicion
ROT:    PUSH DE
        PUSH AF
        LD HL,ORD
        LD C,B
        LD B,0
        ADD HL,BC
        LD A,(HL)
        PUSH AF
        LD HL,EP
        ADD HL,BC
        LD C,(HL)               ; k
        POP AF                  ; t
        CALL ROWP
        POP AF
        CALL LK
        POP DE
        RET

; ---------------------------------------------------------------- impresion
PORD:   LD HL,ORD
        LD B,3
PO1:    PUSH HL
        PUSH BC
        LD A,(HL)
        ADD A,A
        ADD A,A
        LD E,A
        LD D,0
        LD HL,ROMAN
        ADD HL,DE
        EX DE,HL
        CALL PSTR
        POP BC
        POP HL
        INC HL
        DEC B
        RET Z
        LD A,'-'
        CALL PCH
        JR PO1
PPOS:   LD A,(LP)
        ADD A,'A'
        CALL PCH
        LD A,(MP)
        ADD A,'A'
        CALL PCH
        LD A,(RP)
        ADD A,'A'
        JP PCH
PLEN:   LD A,(HL)
        CALL PCH
        INC HL
        DJNZ PLEN
        RET
; GROUPS: texto terminado en 0, en grupos de 5 y 50 letras por renglon
GROUPS: LD B,0
GR1:    LD A,(HL)
        OR A
        JP Z,CRLF
        CALL PCH
        INC HL
        INC B
        LD A,B
        CP 50
        JR NZ,GR2
        CALL CRLF
        LD B,0
        JR GR1
GR2:    SUB 5
        JR Z,GR3
        JR NC,GR2
        JR GR1
GR3:    LD A,(HL)
        OR A
        JP Z,CRLF
        LD A,' '
        CALL PCH
        JR GR1

INCLUDE comun.inc

ROMAN:  DEFB 'I$  II$ III$IV$ V$  '
M_HELLO: DEFB 13,10,'THE TURING-WELCHMAN BOMBE on the Z80-Retro',13,10
        DEFB 'Intercept (Enigma I, weather report, North Sea):',13,10,'$'
M_CRIB: DEFB 'Crib (assumed start):  $'
M_UNDER: DEFB 'Ciphertext under it:   $'
M_MENU: DEFB 'Menu: 25 connections, test letter $'
M_WITH: DEFB ' ($'
M_CONN: DEFB ' connections)',13,10,'$'
M_ORDER: DEFB 'Order $'
M_COLON: DEFB ': $'
M_STOP: DEFB 'STOP $'
M_STECK: DEFB 'Stecker $'
M_CONTRA: DEFB 'contradiction (false stop)',13,10,'$'
M_STOPS: DEFB 'Stops: $'
ALLM:   DEFB 0
ORD:    DEFS 3
LP:     DEFB 0
MP:     DEFB 0
RP:     DEFB 0
TEST:   DEFB 0
X0:     DEFB 0
ST:     DEFB 0
GENV:   DEFB 0
CNT:    DEFB 0
QR:     DEFW 0
QW:     DEFW 0
MSP:    DEFW 0
ESP:    DEFW 0
NSTOP:  DEFW 0
FWM:    DEFW 0
BWM:    DEFW 0
FWL:    DEFW 0
BWL:    DEFW 0
BWR:    DEFW 0
EP:     DEFS 3
PART:   DEFS 26
PLUG:   DEFS 26
        DEFS 128
STACK:
INCLUDE bombe_data.inc
        ORG ($+255)/256*256
MTAB    EQU $
MH      EQU MTAB/256
ELEN    EQU MTAB+256        ; conexiones por letra (pagina propia)
ELENH   EQU ELEN/256
SB      EQU MTAB+512
SBH     EQU SB/256
EDT     EQU SB+1024
EDTH    EQU EDT/256
MARK    EQU EDT+26*256
MARKH   EQU MARK/256
QUEUE   EQU MARK+26*256
        ASSERT QUEUE+1400 < 0C000h
        END
