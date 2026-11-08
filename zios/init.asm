import defs.asm
import config.asm
import zlib.asm
import pcb_def.asm

  extrn   P_MIN,PR_INIT
  extrn   AP_DISP
  extrn   NUL_ISR
  extrn   VDU_INI,VDU_OFF
  extrn   CNS_INI
  extrn   MEM_PRB,TMR_INI,TMR_OFF,MD_INI
  public  _ETICK,TICKS
  extrn   SPCISA,SPCISB
  public  ZIOS_INI,ZIOS_OFF

; init.asm
; System initialisation code. ZIOS must be initialised after the loader
; has copied the code into executable RAM.

            extrn  SDPREP,RTC_INI,NVLD,INITSIO,SERINT,NVRAM
            public ISRCTXT

            CSEG

; ---------- ZIOS_INI
; Flash has been copied to RAM and before using any ZIOS services this function
; must be called. There are no parameters however the function will return
; the status of the hardware configuration switches. The lower bits of this
; will tell the loader what automatic/boot behaviour to take.
; OUTPUT: A   - the hardware status register (bits 0-2)
ZIOS_INI::  LD    A,MN2_PG+1
            CALL  P_MIN        ; Reserve ZLoader memory pages
            CALL  PR_INIT      ; Initialise process control block

            ; Initialise drive map. Map logical drives 0-15 to physical blocks 1-16. Need to store
            ; the physical address << 6 (Upper 10 bits of the 32 bit SD card address).
            CALL   SDPREP

            ; Initialise i2c
            CALL   RTC_INI

            ; and read the NV RAM (returns address of NVRAM)
            CALL   NVLD

            ; Copy execution flag default to the PCB
            LD     A,(HL)
            AND    CFG_VAL
            LD     (P_FLAGS),A

            ; Modo de reloj de la SIO guardado en la NVRAM (0 = por omision). Con
            ; los interruptores de arranque en 11 (antes sin uso) se ignora: es la
            ; forma de recuperar la consola si se eligio una velocidad que no
            ; corresponde a los puentes.
            CALL   SW_CFG
            AND    3
            CP     3
            LD     A,0
            JR     Z,_safe
            LD     A,(NVRAM+NV_SIOA)
_safe:      LD     (SIOA_W4),A
            JR     Z,_safe2
            LD     A,(NVRAM+NV_SIOB)
_safe2:     LD     (SIOB_W4),A

            ; RAM de expansion en el bus (paginas 40-FF)
            DI
            CALL   MEM_PRB
            CALL   MD_INI          ; Discos en RAM y en flash (unidades G y H)

            ; Initialise the interrupt vector table. Table will be right at the end of the
            ; memory map which will be in our second RAM page and will be copied for
            ; application context.
            LD     A,VEC_BASE
            LD     I,A

            LD    HL,0xC000+ISR_BASE
            LD    DE,NUL_ISR
            LD    B,12           ; SIO (8) + CTC (4) vectors; FFF8-FFFF holds RAWGO
_nxtisr:    LD    (HL),E
            INC   HL
            LD    (HL),D
            INC   HL
            DJNZ  _nxtisr

            ; Add entry to vector table for supervisor SIO ISR
            LD     HL,_EISR
            LD     (0xC000+SIO_ARX),HL
            LD     HL,_EISRB             ; Canal B (si esta en modo serie)
            LD     (0xC000+SIO_BRX),HL
            LD     HL,SPCISA           ; Condiciones especiales de recepcion
            LD     (0xC000+SIO_ASP),HL
            LD     HL,SPCISB
            LD     (0xC000+SIO_BSP),HL
            LD     HL,_ETICK             ; Tic del CTC (canal 1 desde la v6)
            LD     (0xC000+CTC_ICH1),HL

            ; Initialise the serial IO module. A = 1 si el canal B es para la Pi.
            ; Tambien con los interruptores en 01 (arranque desde la Raspberry Pi).
            LD     A,(NVRAM)
            AND    CF_SIOBPI
            JR     NZ,_sbpi
            CALL   SW_CFG
            AND    3
            CP     1
            LD     A,0
            JR     NZ,_sbser
_sbpi:      LD     A,1
_sbser:     CALL   INITSIO
            IM     2              ; Using interrupt mode 1 AT THE MOMENT. Need to move to vectored at some point
            EI

            ; Tic del sistema y reloj del CTC para la SIO
            CALL   TMR_INI

            ; Install RST 30h for API access.
            LD     A,$C3
            LD     (30h),A
            LD     HL,AP_DISP
            LD     (31h),HL

            ; And initialise the console dispatcher.
            LD     A,(P_FLAGS)
            AND    CF_IGNVDU
            CALL   CNS_INI

            ; If the keyboard and video card are available then set up CTC for
            ; keyboard scanning and make a virtual console available.
            CALL   VDU_INI

            ; Return the status of the hardware configuration switch
            CALL   SW_CFG

            RET

; ------ ZIOS_OFF
; Called to disable all active hardware used by ZIOS. Call this (eg from ZLoader) before starting
; execution of code that doesn't use the ZIOS services.
ZIOS_OFF:   CALL   VDU_OFF
            CALL   TMR_OFF

            ; Disable SIO interrupts for channel 0
            CALL   SIO_OFF
            RET

; ---- _EISR
; Serial port rx ISR
_EISR:      CALL    SERINT
            EI
            RETI

; Recepcion del canal B (modo serie general)
_EISRB:     CALL    SERINTB
            EI
            RETI

; Tic del CTC (canal 2) en el contexto de ZIOS/ZLoader
_ETICK:     PUSH    AF              ; INC cambia las banderas: hay que guardarlas
            PUSH    HL
            LD      HL,TICKS
            INC     (HL)
            JR      NZ,_etk
            INC     HL
            INC     (HL)
            JR      NZ,_etk
            INC     HL
            INC     (HL)
            JR      NZ,_etk
            INC     HL
            INC     (HL)
_etk:       POP     HL
            POP     AF
            EI
            RETI


            DSEG
ISRCTXT     DEFB    0
TICKS       DEFB    0,0,0,0     ; Tics del CTC desde el arranque
