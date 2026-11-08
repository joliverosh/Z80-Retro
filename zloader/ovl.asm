; **********************************************
; ovl.asm (v6) - ordenes que viven en la pagina 02 de la flash (ver ovlstub.asm)
;   TEST           prueba de la placa: RAM, bus del puerto 64h, SD, reloj, OLED
;                  y, en la ZEPHYRUS, GPIO y altavoz
;   REV [2.2|2.3]  placa en la que corre (se guarda en la NVRAM)
;   OLED           estado en una pantalla SSD1306 en el bus I2C (3Ch)
; Se enlaza en 9000h. Mientras corre, el banco 2 tiene la pagina 02 de la
; flash y el banco 1 se usa para probar la RAM; ovlstub.asm los restaura.
; No tiene segmento de datos: usa OVLBUF y LINEBUF de ovlstub.asm.
; **********************************************
import defs.asm
import config.asm
import zlib.asm
import zios.asm

  extrn  MEM_TOT,LD_TICK,BEEP,OVLBUF,LINEBUF
  extrn  SD_TINI,SD_SEL,I2C_STRT,I2C_WBY,I2C_STOP

  public OVL_ENT

; OVLBUF+39: fallas de TEST; OVLBUF+20: texto del resultado para la pantalla (17 bytes)
OLADDR    EQU   78h             ; SSD1306 en 3Ch (78h en 8 bits)
RTCADDR   EQU   0D0h            ; DS1307

          CSEG

; ------ OVL_ENT: A = 0 TEST, 1 REV, 2 OLED, 3 arranque, 4 linea "Placa" de DH,
;        5 texto del reloj del CTC para BAUD, 6 aviso del puente para BAUD
OVL_ENT:  OR    A
          JP    Z,TEST
          DEC   A
          JR    Z,REV
          DEC   A
          JR    Z,OLED_
          DEC   A
          JR    Z,BOOTO
          DEC   A
          JR    Z,DHBRD
          DEC   A
          JR    Z,BAUDCK
          JR    BAUDJ
OLED_:    JP    OLED

; ---------------------------------------------------------------- placa
; Z si la placa es la Rev 2.3
IS23:     LD    A,(NVRAM+NV_BOARD)
          CP    BRD_23
          RET

; HL = nombre de la placa
BRDNAME:  CALL  IS23
          LD    HL,_b23
          RET   Z
          LD    HL,_b22
          RET

DHBRD:    LD    HL,_m_plc
          CALL  PRINT
          CALL  BRDNAME
          JP    PRINT_LN

BAUDCK:   LD    HL,_m_ck22
          CALL  IS23
          JR    NZ,_bck
          LD    HL,_m_ck23
_bck:     JP    PRINT
BAUDJ:    LD    HL,_m_bj22
          CALL  IS23
          JR    NZ,_bj
          LD    HL,_m_bj23
_bj:      JP    PRINT_LN

; ---------------------------------------------------------------- REV
REV:      CALL  WASTESPC
          JR    Z,_rvshow
          LD    B,0             ; Ultima cifra leida
_rvch:    CALL  BUFCHR
          OR    A
          JR    Z,_rvend
          CP    ' '
          JR    Z,_rvend
          CP    '0'
          JR    C,_rvch
          CP    '9'+1
          JR    NC,_rvch
          LD    B,A
          JR    _rvch
_rvend:   LD    A,B
          LD    C,0
          CP    '2'
          JR    Z,_rvset
          LD    C,BRD_23
          CP    '3'
          JR    Z,_rvset
          LD    HL,_m_rvbad
          JP    PRINT_LN
_rvset:   LD    A,C
          LD    (NVRAM+NV_BOARD),A
          CALL  NVSAV
          LD    HL,_m_rvok
          CALL  PRINT
_rvshow:  CALL  DHBRD
          LD    HL,_m_rvh
          JP    PRINT_LN

; ---------------------------------------------------------------- arranque
BOOTO:    CALL  OLPROBE
          CALL  Z,OLSTAT0
          CALL  IS23
          CALL  Z,BEEP
          RET

; ---------------------------------------------------------------- OLED
OLED:     CALL  OLPROBE
          JR    Z,_olok
          LD    HL,_m_nool
          JP    PRINT_LN
