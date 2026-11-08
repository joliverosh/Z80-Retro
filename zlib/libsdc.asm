import ../zlib/defs.asm

; Functions for reading and writing to/from an SDCard. Currently only cards up
; to 2GB are supported. The SDCards is connected/accessed via the SPI interface.
;
; Note that this library only currently supports the first SDCard. Version 2 of
; the board added hardware support for a second SDCard however this is not yet
; supported in this library.
;
; Exported Functions
; SD_INIT: Initialise the SPI bus and the SDCard. MUST be called before read/write ops
; SD_WBLK:
; SD_RBLK:
;
; SDCard access is not trivial. The following references have been particularly useful
; in reverse engineering the SDCard command interface:
;
;    http://elm-chan.org/docs/mmc/mmc_e.html
;    https://www.microchip.com/forums/m530149.aspx



          extrn  SPI_BEG, SPI_END, SPI_INIT, SPI_ACMD, SPI_TXB, SPI_SEL
          extrn  SPI_RXB, SPI_RBF, SPI_CM1, SPI_CMN, SPI_BRD, SPI_BWR

          ; For debug
          ; extrn  WRITE_8, WRITE_16

          ; Operational exports
          public SD_SEL, SD_INIT, SD_RST, SD_WBLK, SD_RBLK, SD_PRES

          ; Debug symbols
          public _RSET, _SCND, _OCR, _AINIT, _SBLK, _CMDBUF
          CSEG

; ------ SD_RST
; Force SDCard re-initialisation. This would be required if the
; SDCard in one of the carriers in replaced (or card removed then
; re-inserted). Without calling SD_RST the card won't be reset and
; placed into the correct operational mode.
SD_RST:  XOR     A
         LD      (SD_STAT+1),A   ; Card 0 initialisation status
         LD      (SD_STAT+4),A   ; Card 1 initialisation status
         RET

; ------ SD_PRES
; The function takes no parameters and returns a two bit result
; in the accumulator (A):
;    Bit 0: Card 0 presense
;    Bit 1: Card 1 presense
; The value of each bit will be either:
;     0: There is an adaptor fitted but there's no card inserted
;     1: Either there's no adaptor OR there is an adaptor and there
;        is a card inserted into the adaptor.
; NOTE:
; The hardware can't distinguish between card present and adaptor
; missing due to the way the adaptor hardware works. As such it's
; recommended that slot 0 at least have an SDCard adaptor even if
; not used.
SD_PRES:  IN         A,(SPIIN)
          AND        SDC0_PR | SDC1_PR
          RRCA
          RRCA
          RRCA
          AND        3
          RET


; ------ SD_TST
; Test whether the currently selected SDCard is installed.
; This function returns the SPI device number for the selected
; SDCard. Card 0 returns 0, card 1 returns 1.
;
; Return:
;     Z flag SET if the card is NOT installed.
;    HL points to SD_STAT block.
;     A is the SPI device ID for the selected SDCard
SD_TST:   OR        A             ; Which drive?
          IN        A,(SPIIN)
          LD        HL,SD_STAT+2
          JR        NZ,_sd1
          JR        _tst1

_sd1:     LD        HL,SD_STAT+5
_tst1:    AND       (HL)          ; Device number
          DEC       HL
          DEC       HL
          LD        A,(HL)
          RET                     ; Do nothing if there's no card

; ------ SD_SEL
; Select one of the SDCards (0 or 1)
; A: the device number. Anything other than 0 or 1 will cause no device to
; be selected.
SD_SEL:   PUSH       BC
          PUSH       HL
          LD         B,A
          LD         A,$FE
          AND        B           ; Should be zero
          JR         NZ,_baddev
          ; Check whether that drive contains a card
          LD         A,B
          CALL       SD_TST
          ; Se registra la tarjeta pedida aunque no este presente. Antes se
          ; salia sin cambiar nada y las operaciones siguientes caian sobre la
          ; tarjeta seleccionada anteriormente (una escritura a la tarjeta 1
          ; ausente acababa en la tarjeta 0).
          PUSH       AF          ; Z = no hay tarjeta
          LD         A,B
          LD         (CUR_DEV),A
          LD         (CUR_SD),HL
          POP        AF
          LD         A,B
          JR         NZ,_sdsel
_baddev:  LD         A,5         ; Sin tarjeta o numero invalido: ningun CS activo
_sdsel:   CALL       SPI_SEL
          POP        HL
          POP        BC
          RET


