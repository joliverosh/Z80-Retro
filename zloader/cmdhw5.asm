; **********************************************
; Ordenes para el hardware de la placa que antes no se usaba (v5):
;   BAUD [A|B velocidad]  velocidad de los canales de la SIO (se guarda en la NVRAM)
;   RD [n]                tamano del disco en RAM (paginas de 16 KB; 0 = sin disco)
;   I2C                   dispositivos que responden en el bus I2C
; Y SH_MEM, que DH usa para mostrar la memoria y los discos en memoria.
; **********************************************
import defs.asm
import config.asm
import zapi.asm

import pcb_def.asm
import zlib.asm
import zios.asm
import zload.asm

  extrn  main,E_BADPS
  extrn  LD_SERCFG,LD_I2C,LD_MEMINV,MD_INF,MEM_TOT
  extrn  SIOA_W4,SIOB_W4
  extrn  OVLCALL

  public BAUD,RAMDSK,I2CSCAN,SH_MEM

; Velocidades (con la CPU a 7,3728 MHz; con 14,7456 MHz todo da el doble):
; texto, WR4, constante del CTC (0 = oscilador por CLKU)
W_X16     EQU   01000100b
W_X32     EQU   10000100b
W_X64     EQU   11000100b

; 460800 (x16 sin CTC) no se ofrece: la interrupcion de la SIO no da abasto
_rates:   DEFB  "230400",0,W_X32,0
          DEFB  "115200",0,W_X64,0
          DEFB  "9600",0,W_X16,3
          DEFB  "4800",0,W_X16,6
          DEFB  "2400",0,W_X16,12
          DEFB  "1200",0,W_X16,24
          DEFB  "600",0,W_X16,48
          DEFB  "300",0,W_X16,96
          DEFB  0

; ---------------- BAUD
BAUD:     CALL  WASTESPC
          JR    Z,_bshow
          CALL  BUFCHUP
          SUB   'A'
          CP    2
          JR    NC,E_BADPS
          LD    B,A               ; B = canal
          CALL  WASTESPC
          JR    Z,E_BADPS
          ; Buscar la velocidad en la tabla
          LD    HL,_rates
_bnext:   LD    A,(HL)
          OR    A
          JR    Z,E_BADPS
          PUSH  HL
          LD    DE,(INPTR)
          CALL  _match
          POP   HL
          JR    Z,_bfound
          CALL  _skprate
          JR    _bnext
_bfound:  CALL  _skpstr           ; HL -> WR4, TC
          LD    D,(HL)
          INC   HL
          LD    E,(HL)            ; E = TC (0 = oscilador)
          ; Si usa el CTC, el otro canal no puede usar otra constante (es comun)
          LD    A,E
          OR    A
          JR    Z,_bok
          LD    A,(NVRAM+NV_SIOFL)
          INC   B
          DEC   B
          JR    NZ,_bchkb         ; Canal B: mirar el bit 0 (canal A)
          RRCA                    ; Canal A: mirar el bit 1 (canal B)
_bchkb:   AND   1
          JR    Z,_bok
          LD    A,(NVRAM+NV_CTC0)
          CP    E
          JR    Z,_bok
          LD    HL,_m_ctc
          CALL  PRINT_LN
          JR    main
_bok:     ; Guardar en la NVRAM
          LD    HL,NVRAM+NV_SIOA
          LD    A,B
          OR    A
          JR    Z,_bsv
          LD    HL,NVRAM+NV_SIOB
_bsv:     LD    (HL),D
          LD    A,E
          OR    A
          JR    Z,_bnoc
          LD    (NVRAM+NV_CTC0),A
_bnoc:    ; Bandera "usa el CTC" del canal
          LD    A,1
          INC   B
          DEC   B
          JR    Z,_bfl
          LD    A,2
_bfl:     LD    C,A
          LD    A,(NVRAM+NV_SIOFL)
          OR    C
          INC   E
          DEC   E
          JR    NZ,_bfl2
          XOR   C                 ; Sin CTC: borrar la bandera