_olok:    CALL  OLSTAT0
          LD    HL,_m_olok
          JP    PRINT_LN

; Z si la pantalla responde en 3Ch
OLPROBE:  LD    A,OLADDR
          JR    I2PROBE
RTCPROBE: LD    A,RTCADDR
I2PROBE:  PUSH  AF
          CALL  I2C_STRT
          POP   AF
          CALL  I2C_WBY
          AND   1               ; 0 = ACK
          PUSH  AF
          CALL  I2C_STOP
          POP   AF
          RET

; Pantalla de estado sin linea de TEST
OLSTAT0:  LD    HL,0
; Pantalla de estado. HL = texto de la linea 6 (0 = vacia)
OLSTAT:   PUSH  HL
          ; Inicializacion del SSD1306
          CALL  _olcmd0
          LD    HL,_olinit
          LD    B,_olinitn
_oli:     LD    A,(HL)
          INC   HL
          CALL  I2C_WBY
          DJNZ  _oli
          CALL  I2C_STOP
          ; Linea 0: version
          LD    DE,LINEBUF
          LD    HL,_m_ver
          CALL  LBSTR
          XOR   A
          CALL  OLLINE
          ; Linea 1: placa
          LD    DE,LINEBUF
          CALL  BRDNAME
          CALL  LBSTR
          LD    A,1
          CALL  OLLINE
          ; Linea 2: fecha y hora del DS1307
          LD    DE,LINEBUF
          CALL  RTCPROBE
          JR    NZ,_olnrtc
          LD    HL,OVLBUF
          CALL  RTC_GET
          LD    A,'2'
          LD    (DE),A
          INC   DE
          LD    A,'0'
          LD    (DE),A
          INC   DE
          LD    A,(OVLBUF+6)    ; Ano
          CALL  LBBCD
          LD    A,'-'
          LD    (DE),A
          INC   DE
          LD    A,(OVLBUF+5)    ; Mes
          CALL  LBBCD
          LD    A,'-'
          LD    (DE),A
          INC   DE
          LD    A,(OVLBUF+4)    ; Dia
          CALL  LBBCD
          LD    A,' '
          LD    (DE),A
          INC   DE
          LD    A,(OVLBUF+2)    ; Hora
          AND   3Fh
          CALL  LBBCD
          LD    A,':'
          LD    (DE),A
          INC   DE
          LD    A,(OVLBUF+1)    ; Minutos
          CALL  LBBCD
          JR    _ol2
_olnrtc:  LD    HL,_m_nortc
          CALL  LBSTR
_ol2:     XOR   A
          LD    (DE),A
          LD    A,2
          CALL  OLLINE
          ; Linea 3: tarjetas SD
          LD    DE,LINEBUF
          LD    HL,_m_sd1
          CALL  LBSTR
          CALL  SD_PRES          ; Bit 0 = SD1, bit 1 = SD2
          PUSH  AF
          CALL  LBSINO
          LD    HL,_m_sd2
          CALL  LBSTR
          POP   AF
          RRCA
          CALL  LBSINO
          LD    A,3
          CALL  OLLINE
          ; Linea 4: RAM
          LD    DE,LINEBUF
          LD    HL,_m_ram
          CALL  LBSTR
          LD    A,(MEM_TOT)
          LD    L,A
          LD    H,0
          ADD   HL,HL
          ADD   HL,HL
          ADD   HL,HL
          ADD   HL,HL
          CALL  LBDEC
          LD    HL,_m_kb
          CALL  LBSTR
          LD    A,4
          CALL  OLLINE
          ; Linea 5: vacia
          LD    DE,LINEBUF
          XOR   A
          LD    (DE),A
          LD    A,5
          CALL  OLLINE
          ; Linea 6: resultado de TEST (si hay)
          POP   HL
          LD    DE,LINEBUF
          XOR   A
          LD    (DE),A
          LD    A,H
          OR    L
          CALL  NZ,LBSTR
          LD    A,6
          CALL  OLLINE
          ; Linea 7: firma
          LD    DE,LINEBUF
          LD    HL,_m_oli
          CALL  LBSTR
          LD    A,7
          JR    OLLINE

