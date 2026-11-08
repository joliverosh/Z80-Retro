import ../zlib/defs.asm
import config.asm
import pcb_def.asm

; hwsvc.asm
; Este modulo se enlaza con ZLoader (pagina de ZLoader, banco 0), que siempre
; esta mapeada mientras corre un servicio: asi no ocupa el poco espacio que
; queda en la pagina de ZIOS. Lo que usan las interrupciones en el contexto de
; la aplicacion (TICKS y _ETICK) esta en init.asm, en la pagina de ZIOS.
; Hardware de la placa principal que el software original no usaba:
;   - CTC: tic del sistema (canal 1, v6; antes canal 2) y reloj de la SIO
;     (canal 0, si P3/P6 estan en CLK0_OUT). El canal 2 queda libre: en la
;     ZEPHYRUS (Rev 2.3) su salida ZC/TO2 mueve el altavoz.
;   - Servicios: 31 tic, 32 configurar SIO, 33 SPI (S3-S5), 34 I2C, 35 memoria
;   - Deteccion de RAM de expansion en el bus (paginas 40-FF)

          public TMR_INI,TMR_OFF,BEEP,BEL_HK,LD_GPIO,LD_BEEP
          public LD_TICK,LD_SERCFG,LD_SPI,LD_I2C,LD_MEMINV
          public MEM_PRB,MEM_TOT

          extrn  P_MAPX,P_RES,P_FREEN
          extrn  NVRAM,ADD8T16
          extrn  SIO_CFG,SW_CFG
          extrn  SPI_SEL,SPI_STRT,SPI_END,SPI_FIN,SPI_XCH,DEVSEL
          extrn  I2C_STRT,I2C_STOP,I2C_WBY,I2C_RBY
          extrn  CACHE,TICKS

          CSEG

; ===================================================================
; CTC
; Canal 0: temporizador sin interrupcion. Su salida ZC/TO0 (CLK0_OUT) puede
;          dar el reloj a los dos canales de la SIO con P6 (canal A) y P3
;          (canal B). En x16: baudios = CPU / (256 x TC); con 7,3728 MHz
;          TC=3 da 9600, 6 da 4800, 12 da 2400, 24 da 1200. Si los puentes
;          estan en CLKU no tiene efecto.
; Canal 1: tic del sistema (v6). Temporizador con preescala 256 y TC=240:
;          120 Hz con 7,3728 MHz (240 Hz con 14,7456 MHz). En la v5 era el
;          canal 2, pero en la ZEPHYRUS ZC/TO2 va al altavoz y el tic sonaba
;          como un zumbido de 120 Hz con el interruptor BEEP en ON.
; Canal 2: tono del altavoz de la ZEPHYRUS (BEEP), apagado el resto del tiempo.
; El canal 3 lo sigue usando la tarjeta de video (vdu.asm) si esta.
; ===================================================================
CTC_VEC   EQU    0F0h       ; Vectores FFF0-FFF6 (CTC_ICH0..3)

TMR_INI:  DI
          LD     A,CTC_VEC
          OUT    (CTC_CH0),A                 ; Vector (bit 0 = 0)
          LD     A,00000111b                 ; Canal 0: temporizador, /16, sin int.
          OUT    (CTC_CH0),A
          CALL   SW_CFG                      ; Interruptores en 11: valores de siempre
          AND    3
          CP     3
          LD     A,3                         ; 9600 en x16 con 7,3728 MHz
          JR     Z,_tc0
          LD     A,(NVRAM+NV_CTC0)
          OR     A
          JR     NZ,_tc0
          LD     A,3
_tc0:     OUT    (CTC_CH0),A
          LD     A,10100111b                 ; Canal 1: int, temporizador, /256
          OUT    (CTC_CH1),A
          LD     A,240
          OUT    (CTC_CH1),A
          LD     A,00000011b                 ; Canal 2 parado (altavoz en silencio)
          OUT    (CTC_CH2),A
          LD     A,120
          LD     HL,NVRAM+NV_CLK
          BIT    0,(HL)
          JR     Z,_hz
          ADD    A,A                         ; 240 Hz con 14,7456 MHz
