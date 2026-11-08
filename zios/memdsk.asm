import ../zlib/defs.asm
import config.asm
import pcb_def.asm

; memdsk.asm
; Discos en memoria, vistos como unidades logicas de ZIOS:
;   - Disco en RAM (tarjeta 2 en el mapa de unidades): paginas de RAM libres,
;     las mas altas. Se conserva al pulsar reset (no al apagar). Por omision
;     12 paginas (192 KB); el byte NV_RDSK de la NVRAM cambia el tamano
;     (FFh = sin disco en RAM).
;   - Disco en flash (tarjeta 3): solo lectura, en las paginas de flash 03-1F
;     (hasta 464 KB). Se graba con el programador junto con ZLoader. Lleva una
;     cabecera en la pagina de flash 02, desplazamiento 3FF0.
; Formato CP/M de los dos: bloques de 2 KB, 128 entradas de directorio (2
; bloques), sin pistas reservadas. Se enlaza con ZLoader (banco 0).
;
; Las transferencias son de registros de 128 bytes (servicios 17/18, el camino
; de CP/M) o de sectores de 512 (servicios 13/15). Se copian por un buffer
; intermedio: la pagina del disco va al banco 1 y despues el buffer de la
; aplicacion (DMA) a los bancos 1 y 2.

          public MD_INI,MD_INF,MD_REC,MD_SEC

          extrn  P_RES,P_FREEN,_pages
          extrn  NVRAM

MD_RAM    EQU    2          ; Tarjeta "2" en el mapa de unidades
MD_FSH    EQU    3          ; Tarjeta "3"
RD_DEF    EQU    12         ; Paginas por omision del disco en RAM
RD_FREE   EQU    8          ; Paginas que siempre quedan para las aplicaciones
FD_PG0    EQU    3          ; Primera pagina de flash del disco
FD_MAX    EQU    29         ; Paginas 03-1F
HDR_A     EQU    7FF0h      ; Cabecera: desplazamiento 3FF0 de la pagina en el banco 1
DRV_RAM   EQU    6          ; Unidad G
DRV_FSH   EQU    7          ; Unidad H

          CSEG

; ---------- MD_INI
; Se llama al arrancar ZIOS (despues de detectar la RAM). Reserva las paginas
; del disco en RAM, le da formato si no lo tenia, busca el disco en flash y
; los pone en las unidades G y H.
MD_INI:   ; ---- Disco en flash: cabecera en la pagina 02
          LD     A,2
          OUT    (PG_PORT0+1),A
          LD     HL,HDR_A
          LD     DE,_fsig
          LD     B,8
          CALL   _cmp
          LD     A,0
          JR     NZ,_nofd
          LD     A,(HDR_A+8)       ; Numero de paginas del disco
          CP     FD_MAX+1
          JR     C,_fdok
          LD     A,FD_MAX
_fdok:    LD     (FD_PGS),A
          OR     A
          JR     Z,_nofd
          LD     HL,DRVMAP+DRV_FSH*3
          LD     (HL),MD_FSH
          INC    HL
          LD     (HL),0
          INC    HL
          LD     (HL),0
_nofd:
          ; ---- Disco en RAM
          LD     A,(NVRAM+NV_RDSK)
          CP     0FFh
          JR     Z,_rdx            ; Desactivado
          OR     A
          JR     NZ,_rdn
          LD     A,RD_DEF
_rdn:     LD     B,A               ; Pedidas
          CALL   P_FREEN
          SUB    RD_FREE
          JR     C,_rdx
          JR     Z,_rdx
          CP     B
          JR     NC,_rdn2
          LD     B,A               ; No hay tantas: las que se puedan
_rdn2:    LD     A,B
          CP     2                 ; Al menos 2 paginas (directorio + datos)
          JR     C,_rdx
          ; Reservar las paginas libres mas altas, de arriba hacia abajo
          LD     HL,RD_TAB
          LD     C,0FFh            ; Pagina candidata
          LD     E,0               ; Cuantas van
_rdsc:    LD     A,C
          CALL   _isfree
          JR     NZ,_rdnx
          LD     A,C
          CALL   P_RES
          LD     (HL),C
          INC    HL
          INC    E
          LD     A,E
          CP     B
          JR     Z,_rdgot
_rdnx:    DEC    C
          LD     A,C
          CP     RAM_PG_0
          JR     NC,_rdsc