; Empieza un flujo de comandos para la pantalla
_olcmd0:  CALL  I2C_STRT
          LD    A,OLADDR
          CALL  I2C_WBY
          XOR   A               ; Control: comandos
          JP    I2C_WBY

; Escribir LINEBUF en la pagina (fila de 8 pixeles) A de la pantalla
OLLINE:   PUSH  AF
          CALL  _olcmd0
          LD    A,21h           ; Columnas 0-127
          CALL  I2C_WBY
          XOR   A
          CALL  I2C_WBY
          LD    A,7Fh
          CALL  I2C_WBY
          LD    A,22h           ; Pagina A
          CALL  I2C_WBY
          POP   AF
          PUSH  AF
          CALL  I2C_WBY
          POP   AF
          CALL  I2C_WBY
          CALL  I2C_STOP
          CALL  I2C_STRT
          LD    A,OLADDR
          CALL  I2C_WBY
          LD    A,40h           ; Control: datos
          CALL  I2C_WBY
          LD    C,128           ; Columnas por escribir
          LD    HL,LINEBUF
_oll1:    LD    A,(HL)
          OR    A
          JR    Z,_ollpad
          INC   HL
          PUSH  HL
          SUB   ' '
          CP    95
          JR    C,_oll2
          LD    A,'?'-' '
_oll2:    LD    L,A             ; HL = OVFONT + A x 6
          LD    H,0
          ADD   HL,HL
          LD    D,H
          LD    E,L
          ADD   HL,HL
          ADD   HL,DE
          LD    DE,OVFONT
          ADD   HL,DE
          LD    B,6
_oll3:    LD    A,(HL)
          INC   HL
          CALL  I2C_WBY
          DEC   C
          DJNZ  _oll3
          POP   HL
          LD    A,C
          CP    6
          JR    NC,_oll1
_ollpad:  LD    A,C
          OR    A
          JR    Z,_olle
_ollp:    XOR   A
          CALL  I2C_WBY
          DEC   C
          JR    NZ,_ollp
_olle:    JP    I2C_STOP

; ---- Construccion de lineas en (DE)
; Copiar el texto HL (termina en 0) a DE; deja DE en el 0 final
LBSTR:    LD    A,(HL)
          LD    (DE),A
          OR    A
          RET   Z
          INC   HL
          INC   DE
          JR    LBSTR

; Dos cifras BCD de A
LBBCD:    PUSH  AF
          RRCA
          RRCA
          RRCA
          RRCA
          CALL  _lbnib
          POP   AF
_lbnib:   AND   0Fh
          ADD   A,'0'
          LD    (DE),A
          INC   DE
          RET

; "si" o "no" segun el bit 0 de A
LBSINO:   LD    HL,_m_si
          BIT   0,A
          JR    NZ,LBSTR
          LD    HL,_m_no
          JR    LBSTR

; HL en decimal (sin ceros a la izquierda)
LBDEC:    LD    B,0             ; Ya hubo una cifra
          PUSH  DE
          LD    DE,10000
          CALL  _lbd
          LD    DE,1000
          CALL  _lbd
          LD    DE,100
          CALL  _lbd
          LD    DE,10
          CALL  _lbd
          POP   DE
          LD    A,L
          ADD   A,'0'
          LD    (DE),A
          INC   DE
          XOR   A
          LD    (DE),A
          RET
_lbd:     LD    A,'0'-1
_lbd1:    INC   A
          OR    A
          SBC   HL,DE
          JR    NC,_lbd1
          ADD   HL,DE
          CP    '0'
          JR    NZ,_lbd2
          INC   B
          DEC   B
          RET   Z               ; Cero a la izquierda: no se escribe
_lbd2:    LD    B,1
          POP   DE              ; Direccion de retorno
          EX    (SP),HL         ; HL = destino, en la pila el valor
          LD    (HL),A
          INC   HL
          EX    (SP),HL
          PUSH  DE
          RET

; ---------------------------------------------------------------- TEST
TEST:     LD    HL,_t_hdr
          CALL  PRINT
          CALL  DHBRD
          XOR   A
          LD    (OVLBUF+39),A

          ; -- 1. RAM: cada byte de cada pagina con 55h y AAh, sin perder lo
          ;    que tenia (las interrupciones se apagan mientras se prueba)
          LD    HL,_t_ram
          CALL  PRINT
          LD    A,(MEM_TOT)
          LD    B,A
          LD    C,RAM_PG_0
