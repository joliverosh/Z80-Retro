; **********************************************
; Implements: 'SM' - logical drive mapping commands
;   sm [drive=disk]
;
; With no parameters display current drive map.
;
; To change a map use the form L=num where
; L is the logical drive letter (A-P) and
; 'num' is the logical drive number (1-1023)
;   OR
; a logical drive and physical disk number
; (0 or 1).
; **********************************************
; Copyright Peter Wilson 2022
; https://github.com/peterw8102/Z80-Retro
; **********************************************
import defs.asm
import config.asm
import zapi.asm

import pcb_def.asm
import zlib.asm
import zios.asm
import zload.asm

  public MAPDSK,SMAP

  extrn  main,E_PRTERR,E_BADPS
  extrn  E_ERROR,E_NOSD


; ------- MAPDSK
; Display current mapped drives
MAPDSK:  LD    HL,SCRATCH
         LD    BC,100h | A_QDSKMP    ; B must be zero
         RST   30h            ; Get the current drive map
         LD    BC,1000h
         LD    A,'A'
         LD    HL,SCRATCH     ; Where the data went
_dmapn:  PUSH  AF
         RST   08h
         LD    A,':'
         RST   08h
         LD    A,' '
         RST   08h

         LD    A,(HL)         ; Device
         INC   HL
         PUSH  AF
         LD    E,(HL)
         INC   HL
         LD    D,(HL)
         INC   HL
         EX    DE,HL
         CALL  WRITE_D
         EX    DE,HL
         POP   AF
         CALL  _wrdev         ; Write SDCard name (from A)
         CALL  NL
         POP   AF
         INC   A

         DJNZ  _dmapn

         JR    main


_wrdev:  PUSH   HL
         PUSH   AF
         LD     A,'/'
         RST    08h
         POP    AF
         LD     HL,_RAMD          ; Tarjeta 2: disco en RAM
         CP     2
         JR     Z,_wrmd
         LD     HL,_FSHD          ; Tarjeta 3: disco en flash
         CP     3
         JR     Z,_wrmd
         PUSH   AF
         LD     HL,_SDEV
         CALL   PRINT
         POP    AF
         ADD    A,'0'
         RST    08h
         POP    HL
         RET
_wrmd:   CALL   PRINT
         POP    HL
         RET


; ----- SMAP
; Map one of the logical disks hosted on an SDCard to one of the vitual
; disk drives (A thru P)
; SM L=PPPP[:d] - Map Physical drive (decimal 1-1023) to logical drive
; letter L. If ':d' is specified then use physical SDCard 'd' (0 or 1)
SMAP:     JR     Z,MAPDSK
          CALL   BUFCHUP
          CP     'A'
          JR     C,_baddrv
          CP     'A'+16
          JR     C,_gotdrv

          ; Report bad drive letter
_baddrv:  LD     HL,_NODRIVE
          JR     E_PRTERR


_gotdrv:  ; Need a literal '=' next
          PUSH   AF          ; Push DRIVE letter
          CALL   SKIPSPC
          CP     '='
          JR     NZ,E_BADPS

          ; Disco en memoria: SM G=RAM o SM H=FLASH
          CALL   WASTESPC
          LD     DE,_RAMD
          LD     B,2
          CALL   _smword
          JR     Z,_smmd
          LD     DE,_FSHD
          LD     B,3
          CALL   _smword
          JR     Z,_smmd
          ; Want a physical drive (0-1023 decimal)
          CALL   GET_DEC
          JR     C,E_ERROR
          JR     Z,E_ERROR

          ; Number from 1-1023 (Don't allow 0 as a target)
          LD     A,$FC
          AND    H
          JR     NZ,E_NOSD
          LD     A,H
          OR     L
          JR     Z,E_NOSD

          ; Optional SDCard
          CALL   BUFCHR
          CP     ':'
          LD     A,'0'
          JR     NZ,_gotsd

          ; Must be a '0' or '1'
          CALL   BUFCHR
          JR     Z,E_ERROR
          CP     '0'
          JR     Z,_gotsd
_not1:    CP     '1'
          JR     NZ,E_ERROR


          ; A has the SDCard (ASCII) number, which needs to be in E for the API call
_gotsd:   LD     E,A        ; SDCard (into E) as a letter '0' or '1'
          POP    AF         ; Drive letter...
          PUSH   AF
          PUSH   HL         ; disk number
          PUSH   AF
          PUSH   HL         ; disk number
          LD     HL,_MAPD
          CALL   PRINT
          POP    HL
          CALL   WRITE_D
          LD     A,'/'
          RST    08h
          LD     HL,_SDEV    ; 'sd'
          CALL   PRINT
          LD     A,E         ; SDCard
          RST    08H
          LD     A,E
          SUB    '0'
          LD     E,A
          LD     HL,_MAPD_TO
          CALL   PRINT
          POP    AF         ; drive
          RST    08H
          CALL   NL
          POP    HL
          POP    AF         ; drive

          ; Tell the API the mapping we want.
          SUB    'A'
          LD     D,A             ; Drive slot
          LD     B,0             ; Standard mapping
          LD     C,A_DSKMP       ; Map drive

          ; D:  Drive slot (0-15)
          ; E:  Physical SDCard (0 or 1)
          ; HL: Virtual disk on the SDCard
          RST    30h

          JR     main


_SDEV        DEFB "sd",NULL
_RAMD        DEFB "RAM",NULL
_FSHD        DEFB "FLASH",NULL

; Z si la entrada (desde INPTR) es exactamente la palabra de DE (sin importar
; mayusculas) seguida de fin o espacio. Conserva B.
_smword:  LD     HL,(INPTR)
_smw1:    LD     A,(DE)
          OR     A
          JR     Z,_smw2
          LD     A,(HL)
          CALL   TOUPPER
          EX     DE,HL
          CP     (HL)
          EX     DE,HL
          RET    NZ
          INC    HL
          INC    DE
          JR     _smw1
_smw2:    LD     A,(HL)
          OR     A
          RET    Z
          CP     ' '
          RET

; SM x=RAM / x=FLASH: B = tarjeta 2 o 3 (disco virtual 0)
_smmd:    LD     E,B
          POP    AF              ; Letra de la unidad
          SUB    'A'
          LD     D,A
          LD     HL,0
          LD     B,0
          LD     C,A_DSKMP
          RST    30h
          JR     MAPDSK
_NODRIVE     DEFB "Drive A-", 'A'+15, NULL
_MAPD        DEFB "Map disk: ",NULL
_MAPD_TO     DEFB " to drive ", NULL