; ------ SD_INIT
; Initialise the currently selected SDCard (set via SD_SEL)
;
; Initialises the SPI interface and then sets the correct operational
; mode for the SDCard.
;
; This function MUST be called before the read/write block operations. This
; function can be called multiple times and should be called before all
; read/write operations.
;
; The SDCard is set to have a block size of 512 bytes.
;
SD_INIT:  PUSH      HL
          PUSH      DE
          PUSH      BC
          LD        A,(CUR_DEV)     ; Currently installed device
          CALL      SD_TST
          JR        NZ,_havdev      ; If zero then card not installed.

          ; There's no device. HL points to the device control block. Clear the init flag
          ; so that next time, if the card has been inserted, it will be properly initialised.
          XOR       A
          INC       HL
          LD        (HL),A
          JR        _fin

_havdev:  CALL      SPI_SEL         ; SD_TST returns the SPI device number. Select it.

          ; Does this card need to be initialised?
          INC       HL
          LD        A,(HL)
          OR        A
          JR        Z,_doinit       ; Card needs initialisation.
          CALL      SPI_END
          JR        _fin

_doinit:  PUSH      HL              ; HL -> indicador de inicializacion de esta tarjeta
          CALL      SPI_INIT        ; Initialise the SPI interface
          CALL      SPI_END

          ; SD Card initialisation sequence. Cada paso tiene limite de reintentos:
          ; antes, una tarjeta que no respondia (o un zocalo sin adaptador, que
          ; se lee como "tarjeta presente") colgaba la maquina en un bucle infinito.
          CALL      _RSET
          JR        NZ,_ifail       ; La tarjeta no entro en estado de reposo
          CALL      _SCND           ; CMD8: decide si la tarjeta es v2 (SDHC posible)
          CALL      _OCR
          CALL      _AINIT
          OR        A
          JR        Z,_ifail        ; ACMD41 no termino (tiempo agotado o error)
          CALL      _OCR            ; OCR final: bit CCS = direccionamiento por bloque

          ; Set block size to 512 bytes
          CALL      _SBLK

          ; Indicador: 1 = tarjeta SDSC (direccion en bytes), 2 = SDHC/SDXC (en bloques)
          LD        A,(_CMDBUF+1)   ; Primer byte del OCR (bits 31-24)
          AND       40h             ; CCS
          LD        A,1
          JR        Z,_isdsc
          INC       A
_isdsc:   POP       HL
          LD        (HL),A
          OR        A               ; NZ: inicializada (como en el original)
          JR        _fin

_ifail:   POP       HL
          XOR       A               ; Queda sin inicializar: se reintenta en la proxima llamada
          LD        (HL),A
_fin:     POP       BC
          POP       DE
          POP       HL
          RET

; _RSET: Send a card reset command (CMD0) hasta que la tarjeta responda 01
; (reposo). Devuelve Z si lo logro, NZ si se agotaron los 32 intentos.
_RSET:    LD         A,32
_rset1:   PUSH       AF
          LD         BC,9540h    ; CMD0, CRC 95
          CALL       SPI_CMN
          PUSH       AF
          CALL       SPI_END
          POP        AF
          JR         C,_rsetto   ; MISO pegado en bajo: no tiene sentido reintentar
          DEC        A
          JR         Z,_rsetok
          POP        AF
          DEC        A
          JR         NZ,_rset1   ; Start again
          INC        A           ; NZ: fallo
          RET
_rsetto:  POP        AF
          OR         1           ; NZ: fallo
          RET
_rsetok:  POP        AF
          XOR        A           ; Z: correcto
          RET

; ----------- SEND_IF_COND --------
; CMD 08
; Response is stored in the _CMDBUF structure. Si la tarjeta responde con el
; patron (R1 = 01 y eco AA) es una tarjeta v2 y ACMD41 se envia con HCS = 1.
_SCND:    LD         BC,8740h + 8
          LD         HL,0
          LD         DE,01AAh
          CALL       SPI_CM1

          LD         DE,_CMDBUF
          LD         (DE),A
          INC        DE

          ; A contains the first R1 response byte
          ; Next 4 bytes are the status. Read 4 bytes (2 words)
          LD         B,2
          CALL       SPI_BRD
          CALL       SPI_END

          LD         HL,0           ; v1 (o sin respuesta): HCS = 0
          LD         A,(_CMDBUF)
          CP         1
          JR         NZ,_scnd1
          LD         A,(_CMDBUF+4)
          CP         0AAh
          JR         NZ,_scnd1
          LD         H,40h          ; v2: HCS = 1 (bit 30 del argumento)
_scnd1:   LD         (_HCS),HL
          LD         HL,_CMDBUF
          RET