_trp:     PUSH  BC
          LD    A,C
          OUT   (PG_PORT0+1),A
          DI
          CALL  _rtest
          EI
          POP   BC
          JR    NZ,_trbad
          LD    A,'.'
          RST   08h
          INC   C
          DJNZ  _trp
          ; Cada pagina es distinta (sin direcciones repetidas): hasta 32
          CALL  _alias
          JR    NZ,_tral
          LD    HL,_t_ok
          CALL  PRINT_LN
          JR    _tbus
_trbad:   PUSH  HL
          LD    HL,_t_rbad
          CALL  PRINT
          LD    A,C
          CALL  WRITE_8
          LD    HL,_t_dir
          CALL  PRINT
          POP   HL
          CALL  WRITE_16
          CALL  NL
          CALL  _fail
          JR    _tbus
_tral:    PUSH  AF
          LD    HL,_t_alias
          CALL  PRINT
          POP   AF
          CALL  WRITE_8
          CALL  NL
          CALL  _fail

          ; -- 2. Bus del puerto 64h: sin dispositivo seleccionado MISO (bit 0)
          ;    debe leerse en 1 por la resistencia de RP; en 0 es la falla de la
          ;    placa vieja (algo tira MISO abajo)
_tbus:    LD    HL,_t_bus
          CALL  PRINT
          IN    A,(64h)
          AND   1
          LD    HL,_t_bus1
          JR    NZ,_tbus2
          LD    HL,_t_bus0
          CALL  _fail
_tbus2:   CALL  PRINT_LN

          ; -- 3. Tarjetas SD
          LD    C,0
_tsd:     LD    HL,_t_sd
          CALL  PRINT
          LD    A,C
          INC   A
          ADD   A,'0'
          RST   08h
          LD    A,':'
          RST   08h
          LD    A,' '
          RST   08h
          CALL  SD_PRES
          BIT   0,C
          JR    Z,_tsd1
          RRCA
_tsd1:    RRCA
          LD    HL,_t_sdno
          JR    NC,_tsdp
          PUSH  BC
          LD    A,C
          CALL  SD_TINI
          POP   BC
          LD    HL,_t_sdsc
          CP    1
          JR    Z,_tsdp
          LD    HL,_t_sdhc
          CP    2
          JR    Z,_tsdp
          LD    HL,_t_sdnr
_tsdp:    CALL  PRINT_LN
          INC   C
          LD    A,C
          CP    2
          JR    C,_tsd
          XOR   A
          CALL  SD_SEL           ; Dejar seleccionada la tarjeta 1

          ; -- 4. Reloj DS1307
          LD    HL,_t_rtc
          CALL  PRINT
          CALL  RTCPROBE
          LD    HL,_t_nr
          JR    NZ,_trtcf
          LD    HL,OVLBUF
          CALL  RTC_GET
          LD    A,(OVLBUF)
          LD    HL,_t_rtcst
          BIT   7,A              ; CH = 1: oscilador parado
          JR    NZ,_trtcf
          LD    (OVLBUF+30),A
          ; Esperar 1,25 s y ver que avanzo (dos esperas: con 14,7456 MHz son
          ; 240 tics por segundo y 1,25 s no cabe en un byte)
          CALL  LD_TICK
          PUSH  AF
          CALL  _wait
          POP   AF
          SRL   A
          SRL   A
          CALL  _wait
          LD    HL,OVLBUF
          CALL  RTC_GET
          LD    A,(OVLBUF)
          LD    HL,OVLBUF+30
          CP    (HL)
          LD    HL,_t_rtcna
          JR    Z,_trtcf
          LD    HL,_t_rtcok
          JR    _trtcp
_trtcf:   CALL  _fail
_trtcp:   CALL  PRINT_LN

          ; -- 5. Pantalla OLED (no es una falla si no hay)
          LD    HL,_t_ol
          CALL  PRINT
          CALL  OLPROBE
          LD    HL,_m_si
          JR    Z,_tolp
          LD    HL,_m_no