_hz:      LD     (TCK_HZ),A
          EI
          RET

; Apagar el tic (las aplicaciones sin ZIOS). El canal 0 sigue andando porque
; puede ser el reloj de la consola.
TMR_OFF:  LD     A,00000011b
          OUT    (CTC_CH1),A
          RET

; --------- BEEP (v6)
; Pitido de unos 0,1 s por el altavoz de la ZEPHYRUS: canal 2 del CTC como
; temporizador con preescala 256 y TC=33 (873 Hz con 7,3728 MHz). Solo si la
; NVRAM dice que la placa es la Rev 2.3; en la Rev 2.2 no hace nada. Suena
; solo con el interruptor 7 (BEEP) del DIP en ON. Conserva todos los registros.
BEEP:     PUSH   AF
          LD     A,(NVRAM+NV_BOARD)
          CP     BRD_23
          JR     NZ,_bpx
          PUSH   BC
          LD     A,00100111b                 ; Temporizador, /256, sin int., sigue TC
          OUT    (CTC_CH2),A
          LD     A,33
          OUT    (CTC_CH2),A
          LD     BC,28000                    ; ~0,1 s a 7,3728 MHz
_bpw:     DEC    BC
          LD     A,B
          OR     C
          JR     NZ,_bpw
          LD     A,00000011b                 ; Parar
          OUT    (CTC_CH2),A
          POP    BC
_bpx:     POP    AF
          RET

; BEL_HK: lo llama la salida de caracteres (servicio 4). Con BEL (07h) pita.
BEL_HK:   CP     7
          CALL   Z,BEEP
          RET

; --------- LD_GPIO (servicio 37, v6)
; Escribir las 6 salidas del GPIO de la ZEPHYRUS (74HC174 en 6Ch).
; INPUT: E - bits 0-5 = Q0-Q5. OUTPUT: A = 0
LD_GPIO:  LD     A,E
          OUT    (6Ch),A
          XOR    A
          RET

; --------- LD_BEEP (servicio 38, v6): un pitido (solo en la Rev 2.3)
LD_BEEP:  CALL   BEEP
          XOR    A
          RET

; --------- LD_TICK (servicio 31)
; OUTPUT: DEHL - tics desde el arranque (32 bits)
;         A    - tics por segundo
LD_TICK:  DI
          LD     HL,(TICKS)
          LD     DE,(TICKS+2)
          EI
          LD     A,(TCK_HZ)
          RET

; --------- LD_SERCFG (servicio 32)
; Configurar el reloj de un canal de la SIO (no se guarda; el comando BAUD de
; ZLoader lo guarda en la NVRAM).
; INPUT: B - canal (0 = A, 1 = B)
;        D - modo de reloj: 1 = x16, 2 = x32, 3 = x64, 0 = sin cambio
;        E - constante del canal 0 del CTC (0 = sin cambio). Comun a los dos
;            canales, solo cuenta si su puente esta en CLK0_OUT.
; OUTPUT: A = 0 bien, FFh parametro invalido
LD_SERCFG:LD     A,B
          CP     2
          JR     NC,_scbad
          LD     A,D
          CP     4
          JR     NC,_scbad
          LD     A,E
          OR     A
          JR     Z,_scnoc
          LD     A,00000111b
          OUT    (CTC_CH0),A
          LD     A,E
          OUT    (CTC_CH0),A
_scnoc:   LD     A,D
          OR     A
          RET    Z
          RRCA                     ; 1,2,3 -> bits 7-6 = 01,10,11
          RRCA
          OR     00000100b         ; 1 bit de parada, sin paridad
          CALL   SIO_CFG
          XOR    A
          RET
_scbad:   LD     A,0FFh
          OR     A
          RET

