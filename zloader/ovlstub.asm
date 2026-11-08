; **********************************************
; ovlstub.asm (v6)
; La pagina de ZLoader esta casi llena, asi que las ordenes nuevas de la v6
; (TEST, REV y OLED) viven en la pagina 02 de la flash, desde 1000h (de 0000 a
; 0FFF esta el juego de caracteres de la tarjeta de video y en 3FF0 la cabecera
; del disco en flash). Se enlazan en 9000h: con la pagina 02 en el banco 2,
; 9000h es justo su desplazamiento 1000h. Este modulo, en la pagina de ZLoader,
; mapea esa pagina, llama a la orden y deja los bancos 1 y 2 como estaban.
; **********************************************
import defs.asm
import config.asm
import pcb_def.asm
import macros.asm

  extrn  main,OVL_ENT

  public TESTC,REVC,OLEDC,OVLBOOT,OVLCALL,OVLBUF,LINEBUF

OVL_PG    EQU   FSH_PG_0+2          ; Pagina de flash del overlay

          CSEG

TESTC:    XOR   A
          JR    _ovcmd
REVC:     LD    A,1
          JR    _ovcmd
OLEDC:    LD    A,2
_ovcmd:   CALL  OVLCALL
          JP    main

; Al arrancar: pantalla OLED (si responde) y pitido (en la Rev 2.3)
OVLBOOT:  LD    A,3
OVLCALL:  PUSH  AF
          LD    A,OVL_PG
          OUT   (PG_PORT0+2),A
          POP   AF
          CALL  OVL_ENT
          BANK  1,(PAGE_MP+1)
          BANK  2,(PAGE_MP+2)
          RET

          DSEG
OVLBUF:   DEFS  40              ; Datos de las ordenes del overlay
LINEBUF:  DEFS  24              ; Una linea de texto para la pantalla OLED