_rdgot:   LD     A,E
          CP     2
          JR     C,_rdx            ; No alcanzo (quedan reservadas, sin uso)
          LD     (RD_PGS),A
          ; Firma al final de la ultima pagina: si no esta (o cambio el
          ; tamano), dar formato al directorio
          LD     HL,RD_TAB-1
          CALL   _add
          LD     A,(HL)            ; Ultima pagina
          OUT    (PG_PORT0+1),A
          LD     HL,HDR_A
          LD     DE,_rsig
          LD     B,8
          CALL   _cmp
          JR     NZ,_rdfmt
          LD     A,(HDR_A+8)
          LD     HL,RD_PGS
          CP     (HL)
          JR     NZ,_rdfmt
          LD     A,(HDR_A+9)
          LD     HL,RD_TAB
          CP     (HL)
          JR     Z,_rdmap
_rdfmt:   ; Firma en la ultima pagina (ya esta en el banco 1)
          LD     HL,_rsig
          LD     DE,HDR_A
          LD     BC,8
          LDIR
          LD     A,(RD_PGS)
          LD     (DE),A
          INC    DE
          LD     A,(RD_TAB)
          LD     (DE),A
          ; Directorio vacio: 4 KB de E5 al principio de la primera pagina
          LD     A,(RD_TAB)
          OUT    (PG_PORT0+1),A
          LD     HL,4000h
          LD     DE,4001h
          LD     (HL),0E5h
          LD     BC,4095
          LDIR
_rdmap:   LD     HL,DRVMAP+DRV_RAM*3
          LD     (HL),MD_RAM
          INC    HL
          LD     (HL),0
          INC    HL
          LD     (HL),0
_rdx:     LD     A,(PAGE_MP+1)     ; Banco 1 como lo tiene la aplicacion
          OUT    (PG_PORT0+1),A
          RET

; Z si la pagina A esta libre en el mapa de paginas
_isfree:  PUSH   HL
          PUSH   BC
          SUB    RAM_PG_0
          LD     C,A
          RRCA
          RRCA
          RRCA
          AND    1Fh
          LD     HL,_pages
          CALL   _add
          LD     A,C
          AND    7
          LD     B,A
          LD     A,(HL)
          INC    B
_isf1:    DEC    B
          JR     Z,_isf2
          RRCA
          JR     _isf1
_isf2:    AND    1
          POP    BC
          POP    HL
          RET

; HL = HL + A
_add:     ADD    A,L
          LD     L,A
          RET    NC
          INC    H
          RET

; Comparar B bytes de (HL) con (DE). Z si iguales.
_cmp:     LD     A,(DE)
          CP     (HL)
          RET    NZ
          INC    HL
          INC    DE
          DJNZ   _cmp
          RET

_fsig:    DEFB   "FLSHDSK1"
_rsig:    DEFB   "RAMDSK01"

; ---------- MD_INF
; Informacion de un disco en memoria (para que la BIOS arme su DPB).
; INPUT:  A - tarjeta del mapa de unidades (2 = RAM, 3 = flash)
; OUTPUT: A - 0 si existe (Z), FFh si no; DE = DSM (bloques de 2 KB - 1);
;         B = 1 si es de solo lectura
MD_INF:   CP     MD_RAM
          JR     NZ,_inff
          LD     A,(RD_PGS)
          OR     A
          JR     Z,_infno
          LD     L,A               ; DSM = paginas x 8 - 2 (el ultimo bloque
          LD     H,0               ; tiene la firma)
          ADD    HL,HL
          ADD    HL,HL
          ADD    HL,HL
          DEC    HL
          DEC    HL
          EX     DE,HL
          LD     B,0
          XOR    A
          RET
_inff:    CP     MD_FSH
          JR     NZ,_infno
          LD     A,(FD_PGS)
          OR     A
          JR     Z,_infno
          LD     L,A
          LD     H,0
          ADD    HL,HL
          ADD    HL,HL
          ADD    HL,HL
          DEC    HL
          EX     DE,HL
          LD     B,1
          XOR    A
          RET
_infno:   LD     A,0FFh
          OR     A
          RET