_bfl2:    LD    (NVRAM+NV_SIOFL),A
          PUSH  BC
          PUSH  DE
          CALL  NVSAV
          POP   DE
          POP   BC
          ; Aviso y cambio inmediato
          LD    HL,_m_set
          CALL  PRINT
          LD    A,B
          ADD   A,'A'
          RST   08h
          LD    HL,_m_set2
          CALL  PRINT_LN
          INC   E
          DEC   E
          JR    Z,_bnow
          LD    A,6               ; v6: aviso del puente o del DIP segun la placa
          CALL  OVLCALL
_bnow:    ; Esperar a que salga el texto antes de cambiar el reloj
          LD    HL,0
_bwt:     DEC   HL
          LD    A,H
          OR    L
          JR    NZ,_bwt
          LD    A,D               ; WR4 -> codigo 1/2/3 del servicio
          RLCA
          RLCA
          AND   3
          LD    D,A
          CALL  LD_SERCFG
          JR    main

; Mostrar la configuracion de los dos canales
_bshow:   LD    B,0
_bsh1:    LD    HL,_m_sio
          CALL  PRINT
          LD    A,B
          ADD   A,'A'
          RST   08h
          LD    A,':'
          RST   08h
          LD    A,' '
          RST   08h
          ; WR4 guardado (0 = por omision)
          LD    HL,NVRAM+NV_SIOA
          LD    A,B
          OR    A
          JR    Z,_bsh2
          LD    HL,NVRAM+NV_SIOB
_bsh2:    LD    D,(HL)
          LD    A,D
          OR    A
          JR    NZ,_bsh3
          LD    D,W_X64           ; Por omision: x64 (115200); B con la Pi: x32
          LD    A,B
          OR    A
          JR    Z,_bsh3
          LD    A,(NVRAM)
          AND   CF_SIOBPI
          JR    Z,_bsh3
          LD    D,W_X32
_bsh3:    ; Usa el CTC?
          LD    E,0
          LD    A,(NVRAM+NV_SIOFL)
          INC   B
          DEC   B
          JR    Z,_bsh4
          RRCA
_bsh4:    AND   1
          JR    Z,_bsh5
          LD    A,(NVRAM+NV_CTC0)
          OR    A
          JR    NZ,_bsh4b
          LD    A,3
_bsh4b:   LD    E,A
_bsh5:    ; Buscar en la tabla el par (WR4, TC)
          LD    HL,_rates
_bsh6:    LD    A,(HL)
          OR    A
          JR    Z,_bshq
          PUSH  HL
          CALL  _skpstr
          LD    A,(HL)
          CP    D
          JR    NZ,_bsh7
          INC   HL
          LD    A,(HL)
          CP    E
          JR    NZ,_bsh7
          POP   HL
          CALL  PRINT
          JR    _bsh8
_bsh7:    POP   HL
          CALL  _skprate
          JR    _bsh6
_bshq:    LD    A,'?'
          RST   08h
_bsh8:    LD    HL,_m_clku
          INC   E
          DEC   E
          JR    Z,_bsh9
          LD    A,5               ; v6: texto segun la placa (P6/P3 o DIP 8)
          CALL  OVLCALL
          CALL  NL
          JR    _bsh10
_bsh9:    CALL  PRINT_LN
_bsh10:
          INC   B
          LD    A,B
          CP    2
          JR    C,_bsh1
          JR    main

; Coincidencia exacta: texto en DE (entrada) contra HL (tabla). Z si coincide.
_match:   LD    A,(HL)
          OR    A
          JR    Z,_mend
          LD    A,(DE)
          CP    (HL)
          RET   NZ
          INC   HL
          INC   DE
          JR    _match
_mend:    LD    A,(DE)            ; Despues debe venir fin o espacio
          OR    A
          RET   Z
          CP    ' '
          RET

_skpstr:  LD    A,(HL)
          INC   HL
          OR    A
          JR    NZ,_skpstr
          RET
_skprate: CALL  _skpstr
          INC   HL
          INC   HL
          RET