; ----------- CMD58 --------
_OCR:     LD         BC,0FF40h+58
          CALL       SPI_CMN

          LD         DE,_CMDBUF
          LD         (DE),A
          INC        DE

          ; And the next 4 response bytes
          LD         B,2
          CALL       SPI_BRD
          CALL       SPI_END

          LD         HL,_CMDBUF
          RET

; ----------- ACMD41 --------
; Repite CMD55 + ACMD41 hasta que la tarjeta sale del reposo. Antes se enviaba
; siempre con argumento 0 (HCS = 0): una tarjeta SDHC (mas de 2 GB) no sale
; nunca del reposo en ese caso y el bucle no tenia limite. Ahora se envia HCS
; segun CMD8 y se abandona tras 255 intentos (~2 s a 7,37 MHz).
; Devuelve A = 1 si la tarjeta quedo lista, A = 0 si no.
_AINIT:   LD         A,255
_ain1:    LD         (_ATRY),A
          CALL       SPI_ACMD       ; Prefix command

          ; If we didn't get success at this point then wait and retry
          LD         A,0FEh
          AND        B              ; Result from the ACMD command
          LD         A,0
          RET        NZ

          LD         BC,0ff40h+41
          LD         HL,(_HCS)
          LD         DE,0
          CALL       SPI_CM1

          ; Wait for zero byte
          OR         A
          CALL       SPI_END
          LD         A,1
          RET        Z
          CALL       _PAUSE
          LD         A,(_ATRY)
          DEC        A
          JR         NZ,_ain1
          RET                       ; A = 0: tiempo agotado

; ----------- SET BLOCK SIZE --------
; CMD 16 - Set 512 BYTE BLOCK SIZE
_SBLK:    LD         BC,0FF40h+16
          LD         HL,0
          LD         DE,512      ; block size of 512 bytes
          CALL       SPI_CM1
          LD         D,A
          CALL       SPI_END
          RET

_PAUSE:  PUSH  HL
         LD    HL,0FFFh
         JR    del_2
         PUSH  HL
         LD    H,001H
del_1:   LD    L,0FFH
del_2:   DEC   L
         JR    NZ,del_2
         DEC   H
         JR    NZ,del_1
         POP   HL
         RET


; ----------- WRITE BLOCK -----------
; SDCard address is a 512byte sector number which needs to be scaled up to
; a byte address. Eventually the scaling will depend on the SDCard formats
; supported. Right now we only support the original cards which have a
; byte addressing scheme.
;
; ALL WRITES ARE 512 BYTES!!!
;
; HL  - SD address upper word...
; DE  - SD address lower word...
; BC  - Points to the buffer containing the data to write.
;
; NOTE: The correct drive must have been selected in SD_INIT BEFORE attempting
; to read or write from a drive.
SD_WBLK:  CALL       SD_INIT        ; Las escrituras no inicializaban la tarjeta: si lo
                                    ; primero que se hacia era escribir (por ejemplo WI
                                    ; o SW justo despues de encender) la tarjeta seguia
                                    ; en reposo, rechazaba el comando y el error se
                                    ; perdia. SD_INIT conserva BC, DE y HL y, si la
                                    ; tarjeta ya esta inicializada, no hace nada.
          CALL       _PRSNT         ; Sin tarjeta seleccionada: no hacer nada
          JR         NZ,_wrgo
          DEC        A              ; A = FF, NZ
          RET
_wrgo:    CALL       SCL_AD
          PUSH       BC             ; Save buffer address
          ; Send command...
          LD         BC,0FF40h + 24
          CALL       SPI_CM1

          OR         A
          LD         H,A            ; R1 como codigo de error si se aborta
          JR         NZ,_abrt_wr

          ; Wait for ready (read FF byte from SD card). Antes sin limite.
          LD         DE,8000
_a:       CALL       SPI_RXB
          INC        A
          JR         Z,_wrrdy
          DEC        DE
          LD         A,D
          OR         E
          JR         NZ,_a
          DEC        A              ; A = FF: tiempo agotado
          LD         H,A
          JR         _abrt_wr
_wrrdy:
          ; Send the start token
          LD         A,0FEh
          CALL       SPI_TXB

          ; Write out the block...
          LD         B,00h          ; 256x2 bytes
          POP        HL             ; Get the block address back but into HL where we can use it.
          CALL       SPI_BWR

          ; 2 byte CRC (NOT USED)
          CALL       SPI_RXB
          CALL       SPI_RXB

          ; Next inbound byte is the response code
          CALL       SPI_RXB
          AND        1Fh
          CP         5
          LD         H,A
          ; End of command
_ec:      CALL       SPI_END
          LD         A,H
          ; Returning Z flag set if we got the expected result.
          CP         5
          RET