; ---------- MD_REC
; Leer o escribir un registro de 128 bytes con el DMA de la aplicacion.
; INPUT:  A  - tarjeta (2 RAM, 3 flash)
;         B  - 0 leer, 1 escribir
;         DE - numero de registro dentro del disco
; OUTPUT: A = 0 bien (Z); 1 error (fuera del disco o escritura en flash)
MD_REC:   LD     HL,(DMA_ADDR)
          LD     (MD_DMA),HL
          JR     _xfr

; ---------- MD_SEC
; Igual con un sector de 512 bytes: DE = sector. Son 4 registros seguidos.
MD_SEC:   LD     HL,(DMA_ADDR)
          LD     (MD_DMA),HL
          LD     (MD_TYP),A
          EX     DE,HL             ; Registro = sector x 4
          ADD    HL,HL
          ADD    HL,HL
          EX     DE,HL
          LD     C,4
_sec1:    PUSH   BC
          PUSH   DE
          LD     A,(MD_TYP)
          CALL   _xfr
          POP    DE
          POP    BC
          RET    NZ
          INC    DE
          LD     HL,(MD_DMA)
          PUSH   DE
          LD     DE,128
          ADD    HL,DE
          POP    DE
          LD     (MD_DMA),HL
          DEC    C
          JR     NZ,_sec1
          XOR    A
          RET

; Un registro: A tarjeta, B direccion, DE registro, MD_DMA destino/origen
_xfr:     PUSH   BC
          LD     C,A
          ; Pagina dentro del disco = registro / 128; desplazamiento = resto x 128
          LD     A,E
          RLA
          LD     A,D
          RLA                      ; A = (D << 1) | bit 7 de E
          LD     H,A               ; H = indice de pagina
          LD     A,E
          AND    7Fh
          RRA                      ; (E & 7F) x 128 = byte alto (E&7F)>>1,
          LD     D,A               ;                  byte bajo (E&1)<<7
          LD     A,0
          RRA
          LD     E,A
          LD     A,D
          OR     40h               ; En el banco 1
          LD     D,A               ; DE = direccion del registro en el banco 1
          LD     A,C
          CP     MD_RAM
          JR     NZ,_xff
          LD     A,(RD_PGS)
          CP     H
          JR     C,_xbad
          JR     Z,_xbad
          LD     A,H
          LD     HL,RD_TAB
          CALL   _add
          LD     A,(HL)            ; Pagina de RAM
          JR     _xgo
_xff:     CP     MD_FSH
          JR     NZ,_xbad
          POP    BC
          PUSH   BC
          LD     A,B               ; La flash es de solo lectura
          OR     A
          JR     NZ,_xbad
          LD     A,(FD_PGS)
          CP     H
          JR     C,_xbad
          JR     Z,_xbad
          LD     A,H
          ADD    A,FD_PG0          ; Pagina de flash
_xgo:     POP    BC
          LD     C,A               ; C = pagina del disco
          LD     A,B
          OR     A
          JR     NZ,_xwr
          ; Leer: disco -> buffer -> DMA
          LD     A,C
          OUT    (PG_PORT0+1),A
          EX     DE,HL
          LD     DE,MD_BUF
          LD     BC,128
          LDIR
          CALL   _mapdma
          LD     HL,MD_BUF
          LD     DE,(MD_DMA)
          LD     BC,128
          LDIR
          XOR    A
          RET
_xwr:     ; Escribir: DMA -> buffer -> disco
          PUSH   DE
          PUSH   BC
          CALL   _mapdma
          LD     HL,(MD_DMA)
          LD     DE,MD_BUF
          LD     BC,128
          LDIR
          POP    BC
          POP    DE
          LD     A,C
          OUT    (PG_PORT0+1),A
          LD     HL,MD_BUF
          LD     BC,128
          LDIR
          XOR    A
          RET
_xbad:    POP    BC
          LD     A,1
          OR     A
          RET

; El buffer de la aplicacion en los bancos 1 y 2
_mapdma:  LD     A,(DMA_PAGE)
          OUT    (PG_PORT0+1),A
          LD     A,(DMA_PG2)
          OUT    (PG_PORT0+2),A
          RET

          DSEG
RD_PGS    DEFB   0          ; Paginas del disco en RAM (0 = no hay)
FD_PGS    DEFB   0          ; Paginas del disco en flash
MD_TYP    DEFS   1
MD_DMA    DEFS   2
MD_BUF    DEFS   128
RD_TAB    DEFS   224        ; Paginas del disco en RAM, en orden