_m_sio:   DEFB  "SIO ",0
_m_clku:  DEFB  " (reloj por CLKU)",0
_m_set:   DEFB  "Guardado. El canal ",0
_m_set2:  DEFB  " cambia ahora (con los interruptores en 11 se arranca con los valores de siempre)",0
_m_ctc:   DEFB  "El otro canal usa el CTC con otra velocidad (el CTC es comun a los dos)",0

; ---------------- RD [n]
RAMDSK:   CALL  WASTESPC
          JR    Z,_rdshow
          CALL  GET_DEC
          JR    C,E_BADPS
          LD    A,H
          OR    A
          JR    NZ,E_BADPS
          LD    A,L
          CP    0FFh
          JR    Z,E_BADPS
          OR    A
          JR    NZ,_rdset
          LD    A,0FFh            ; 0 = sin disco en RAM
_rdset:   LD    (NVRAM+NV_RDSK),A
          CALL  NVSAV
          LD    HL,_m_rdr
          CALL  PRINT_LN
          JR    main
_rdshow:  CALL  _shrd
          JR    main

; Lineas de memoria para DH
SH_MEM:   LD    A,4               ; v6: linea "Placa"
          CALL  OVLCALL
          LD    HL,_m_ram
          CALL  PRINT
          LD    A,(MEM_TOT)
          CALL  _pgkb
          LD    HL,_m_free
          CALL  PRINT
          CALL  LD_MEMINV
          LD    A,B
          CALL  _pgkb
          CALL  NL
          CALL  _shrd
          LD    HL,_m_fd
          CALL  PRINT
          LD    A,3
          CALL  MD_INF
          JR    NZ,_nofd
          CALL  _dskkb
          LD    HL,_m_fd2
          JR    PRINT_LN
_nofd:    LD    HL,_m_no
          JR    PRINT_LN

_shrd:    LD    HL,_m_rd
          CALL  PRINT
          LD    A,2
          CALL  MD_INF
          JR    NZ,_nord
          CALL  _dskkb
          LD    HL,_m_rd2
          JR    PRINT_LN
_nord:    LD    HL,_m_no
          JR    PRINT_LN

; Escribir A paginas como KB
_pgkb:    LD    L,A
          LD    H,0
          ADD   HL,HL
          ADD   HL,HL
          ADD   HL,HL
          ADD   HL,HL
          CALL  WRITE_D
          LD    HL,_m_kb
          JP    PRINT

; DSM (DE) -> KB del disco: (DSM + 1) x 2
_dskkb:   EX    DE,HL
          INC   HL
          ADD   HL,HL
          CALL  WRITE_D
          LD    HL,_m_kb
          JP    PRINT

_m_ram:   DEFB  "RAM: ",0
_m_free:  DEFB  ", libre para programas: ",0
_m_kb:    DEFB  " KB",0
_m_rd:    DEFB  "Disco en RAM: ",0
_m_rd2:   DEFB  " (unidad G)",0
_m_fd:    DEFB  "Disco en flash: ",0
_m_fd2:   DEFB  " (unidad H, solo lectura)",0
_m_no:    DEFB  "no",0
_m_rdr:   DEFB  "Guardado. Se aplica al reiniciar (el disco en RAM se vuelve a formatear).",0

; ---------------- I2C
; Probar las direcciones 08-77 (7 bits) y mostrar las que responden, en el
; formato de 8 bits que usa el servicio 34 (el DS1307 es D0).
I2CSCAN:  LD    HL,_m_i2c
          CALL  PRINT
          LD    C,10h             ; 08 x 2
_i2n:     PUSH  BC
          LD    D,C
          LD    B,2
          LD    HL,0
          CALL  LD_I2C
          POP   BC
          OR    A
          JR    NZ,_i2s
          LD    A,' '
          RST   08h
          LD    A,C
          CALL  WRITE_8
_i2s:     INC   C
          INC   C
          LD    A,C
          CP    0F0h              ; 78 x 2
          JR    C,_i2n
          CALL  NL
          JR    main

_m_i2c:   DEFB  "I2C:",0