_abrt_wr: POP        BC
          CALL       SPI_END
          LD         A,H
          OR         A              ; NZ: error (A = R1 o FF)
          RET

; ----------- READ BLOCK -----------
; SDCard address is a 512byte sector number which needs to be scaled up to
; a byte address. Eventually the scaling will depend on the SDCard formats
; supported. Right now we only support the original cards which have a
; byte addressing scheme.
; HL  - SD address upper word...
; DE  - SD address lower word...
; BC  - Target buffer
SD_RBLK:  CALL       _PRSNT             ; Presencia de LA TARJETA SELECCIONADA
          JR         NZ,_rdgo           ; (antes se miraba siempre la tarjeta 0)
          DEC        A                  ; Sin tarjeta: A = FF, NZ
          RET
_rdgo:
          CALL       SCL_AD
          PUSH       BC                 ; Address of buffer to receive data
          LD         BC,0FF40h + 17     ; Command code
          CALL       SPI_CM1
          OR         A                  ; R1 distinto de 0: la tarjeta rechazo el comando.
          JR         NZ,_rderr          ; Antes se esperaba el token para siempre.

          ; Esperar el token de datos FE. Mientras la tarjeta prepara el bloque
          ; envia FF; un byte 0000xxxx es un token de error. Limite ~0,4 s.
          LD         DE,8000
_tok1:    CALL       SPI_RBF           ; Don't care about HL
          CP         0FEh
          JR         Z,_gtok
          CP         0FFh
          JR         NZ,_rderr          ; Token de error (se devuelve tal cual)
          DEC        DE
          LD         A,D
          OR         E
          JR         NZ,_tok1
          DEC        A                  ; A = FF: tiempo agotado

_rderr:   POP        DE                 ; Descartar la direccion del buffer
          LD         H,A
          CALL       SPI_END
          LD         A,H
          OR         A                  ; NZ y A = codigo de error
          RET

_gtok:    POP        DE                ; Where to write the data

          ; Block read 512byte block
_nrb:     LD         B,0               ; Number of 16 bit words to read. Read 256x2 bytes
          CALL       SPI_BRD
          CALL       SPI_RBF           ; CRC (2 bytes, no se usa): leerlo deja la
          CALL       SPI_RBF           ; tarjeta lista para el siguiente comando

          CALL       SPI_END
          XOR        A                 ; Z y A = 0: correcto
          RET

; _PRSNT: Z si la tarjeta seleccionada (CUR_SD) no esta presente.
; Conserva BC, DE y HL.
_PRSNT:   PUSH       HL
          LD         HL,(CUR_SD)
          INC        HL
          INC        HL
          IN         A,(SPIIN)
          AND        (HL)
          POP        HL
          RET

; -------------- SCALE BLOCK ADDRESS ------------
; This library currently only supports the original byte addressed SDCards with a maximum
; size of 4GB. The address accepted by the API is a 512 byte sector address so need to
; left shift 9 bits.
SCL_AD:  PUSH  HL      ; Tarjeta SDHC/SDXC (indicador 2): el comando lleva el
         LD    HL,(CUR_SD) ; numero de bloque tal cual, sin escalar.
         INC   HL
         LD    A,(HL)
         POP   HL
         CP    2
         RET   Z
         LD    H,L     ; Multiple by 256
         LD    L,D
         LD    D,E
         LD    E,0

         SLA   D       ; And then by 2 to get to 512 block address
         RL    L
         RL    H
         RET

          DSEG

; Maintain two SDCard status blocks. Bytes in ech block are:
;    0: the SPI device ID (0 or 1)
;    1: 0 = sin inicializar, 1 = SDSC (direcciones en bytes), 2 = SDHC/SDXC (en bloques)
;    2: The presense bit for this device
CUR_SD   DW    SD_STAT   ; Points to current SD_STAT block (tarjeta 0 por defecto)
CUR_DEV  DB    0         ; Current SDCard (default to card zero)
SD_STAT  DB    0         ; SDCard 1 SPI device ID
         DB    0         ; Set to !0 once initialised
         DB    SDC0_PR   ; Bit mask for this card's presense
         DB    1         ; SDCard 2 SPI device ID
         DB    0         ; Set to !0 once initialised
         DB    SDC1_PR   ; Bit mask for this card's presense

; _CMDBUF - small buffer for short command responses that can be returned to the caller.
_CMDBUF:   DEFS     10      ; For short response data
_HCS:      DW       0       ; Palabra alta del argumento de ACMD41 (4000h = HCS)
_ATRY:     DB       0       ; Intentos restantes de ACMD41

.END
