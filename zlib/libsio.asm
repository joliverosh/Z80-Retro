;==================================================================================
; Original by Grant Searle
; Modified by
; http://searle.hostei.com/grant/index.html
; eMail: home.micros01@btinternet.com
;
; Modifed by smbaker@smbaker.com for use as general-purpose IO for nixie tube
; clock. Also added support for CTC chip. Switched to SIO implementation instead
; of 68B50. Removed all basic-related stuff.
; (https://github.com/sbelectronics/rc2014/blob/master/asm/intsio.asm)
;
; Heavily re-written and stripped down by petew@yellowhawk.co.uk to drive a minimal
; Z80 board using a single SIO. CTC code removed and port B removed. Also added in
; a hacky Ctrl-C tracker with call out in the SIO interrupt routine to allow my
; debugger to break into errant code. Works fine with unmodified RC2014
; Nascom/Microsoft BASIC.
;
; Interrupts:
;    RST08 - TX the character in A reg on port A
;    RST10 - RX a character from port A
;    RST18 - Check port status on Port A
;    RST20 - Initialise the SIO
;    RST38 - Hardware interrupt from SIO
;
;
;==================================================================================
; import config.asm
import defs.asm

                public INITSIO,SIO_OFF,TXA,RXA,CKINCHAR,_ENDLIBS,SERINT
                public SERINTB,TXB,RXB,CKINB,SIO_CFG,SIOB_MD,SIOA_W4,SIOB_W4
                extrn  BRK_HK

; Full input buffering with incoming data hardware handshaking
; Handshake shows full before the buffer is totally filled to allow run-on from the sender

; EXPORTED FUNCTIONS:
;    TXA:       Transmit a character on port A. USUALLY INSTALLED AS RST 08h
;    RXA:       Wait for a character on port A. USUALLY INSTALLED AS RST 10h
;    CKINCHAR:  Check to see whether there's a character in the port A buffer. Z if no characters. NZ otherwise
;                                               USUALLY INSTALLED AS RST 18h
;    INITSIO:   Initialise the SIO for both ports A and B - installed on RST 20h but never used in that way!
;    SERINT:    Interrupt handler - needs to be installed at RST 38h as part of INITSIO

SER_BUFSIZE     .EQU     $F0
SER_FULLSIZE    .EQU     SER_BUFSIZE / 2
SER_EMPTYSIZE   .EQU     10H

; Canal B (modo serie general): buffer mas chico
SERB_BUFSIZE    .EQU     80H
SERB_FULLSIZE   .EQU     40H
SERB_EMPTYSIZE  .EQU     10H

; Modo de reloj de la SIO en WR4 (bits 7-6): x16, x32, x64. 1 bit de parada, sin paridad.
W4_X16          .EQU     01000100b
W4_X32          .EQU     10000100b
W4_X64          .EQU     11000100b

                CSEG

SERINT:         PUSH     AF
nextchr:        XOR      A
                OUT      (SIOA_C),A
                IN       A, (SIOA_C)      ; Read Reg 0: Bit 0: Character available
                RRCA
                JR       NC, rts0         ; Should be a character but maybe not...

                IN       A,(SIOA_D)       ; Get the character - frees the input FIFO

                PUSH     HL

                ; Check if this is a break character and if it is has anyone registered a break handler?
                CP       3h               ; Character still in A

                ; CTRL-C - is there a handler?
                JR       Z,brk

                ; If the break handler isn't installed continue from here.
proc:           PUSH     AF              ; Make sure we have enough room for this character
                LD       A,(serBufUsed)
                CP       SER_BUFSIZE     ; If full then ignore
                JR       Z,_full

                INC      A
                LD       (serBufUsed),A
                CP       SER_FULLSIZE    ; Check H/W flow control
                JR       NC,setrts

norts:          LD       HL,(serInPtr)
                INC      HL
                LD       A,L             ; Only need to check low byte becasuse buffer<256 bytes
                CP       serInPtr
                JR       NZ, notWrap
                LD       HL,serBuf
notWrap:        LD       (serInPtr),HL
                POP      AF
                LD       (HL),A
                POP      HL
                ; Before leaving, check for another character to save an interrupt.
                JR       nextchr

                ; set rts high
setrts:         SIO_WR   A,5,RTS_HIGH
                JR       norts

_full:          POP      AF
                POP      HL
                ; Drop through to return

                ; No characters left...
rts0:           POP      AF
                RET

                ; There is a break handler. Hack the stack so we return to the
                ; handler
brk:            LD       HL,(BRK_HK)
                LD       A,L            ; Null break handler?
                OR       H
                LD       A,3
                JR       Z,proc

                ; The break handler will have a stack that looks like:
                ;    Ret address from SERINT
                ;    AF at start of ISR
                ;    HL at start of ISR
                ;    AF containing the break character
                ;    <--- SP
                ; Still running in the interrupt routine (needs a RETI at some point)
                JP       (HL)

;------------------------------------------------------------------------------
RXA:
waitForChar:    LD       A,(serBufUsed)
                OR       A
                JR       Z, waitForChar
                PUSH     HL
                LD       HL,(serRdPtr)
                INC      HL
                LD       A,L             ; Only need to check low byte becasuse buffer<256 bytes
                CP       serInPtr
                JR       NZ, notRdWrap
                LD       HL,serBuf
notRdWrap:      LD       (serRdPtr),HL
                DI
                LD       A,(serBufUsed)
                DEC      A
                LD       (serBufUsed),A
                CP       SER_EMPTYSIZE
                JR       NC,rts1

                ; set rts low
                SIO_WR   A,5,RTS_LOW

rts1:           LD       A,(HL)
                EI
                POP      HL
                CP       7fh             ; If it's a DEL character then make it a backspace
                RET      NZ
                LD       A,08h
                RET                      ; Char ready in A

;------------------------------------------------------------------------------
; ---- SERINTB
; Interrupcion de recepcion del canal B (solo en modo serie general). Igual que
; SERINT pero sin Ctrl-C y con su propio buffer y control de flujo (RTS B).
SERINTB:        PUSH     AF
_nxtb:          XOR      A
                OUT      (SIOB_C),A
                IN       A,(SIOB_C)
                RRCA
                JR       NC,_rtsb0
                IN       A,(SIOB_D)
                PUSH     HL
                PUSH     AF
                LD       A,(serBUsed)
                CP       SERB_BUFSIZE    ; Lleno: se descarta
                JR       Z,_fullb
                INC      A
                LD       (serBUsed),A
                CP       SERB_FULLSIZE
                JR       C,_nortsb
                SIO_WR   B,5,RTS_HIGH    ; Pedir al otro lado que pare
_nortsb:        LD       HL,(serBIn)
                INC      HL
                LD       A,(serBEnd)     ; Byte bajo de la direccion de fin del buffer
                CP       L
                JR       NZ,_nwrb
                LD       HL,serBufB
_nwrb:          LD       (serBIn),HL
                POP      AF
                LD       (HL),A
                POP      HL
                JR       _nxtb
_fullb:         POP      AF
                POP      HL
_rtsb0:         POP      AF
                RET

; ---- RXB: esperar un caracter del canal B (sin conversion de DEL)
RXB:            LD       A,(serBUsed)
                OR       A
                JR       Z,RXB
                PUSH     HL
                LD       HL,(serBRd)
                INC      HL
                LD       A,(serBEnd)
                CP       L
                JR       NZ,_nrwb
                LD       HL,serBufB
_nrwb:          LD       (serBRd),HL
                DI
                LD       A,(serBUsed)
                DEC      A
                LD       (serBUsed),A
                CP       SERB_EMPTYSIZE
                JR       NC,_rtsb1
                SIO_WR   B,5,RTS_LOW     ; Hay espacio: el otro lado puede seguir
_rtsb1:         LD       A,(HL)
                EI
                POP      HL
                RET

; ---- TXB: mandar el caracter en A por el canal B
TXB:            PUSH     AF
_txbw:          XOR      A
                OUT      (SIOB_C),A
                IN       A,(SIOB_C)
                BIT      2,A
                JR       Z,_txbw
                POP      AF
                OUT      (SIOB_D),A
                RET

; ---- CKINB: Z si no hay caracteres en el canal B, NZ si hay
CKINB:          LD       A,(serBUsed)
                OR       A
                RET

;------------------------------------------------------------------------------
TXA:            PUSH     AF              ; Store character
conout1:        XOR      A
                OUT      (SIOA_C),A
                IN       A,(SIOA_C)
                BIT      2,A             ; Set if still transmitting character
                JR       Z,conout1       ; Loop until flag signals ready
                POP      AF              ; Retrieve character
                OUT      (SIOA_D),A      ; Output the character
                RET
;------------------------------------------------------------------------------
CKINCHAR:       LD       A,(serBufUsed)
                OR       A
                RET

;------------------------------------------------------------------------------
; Initialise the SIO handlers. Assumed we're running from RAM and called from
; the application runtime and the memory paging is initialised. This library doesn't
; understand how the memory is managed. Also assuming the stack has been initialised.
; INPUT: A - 0: canal B en modo serie general (con interrupciones y buffer);
;            1: canal B reservado para el protocolo de bloques de la Raspberry Pi
;        SIOA_W4 / SIOB_W4: modo de reloj (WR4) de cada canal; 0 = el de siempre
INITSIO:      DI
              PUSH     AF
              LD       (SIOB_MD),A

              ; initialize input buffer for Port A
              LD        HL,serBuf
              LD        (serInPtr),HL
              LD        (serRdPtr),HL
              LD        HL,serBufB
              LD        (serBIn),HL
              LD        (serBRd),HL
              LD        HL,serBIn       ; Fin del buffer del canal B (byte bajo)
              LD        A,L
              LD        (serBEnd),A
              XOR       A
              LD        (serBufUsed),A
              LD        (serBUsed),A

              ; Fully disable/reset the SIO channels
              CALL    SIO_OFF

              ; Start programming both channels from scratch.

              ; SET INTERRUPT VECTOR - ONLY USED FOR PORT A but set through port B. Port A is polled.
              SIO_WR  B,2,SIO_INTV   ; INTERRUPT VECTOR ADDRESS

              CALL    _inita
              CALL    _initb
              POP     AF
              RET

; ---- _inita / _initb: programar un canal (WR4 primero, como pide el manual)
_inita:       LD      A,4
              OUT     (SIOA_C),A
              LD      A,(SIOA_W4)
              OR      A
              JR      NZ,_a4
              LD      A,W4_X64       ; X64: 115200 con 7,3728 MHz (230400 con 14,7 MHz)
_a4:          OUT     (SIOA_C),A
              SIO_WR  A,1,00011000b  ; interrupt on all recv
              SIO_WR  A,3,11100001b  ; 8 bits, auto enable, rcv enable
              SIO_WR  A,5,RTS_LOW    ; dtr enable, 8 bits, tx enable, rts OFF
              RET

_initb:       LD      A,4
              OUT     (SIOB_C),A
              LD      A,(SIOB_W4)
              OR      A
              JR      NZ,_b4
              LD      A,(SIOB_MD)
              OR      A
              LD      A,W4_X64       ; Serie general: igual que el canal A
              JR      Z,_b4
              LD      A,W4_X32       ; Protocolo de la Pi: x32 (230400 con 7,3728 MHz)
_b4:          OUT     (SIOB_C),A
              ; WR1 del canal B: bit 2 = el estado modifica el vector (para los dos
              ; canales). En modo serie tambien interrumpe en cada caracter recibido.
              LD      A,1
              OUT     (SIOB_C),A
              LD      A,(SIOB_MD)
              OR      A
              LD      A,00000100b
              JR      NZ,_b1
              LD      A,00011100b
_b1:          OUT     (SIOB_C),A
              SIO_WR  B,3,11000001b  ; WR3 - Enable receiver, 8 bits per character
              SIO_WR  B,5,RTS_LOW    ; WR5 - TX 8 bits/char, Enable TX
              RET

; ---- SIO_CFG
; Cambiar el modo de reloj de un canal en caliente.
; INPUT: B - canal (0 = A, 1 = B); A - valor de WR4 (W4_X16/X32/X64)
SIO_CFG:      PUSH    AF
              DI
              LD      C,A
              LD      A,B
              OR      A
              LD      A,C
              JR      NZ,_cfb
              LD      (SIOA_W4),A
              CALL    _inita
              JR      _cfx
_cfb:         LD      (SIOB_W4),A
              CALL    _initb
_cfx:         EI
              POP     AF
              RET

; ------ Close down both channel 1 and 2, prevent further interrupts.
SIO_OFF:      XOR       A
              LD        (serBufUsed),A

              ; Channel A - RESET
              SIO_C   A,00011000b    ; Channel reset
              SIO_C   A,00110000b    ; Error reset
              SIO_WR  A,1,0          ; Disable interrupts

              ; Channel B - RESET
              SIO_C   B,00011000b    ; Channel reset
              SIO_C   B,00110000b    ; Error reset
              SIO_WR  B,1,0          ; Disable interrupts
              RET

_ENDLIBS:
                DSEG
serBuf          .DS      SER_BUFSIZE
serInPtr        .DS      2
serRdPtr        .DS      2
serBufUsed      .DS      1

; Canal B. serBIn debe ir justo despues del buffer (ver la comparacion de fin).
serBufB         .DS      SERB_BUFSIZE
serBIn          .DS      2
serBRd          .DS      2
serBUsed        .DS      1
SIOB_MD         .DS      1        ; 0 serie general, 1 protocolo de la Pi
SIOA_W4         .DS      1        ; WR4 del canal A (0 = por omision)
SIOB_W4         .DS      1        ; WR4 del canal B (0 = por omision)
serBEnd         .DS      1        ; Byte bajo de la direccion de serBIn

useisr          .DS      1

;.END