; --------- LD_SPI (servicio 33)
; Intercambio con un dispositivo SPI general (selecciones S3, S4 y S5 del
; conector = dispositivos 2, 3 y 4). Las tarjetas SD (0 y 1) no se aceptan.
; INPUT: B  - dispositivo (2-4); bit 7 = dejar el CS activo al terminar (para
;             partir una transaccion en varias llamadas)
;        E  - numero de bytes (0 = 256)
;        HL - buffer en la aplicacion: se manda su contenido y se reemplaza
;             por lo recibido
; OUTPUT: A = 0 bien, FFh dispositivo invalido
LD_SPI:   LD     A,B
          AND    7Fh
          CP     2
          JR     C,_spbad
          CP     5
          JR     NC,_spbad
          PUSH   AF
          LD     A,(DEVSEL)
          LD     (SPI_SV),A
          POP    AF
          CALL   SPI_SEL
          LD     A,B               ; Si la llamada anterior dejo el CS de este
          AND    7Fh               ; mismo dispositivo activo, la transaccion
          LD     C,A               ; sigue (solo se vuelve a activar el CS)
          LD     A,(SPI_CSA)
          CP     C
          JR     Z,_spcnt
          CALL   SPI_STRT
          JR     _spgo
_spcnt:   LD     A,(DEVSEL)
          OUT    (SPICS_P),A
_spgo:
          CALL   P_MAPX            ; Buffer de la aplicacion en los bancos 1/2
          LD     C,E
_spnx:    LD     A,(HL)
          CALL   SPI_XCH
          LD     (HL),A
          INC    HL
          DEC    C
          JR     NZ,_spnx
          LD     A,B               ; Dispositivo con el CS activo (0 = ninguno)
          AND    7Fh
          BIT    7,B
          JR     NZ,_spkeep
          XOR    A
          LD     (SPI_CSA),A
          CALL   SPI_END
          JR     _sprst
_spkeep:  LD     (SPI_CSA),A
_sprst:   LD     A,(SPI_SV)
          LD     (DEVSEL),A
          XOR    A
          RET
_spbad:   LD     A,0FFh
          OR     A
          RET

; --------- LD_I2C (servicio 34)
; Acceso a dispositivos del bus I2C (el DS1307 esta en D0h).
; INPUT: B  - funcion: 0 = escribir, 1 = leer, 2 = probar si responde
;        D  - direccion del dispositivo en 8 bits (bit 0 se ignora)
;        E  - numero de bytes (0 = 256)
;        HL - buffer en la aplicacion
; OUTPUT: A = 0 bien, 1 el dispositivo no respondio (NAK), FFh funcion invalida
LD_I2C:   LD     A,B
          CP     3
          JR     NC,_spbad
          PUSH   AF
          LD     A,H
          OR     L
          CALL   NZ,P_MAPX
          POP    AF
          LD     C,A               ; C = funcion
          CALL   I2C_STRT
          LD     A,D
          AND    0FEh
          BIT    0,C               ; Leer: bit R/W = 1
          JR     Z,_i2a
          INC    A
_i2a:     CALL   I2C_WBY
          AND    1                 ; ACK = 0
          JR     NZ,_i2nak
          LD     A,C
          CP     2
          JR     Z,_i2ok           ; Solo probar
          LD     B,E
          OR     A
          JR     NZ,_i2rd
_i2wr:    LD     A,(HL)
          INC    HL
          CALL   I2C_WBY
          AND    1
          JR     NZ,_i2nak
          DJNZ   _i2wr
          JR     _i2ok
_i2rd:    LD     A,B
          DEC    A                 ; Ultimo byte: NAK (A=1); si no ACK (A=0)
          LD     A,0
          JR     NZ,_i2r1
          INC    A
_i2r1:    CALL   I2C_RBY
          LD     (HL),A
          INC    HL
          DJNZ   _i2rd
_i2ok:    CALL   I2C_STOP
          XOR    A
          RET