_tolp:    CALL  PRINT_LN

          ; -- 6. ZEPHYRUS: GPIO y altavoz
          CALL  IS23
          JR    NZ,_tres
          LD    HL,_t_gpio
          CALL  PRINT_LN
          LD    B,6
          LD    C,1
_tgp:     LD    A,C
          OUT   (6Ch),A
          PUSH  BC
          CALL  LD_TICK
          SRL   A
          SRL   A               ; 1/4 s
          CALL  _wait
          POP   BC
          SLA   C
          DJNZ  _tgp
          XOR   A
          OUT   (6Ch),A
          LD    HL,_t_spk
          CALL  PRINT_LN
          CALL  BEEP

          ; -- Resultado
_tres:    LD    A,(OVLBUF+39)
          OR    A
          JR    NZ,_tresf
          LD    HL,_t_allok
          CALL  PRINT_LN
          LD    HL,_t_olok
          JR    _tresol
_tresf:   LD    HL,_t_res
          CALL  PRINT
          LD    A,(OVLBUF+39)
          ADD   A,'0'
          RST   08h
          LD    HL,_t_res2
          CALL  PRINT_LN
          ; Linea para la pantalla: "TEST: n FALLA(S)" (OLSTAT reescribe
          ; LINEBUF, asi que se arma en OVLBUF+20)
          LD    DE,OVLBUF+20
          LD    HL,_t_olf1
          CALL  LBSTR
          LD    A,(OVLBUF+39)
          ADD   A,'0'
          LD    (DE),A
          INC   DE
          LD    HL,_t_olf2
          CALL  LBSTR
          LD    HL,OVLBUF+20
_tresol:  PUSH  HL
          CALL  OLPROBE
          POP   HL
          RET   NZ
          JP    OLSTAT

_fail:    PUSH  AF
          LD    A,(OVLBUF+39)
          INC   A
          LD    (OVLBUF+39),A
          POP   AF
          RET

; Esperar A tics del CTC (con las interrupciones encendidas)
_wait:    LD    B,A
          EI
          PUSH  BC
          CALL  LD_TICK
          POP   BC
          LD    C,L              ; Tic de partida
_wt1:     PUSH  BC
          CALL  LD_TICK
          POP   BC
          LD    A,L
          SUB   C
          CP    B
          JR    C,_wt1
          RET

; Probar los 16K del banco 1. Z bien; NZ mal con HL = direccion
_rtest:   LD    HL,4000h
_rt1:     LD    C,(HL)
          LD    (HL),55h
          LD    A,(HL)
          CP    55h
          JR    NZ,_rtbad
          LD    (HL),0AAh
          LD    A,(HL)
          CP    0AAh
          JR    NZ,_rtbad
          LD    (HL),C
          INC   HL
          LD    A,H
          CP    80h
          JR    NZ,_rt1
          XOR   A
          RET
_rtbad:   LD    (HL),C
          OR    1
          RET

; Prueba de direcciones de pagina: cada pagina de RAM (hasta 32) guarda su
; numero en su primer byte y despues se comprueba que cada una lee el suyo.
; Z bien; NZ mal con A = pagina que no leyo su numero.
_alias:   LD    A,(MEM_TOT)
          CP    33
          JR    C,_al0
          LD    A,32
_al0:     LD    B,A
          LD    E,0              ; Pagina mala (0 = ninguna)
          DI
          ; Guardar y marcar
          PUSH  BC
          LD    C,RAM_PG_0
          LD    HL,OVLBUF
_al1:     LD    A,C
          OUT   (PG_PORT0+1),A
          LD    A,(4000h)
          LD    (HL),A
          INC   HL
          LD    A,C
          LD    (4000h),A
          INC   C
          DJNZ  _al1
          POP   BC
          ; Comprobar
          PUSH  BC
          LD    C,RAM_PG_0
_al2:     LD    A,C
          OUT   (PG_PORT0+1),A
          LD    A,(4000h)
          CP    C
          JR    Z,_al3
          LD    A,E
          OR    A
          JR    NZ,_al3
          LD    E,C
_al3:     INC   C
          DJNZ  _al2
          POP   BC
          ; Restaurar
          LD    C,RAM_PG_0
          LD    HL,OVLBUF
_al4:     LD    A,C
          OUT   (PG_PORT0+1),A
          LD    A,(HL)
          LD    (4000h),A
          INC   HL
          INC   C
          DJNZ  _al4
          EI
          LD    A,E
          OR    A
          RET

; ---------------------------------------------------------------- textos
_b22:     DEFB  "Z80 CPU Rev 2.2",0
_b23:     DEFB  "ZEPHYRUS Rev 2.3",0
_m_plc:   DEFB  "Board                    ",0
_m_ck22:  DEFB  " (clock from the CTC: P6/P3 on CLK0_OUT)",0
_m_ck23:  DEFB  " (clock from the CTC: DIP switch 8 BAUD ON)",0
_m_bj22:  DEFB  "This speed comes from the CTC: its jumper (P6 channel A, P3 channel B) must be on CLK0_OUT",0
_m_bj23:  DEFB  "This speed comes from the CTC: set DIP switch 8 (BAUD) ON; it changes both channels at once",0
_m_rvok:  DEFB  "Saved. ",0
_m_rvbad: DEFB  "Use: REV 2.2 or REV 2.3",0
_m_rvh:   DEFB  "(REV 2.2 or REV 2.3 changes it; saved in NVRAM)",0
_m_nool:  DEFB  "No OLED display at 3Ch",0
_m_olok:  DEFB  "OLED display updated",0
_m_ver:   DEFB  "ZIOS 2.1.4 v6",0
_m_nortc: DEFB  "no clock",0
_m_sd1:   DEFB  "SD1 ",0
_m_sd2:   DEFB  "  SD2 ",0
_m_si:    DEFB  "yes",0
_m_no:    DEFB  "no",0
_m_ram:   DEFB  "RAM ",0
_m_kb:    DEFB  " KB",0
_m_oli:   DEFB  "OLIVEROS 2026",0
_t_hdr:   DEFB  "Board TEST",13,10,0
_t_ram:   DEFB  "RAM ",0
_t_ok:    DEFB  " OK",0
_t_rbad:  DEFB  " ERROR in page ",0
_t_dir:   DEFB  ", address ",0
_t_alias: DEFB  " ADDRESS ERROR: page does not keep its own data: ",0
_t_bus:   DEFB  "Bus 64h (MISO idle): ",0
_t_bus1:  DEFB  "1, OK",0
_t_bus0:  DEFB  "0, BAD: something pulls MISO low (SD module that does not release it, bent pin or track)",0
_t_sd:    DEFB  "SD",0
_t_sdno:  DEFB  "no card",0
_t_sdsc:  DEFB  "responds (SDSC)",0
_t_sdhc:  DEFB  "responds (SDHC/SDXC)",0
_t_sdnr:  DEFB  "no response (normal if that connector has no adapter)",0
_t_rtc:   DEFB  "RTC DS1307: ",0
_t_nr:    DEFB  "no response on I2C",0
_t_rtcst: DEFB  "stopped (set the time with DT)",0
_t_rtcna: DEFB  "responds but does not advance",0
_t_rtcok: DEFB  "responds and runs",0
_t_ol:    DEFB  "OLED display (3Ch): ",0
_t_gpio:  DEFB  "GPIO 6Ch: one bit every 1/4 s from Q0 to Q5 (watch the LEDs)",0
_t_spk:   DEFB  "Speaker: one beep (with switch 7 BEEP ON)",0
_t_allok: DEFB  "TEST: all OK",0
_t_res:   DEFB  "TEST: ",0
_t_res2:  DEFB  " failure(s)",0
_t_olok:  DEFB  "TEST: all OK",0
_t_olf1:  DEFB  "TEST: ",0
_t_olf2:  DEFB  " FAILURE(S)",0

; Inicializacion del SSD1306 (128x64, direccionamiento horizontal)
_olinit:  DEFB  0AEh,0D5h,80h,0A8h,3Fh,0D3h,00h,40h,8Dh,14h,20h,00h,0A1h,0C8h
          DEFB  0DAh,12h,81h,0CFh,0D9h,0F1h,0DBh,40h,0A4h,0A6h,0AFh
_olinitn  EQU   $-_olinit

import ovlfont.asm