_i2nak:   CALL   I2C_STOP
          LD     A,1
          OR     A
          RET

; --------- LD_MEMINV (servicio 35)
; OUTPUT: A - paginas de RAM instaladas (32 en la placa + las del bus)
;         B - paginas libres ahora
LD_MEMINV:LD     A,(MEM_TOT)
          PUSH   AF
          CALL   P_FREEN
          LD     B,A
          POP    AF
          RET

; ===================================================================
; MEM_PRB - deteccion de RAM en el bus de expansion (paginas 40-FF)
; Las paginas 40-7F y C0-FF (BA20 = 1) nunca son de la placa. Las 80-BF
; repiten la memoria de la placa salvo que el puente BA21SEL este en BRDM,
; y una tarjeta de expansion puede repetirse dentro de su rango. Por eso,
; ademas de comprobar que la pagina guarda datos, se escribe en cada una su
; numero y se descartan las que resultan ser repeticion de otra.
; Se usan 2 bytes al final de cada pagina (3FF0/3FF1) y se dejan como
; estaban. Usa el banco 1 y la cache de disco de ZIOS como espacio de trabajo
; (todavia no tiene datos). Se llama una vez al arrancar ZIOS.
; ===================================================================
PRB_A     EQU    7FF0h      ; Desplazamiento 3FF0 de la pagina en el banco 1

; Se llama con las interrupciones deshabilitadas (arranque de ZIOS).
MEM_PRB:  ; 1. Guardar los valores originales de las 256 paginas
          LD     C,0
_p1:      LD     A,C
          OUT    (PG_PORT0+1),A
          LD     A,(PRB_A)
          LD     HL,CACHE
          CALL   _idx
          LD     (HL),A
          LD     A,(PRB_A+1)
          INC    H                 ; ORIG1 = ORIG0 + 256
          LD     (HL),A
          INC    H                 ; CAND
          LD     (HL),0
          INC    C
          JR     NZ,_p1

          ; 2. Paginas 40-FF: probar que guardan datos y escribir su numero
          LD     C,40h
_p2:      LD     A,C
          OUT    (PG_PORT0+1),A
          ; 80-9F pueden ser la flash de la placa (BA21 sin decodificar): si la
          ; pagina es igual a su gemela de flash no se escribe nada, para no
          ; mandarle escrituras sueltas a la flash.
          CP     80h
          JR     C,_p2t
          CP     0A0h
          JR     NC,_p2t
          SUB    80h
          OUT    (PG_PORT0+2),A
          PUSH   BC
          LD     HL,4000h          ; Dos ventanas de 32 bytes: al principio y en
          LD     DE,8000h          ; 3E00 (en la pagina 1 de flash hay codigo en
          CALL   _cmp32            ; los dos sitios)
          JR     NZ,_p2d
          LD     HL,7E00h
          LD     DE,0BE00h
          CALL   _cmp32
_p2d:     POP    BC
          JR     NZ,_p2t
          LD     HL,CACHE+512      ; 32 bytes iguales: es la flash. Marca 2 =
          CALL   _idx              ; no se escribio (tampoco se restaura)
          LD     (HL),2
          JR     _p2n
_p2t:     LD     HL,PRB_A
          LD     (HL),55h
          INC    HL
          LD     (HL),0AAh         ; Otra direccion: el bus flotante no la recuerda
          DEC    HL
          LD     A,(HL)
          CP     55h
          JR     NZ,_p2n
          INC    HL
          LD     A,(HL)
          CP     0AAh
          JR     NZ,_p2n
          LD     (HL),55h
          DEC    HL
          LD     (HL),0AAh
          LD     A,(HL)
          CP     0AAh
          JR     NZ,_p2n
          INC    HL
          LD     A,(HL)
          CP     55h
          JR     NZ,_p2n
          ; Guarda datos: firma = numero de pagina y su complemento
          DEC    HL
          LD     (HL),C
          INC    HL
          LD     A,C
          CPL
          LD     (HL),A
          LD     HL,CACHE+512
          CALL   _idx
          LD     (HL),1
_p2n:     INC    C
          JR     NZ,_p2

          ; 3. Descartar repeticiones: la firma debe seguir siendo la propia,
          ;    y la pagina gemela de la placa (p-80h) no debe haber cambiado
          LD     C,40h
_p3:      LD     HL,CACHE+512
          CALL   _idx
          LD     A,(HL)
          CP     1
          JR     NZ,_p3n
          LD     A,C
          OUT    (PG_PORT0+1),A
          LD     A,(PRB_A)
          CP     C
          JR     NZ,_p3x
          LD     A,(PRB_A+1)
          CPL
          CP     C
          JR     NZ,_p3x
          LD     A,C
          SUB    80h
          JR     C,_p3n            ; 40-7F: no tienen gemela en la placa
          CP     40h
          JR     NC,_p3n           ; C0-FF tampoco
          LD     B,A               ; B = pagina de la placa
          OUT    (PG_PORT0+1),A
          LD     A,B
          LD     HL,CACHE
          PUSH   BC
          LD     C,B
          CALL   _idx
          POP    BC
          LD     A,(PRB_A)
          CP     (HL)
          JR     NZ,_p3x           ; Cambio: es la misma memoria
          INC    H
          LD     A,(PRB_A+1)
          CP     (HL)
          JR     Z,_p3n
_p3x:     LD     HL,CACHE+512
          CALL   _idx
          LD     (HL),0
_p3n:     INC    C
          JR     NZ,_p3

          ; 4. Restaurar: primero las del bus y al final las de la placa (si una
          ;    pagina del bus era repeticion, la de la placa queda bien)
          LD     C,40h
_p4:      LD     HL,CACHE+512
          CALL   _idx
          LD     A,(HL)
          CP     2                 ; Pagina de flash: no se toco
          CALL   NZ,_rest
          INC    C
          JR     NZ,_p4
          LD     C,RAM_PG_0        ; La flash no se toca (no puede haber cambiado)
_p5:      CALL   _rest
          INC    C
          LD     A,C
          CP     40h
          JR     NZ,_p5

          ; 5. Las paginas del bus que no estan quedan reservadas; contar las RAM
          LD     B,32              ; RAM de la placa
          LD     C,40h
_p6:      LD     HL,CACHE+512
          CALL   _idx
          LD     A,(HL)
          CP     1
          LD     A,C
          JR     Z,_p6y
          CALL   P_RES             ; No hay RAM: que nunca se reparta
          JR     _p6n
_p6y:     INC    B
_p6n:     INC    C
          JR     NZ,_p6
          LD     A,B
          LD     (MEM_TOT),A

          ; Bancos 1 y 2 como los tiene la aplicacion
          LD     A,(PAGE_MP+1)
          OUT    (PG_PORT0+1),A
          LD     A,(PAGE_MP+2)
          OUT    (PG_PORT0+2),A
          RET

; Z si los 32 bytes de (HL) y (DE) son iguales
_cmp32:   LD     B,32
_c32:     LD     A,(DE)
          CP     (HL)
          RET    NZ
          INC    HL
          INC    DE
          DJNZ   _c32
          RET

; HL = HL + C
_idx:     PUSH   AF
          LD     A,L
          ADD    A,C
          LD     L,A
          JR     NC,_idx1
          INC    H
_idx1:    POP    AF
          RET

; Restaurar los dos bytes de prueba de la pagina C
_rest:    LD     A,C
          OUT    (PG_PORT0+1),A
          LD     HL,CACHE
          CALL   _idx
          LD     A,(HL)
          LD     (PRB_A),A
          INC    H
          LD     A,(HL)
          LD     (PRB_A+1),A
          RET

          DSEG
TCK_HZ    DEFS   1
SPI_SV    DEFS   1
SPI_CSA   DEFB   0
MEM_TOT   DEFB   32
