# CP/M 3 (CP/M Plus) con bancos para la Z80-Retro

Port de CP/M 3 de Digital Research, en su versión **con bancos**, a la Z80-Retro
(peterw8102, Z80 CPU Rev 2.2) funcionando sobre los servicios de ZIOS.

- **TPA de 60K** (61.696 bytes, de 0100h a F1FFh).
- Unidades **A: a H:** con el **mismo formato de disco que el CP/M 2.2** de
  `apps/cpm22`: los dos sistemas comparten discos (incluso el de arranque).
- **G:** disco en RAM y **H:** disco en flash de solo lectura de ZIOS (si existen).
- Tablas de *hash* de directorio, vectores de asignación y buffers de
  directorio en el banco 0; buffers de datos de GENCPM en el banco 0/2.
- Reloj: `DATE` lee y **pone** la fecha/hora del DS1307.
- Errores de la tarjeta SD: se avisa en la consola y el BDOS da el error
  normal (`CP/M Error On A: Disk I/O`); no se cuelga.

Necesita ZLoader/ZIOS v5 (commit f65e73e o posterior): usa los servicios
1, 2, 4-6, 12, 13, 15, 28, 29, 30, 34, 35 y 36.

## Ficheros

| Fichero | Qué es |
|---|---|
| `bios3.asm` | BIOS con bancos (Z80, zmac). Parte común + parte en el banco 0 |
| `ldrbios.asm` | BIOS mínimo para el cargador CPMLDR |
| `gencpm.dat` | Respuestas para `GENCPM AUTO` |
| `mk.sh` | Construye todo (zmac + RMAC/LINK/GENCPM de DRI bajo zxcc) |
| `mkpkg.py` | Genera el Intel HEX del cargador y los paquetes para DOWNLOAD |
| `dri/` | Ficheros de Digital Research (ver `dri/LEEME.md`) |
| **`cpmldr.hex`** | Cargador ya construido (Intel HEX en 0100h, para el comando `L`) |
| `cpmldr.com` | El mismo cargador en binario |
| **`cpm3.sys`** | Sistema ya generado (BDOS + BIOS) |
| **`cpm3.pkg`** | Paquete DOWNLOAD: CPM3.SYS, CCP.COM y utilidades básicas |
| `cpm3dev.pkg` | Paquete DOWNLOAD: GENCPM, LINK, RMAC, los .SPR, GENCPM.DAT y el resto de utilidades de DRI |

`cpm3.pkg` contiene: CPM3.SYS, CCP.COM, DATE, DEVICE, DIR, DUMP, ED, ERASE,
GET, HELP, INITDIR, PIP, PUT, RENAME, SAVE, SET, SETDEF, SHOW, SUBMIT y TYPE.
`cpm3dev.pkg`: BNKBIOS3.SPR, RESBDOS3.SPR, BNKBDOS3.SPR, GENCPM.COM,
GENCPM.DAT, LINK, RMAC, MAC, LIB, XREF, ZSID, GENCOM, HEXCOM, PATCH y HELP.HLP.

## Cómo arranca

```
ZLoader  --BOS 3-->  CPMLDR (sector 40h de A:, cargado en 0100h)
         --lee A:CPM3.SYS-->  BIOS (arranque en frío)
         --lee A:CCP.COM-->   A>
```

1. ZLoader carga desde la zona de sistema del disco A: (los primeros 64K del
   disco, que el CP/M de la Z80-Retro reserva) el cargador **CPMLDR** de DRI
   con nuestro `ldrbios`. Va en el **sector 40h**: el CP/M 2.2 ocupa los
   sectores 0-10h, así que los dos sistemas caben en el mismo disco.
2. CPMLDR lee **A:CPM3.SYS** (usuario 0) del sistema de ficheros, pone la
   parte común arriba (F200h-FDFFh) y la parte con bancos en el banco 0
   (7600h-BFFFh) y salta al BIOS.
3. El BIOS pide las páginas de los bancos 1 y 2, carga **A:CCP.COM** con el
   BDOS y guarda una copia en el banco 2 para los arranques en caliente.

Se eligió este camino (en vez de una imagen binaria cargada directamente por
ZLoader) porque es el estándar de DRI y el más robusto de mantener: el sistema
es un fichero normal, así que para cambiarlo basta con copiar otro CPM3.SYS
(se puede regenerar en la propia placa con GENCPM) sin tocar ZLoader ni la
zona de sistema.

## Instalación (desde ZLoader)

Requisitos: CP/M 2.2 instalado en A: con su entrada de arranque (ID 1) y
`DOWNLOAD.COM` en A:, tal como explica
[Installing-CPM](https://github.com/peterw8102/Z80-Retro/wiki/Installing-CPM)
(en v5: `WI 0:A DC00 FDFF` y `WB 1 0:A DC00 2200 F20C 01 CP/M`). Hace falta el
**control de flujo por hardware** (RTS/CTS) en el terminal para pegar los
paquetes.

**1. Copiar los ficheros a A: desde CP/M 2.2**

```
> BOS 1
a>
```
En el indicador `a>` **pegar** el contenido de `cpm3.pkg` (sin escribir nada
antes). Cada fichero termina con `OK`. Opcionalmente pegar también
`cpm3dev.pkg` (herramientas para regenerar el sistema en la placa).

> Pegar los paquetes desde CP/M 2.2, no desde CP/M 3: en CP/M 3 el BDOS se
> come los caracteres que llegan mientras escribe el indicador y se pierde el
> principio de cada línea `A:DOWNLOAD`. Un fichero suelto con `DOWNLOAD` sí
> funciona en CP/M 3.

**2. Escribir el cargador y la entrada de arranque**

Reiniciar la placa para volver a ZLoader y escribir:

```
> F 0 0 0
> L
(pegar el contenido de cpmldr.hex)
> WI 40:A 0100 12FF
> WB 3 40:A 0100 1200 0100 01 CPM3
> BOS 3
```

- `WI 40:A 0100 12FF` escribe el cargador (0100h-12FFh, 9 sectores) a partir
  del sector 40h del disco A:.
- `WB 3 ...` añade la entrada 3 del menú: carga 1200h bytes desde 40:A en
  0100h, ejecuta en 0100h, `01` = usa ZIOS (sin manejador de *break*).

Al arrancar se ve:

```
CP/M V3.0 Loader
...
 60K TPA

CP/M 3 con bancos para Z80-Retro (ZIOS)
A>
```

Para que CP/M 3 sea el sistema que arranca solo (con los interruptores de
autoarranque, que buscan la ID 1):

```
> WB 1 DELETE
> WB 1 40:A 0100 1200 0100 01 CPM3
```
(el CP/M 2.2 puede seguir en otra ID, p. ej. `WB 2 0:A DC00 2200 F20C 01 CP/M`).

## Uso

- Fecha y hora: `DATE` la muestra, `DATE SET` la pide y `DATE 12/24/27 23:59:30`
  la pone (pide pulsar una tecla). Se guarda en el DS1307.
- Páginas: la consola pagina por defecto (24 líneas). `SETDEF [NO PAGE]` lo
  quita.
- Unidades: `SHOW [DRIVES]`, `SHOW G:`. G: es el disco en RAM de ZIOS, H: el
  disco en flash (solo lectura: escribir da `R/O DISK`). Si no existen dan
  `Invalid Drive`. A:-F: son los discos virtuales de la SD montados por ZIOS
  (comando `SM` de ZLoader).
- Dispositivos de caracteres (`DEVICE`): `SIOA` (canal A), `CRT` (consola de
  ZIOS: vídeo y teclado si están, si no el canal A) y `SIOB` (canal B en modo
  serie general). Por defecto `CONIN:/CONOUT:` = CRT, `AUXIN:/AUXOUT:` = SIOB,
  `LST:` = SIOA (lo mismo que hacía el IOBYTE del CP/M 2.2).
- `RST 30h` sigue llevando a ZIOS en la TPA, como en CP/M 2.2.
- `^C` en el indicador reinicia el sistema de discos (por ejemplo después de
  cambiar un disco con `SM` desde otro programa).

## Regenerar el sistema

**En el ordenador** (Linux/macOS): hace falta `zmac` (el mismo de
`apps/cpm22`), `python3` y `zxcc`, un emulador de CP/M que ejecuta las
herramientas de DRI (por ejemplo el de RomWBW, `Tools/unix/zxcc`, que se
compila con `make`; o el de John Elliott). Luego:

```
cd apps/cpm3
ZXCC=/ruta/a/zxcc ./mk.sh
```

Genera `cpm3.sys`, `cpmldr.com`, `cpmldr.hex`, `cpm3.pkg` y `cpm3dev.pkg`.
Los pasos son: zmac de `bios3.asm` y `ldrbios.asm` a .REL;
`RMAC CPMLDR` y `LINK CPMLDR[L100]=CPMLDR,LDRBIOS`; `RMAC SCB` y
`LINK BNKBIOS3[B]=BIOS3,SCB`; `GENCPM AUTO DISPLAY`.

**En la placa**: con `cpm3dev.pkg` instalado, editar si se quiere `GENCPM.DAT`
(número de buffers, hash...) y ejecutar `GENCPM AUTO` (o `GENCPM` para
contestar a mano) en A:. Escribe un CPM3.SYS nuevo que se usa en el siguiente
arranque (`BOS 3`). Conviene guardar antes una copia (`PIP CPM3.BAK=CPM3.SYS`).

## Detalles del port

### Memoria

| Ventanas | Banco 0 (sistema) | Banco 1 (TPA) | Banco 2 |
|---|---|---|---|
| 0000-3FFF | P0 | T0 | X |
| 4000-7FFF | P1 | T1 | P1 |
| 8000-BFFF | P2 | T2 | P2 |
| C000-FDFF | común (página 3 de la aplicación) | | |
| FE00-FFFF | ZIOS (entrada de servicios, vectores IM2) | | |

- P0-P2 son las páginas con las que ZLoader lanza la aplicación; T0-T2 y X se
  piden a ZIOS con el servicio 2. La página de la ventana 0 no se puede
  preguntar a ZIOS (servicio 1 no sirve para el banco 0), así que el BIOS la
  busca escribiendo una firma en 0040h y mirando, por la ventana 1, qué página
  de RAM la tiene (las que dice el servicio 35, incluida la RAM de expansión).
- Común (F200-FDFF): RESBDOS3 y la parte común del BIOS (vector, E/S de
  caracteres, DPB, gestión de bancos, arranque, pila).
- Banco 0: BNKBDOS3 (7600h), parte con bancos del BIOS (A400h: DPH, disco,
  reloj), y lo que reparte GENCPM: tablas de hash de A:-H:, vectores de
  asignación dobles, 8 buffers de directorio y 8 de datos (compartidos).
- Banco 2: segmento de GENCPM 0000-2FFF; la copia del CCP está en 3000-3FFF.
- Cambio de banco (SELMEM) siempre a través de ZIOS, para que su mapa de
  páginas (que repone al volver de cada servicio y en la interrupción del CTC)
  esté al día.
- Copias entre bancos (XMOVE/MOVE, copia del CCP, buffer intermedio): con las
  interrupciones desactivadas se ponen directamente en las ventanas 1 y 2 la
  página de origen y la de destino, se copian como mucho 128 bytes y se
  reponen las páginas del banco actual.

### Disco

- Sectores físicos de **512 bytes** con los servicios **13/15** (leer/escribir
  sector de una unidad lógica) y el *deblocking* del propio BDOS de CP/M 3
  (PSH=2, PHM=3). Dirección: H = unidad, DE = pista×128 + sector.
  Se descartaron los servicios 17/18 (registros de 128 bytes con la caché de
  ZIOS) porque CP/M 3 ya tiene sus propios buffers en el banco 0 con LRU y
  *hash*, y con 17/18 los datos pasarían por dos cachés; además 13/15 permiten
  leer un sector entero directamente en la TPA.
- El destino de cada transferencia (SETBNK): banco 0 o memoria común →
  servicio 12 (dirección normal); otro banco → servicio 30 con la página
  física. Si un sector de 512 bytes cruzaría el final de una página de otro
  banco se usa un buffer intermedio en el banco 0.
- DPB del disco de la SD: igual que el CP/M 2.2 (SPT 512, bloques de 2K, DSM
  2015, DRM 511, AL0 FFh, OFF 1, CKS 8000h = disco fijo). En el primer acceso
  a cada unidad el BIOS pregunta a ZIOS (servicio 36) qué hay: SD, disco en
  RAM o en flash (128 entradas, OFF 0, DSM y EXM según el tamaño) o nada.
- 3 intentos por sector antes de dar el error.

### Reloj

`TIME` lee el DS1307 con el servicio 28 y lo convierte al formato de CP/M 3
(días desde el 31/12/1977, hora en BCD). Al poner la hora escribe los
registros 0-6 del DS1307 con el servicio 34 (I²C). Años 1978-2077.

### Notas sobre ZIOS v5 (para quien mantenga el firmware)

- **Servicio 29 (A_PGMAP3)**: la página del banco 1 se pasa en C, pero C es el
  número de servicio (29), así que siempre mapearía la página 1Dh (flash) en
  la ventana 1. El BIOS lo usa solo para las ventanas 0 y 2 y fija la 1
  después con el servicio 1 (E=1). Sería mejor tomar la página del banco 1
  de E (el BIOS ya la pasa también en E).
- **Servicio 15 (escribir sector)**: en la SD devuelve A = 5 cuando va bien
  (la respuesta de datos de la tarjeta), mientras que los discos en memoria y
  las lecturas devuelven 0. El BIOS acepta 0 o 5 en las escrituras.

## Pruebas hechas (emulador retroemu5, firmware v5 f65e73e)

- Instalación completa con el procedimiento de arriba (DOWNLOAD de
  `cpm3.pkg` y `cpm3dev.pkg` en CP/M 2.2, `L`/`WI`/`WB`/`BOS 3`): todos los
  ficheros llegan idénticos y arranca hasta `A>` con `60K TPA`.
- `DIR`, `TYPE`, `PIP`, `SHOW`, `SHOW [DRIVES]`, `DATE`, `DATE` con fecha
  (el DS1307 queda con la nueva), `SETDEF`, `ERA`, `REN`.
- Compatibilidad: ficheros escritos por CP/M 3 leídos por CP/M 2.2 (`TYPE`,
  `DIR`) y ficheros escritos/renombrados/borrados por CP/M 2.2 leídos y
  copiados por CP/M 3, en la misma imagen; la estructura de los directorios se
  comprobó desde fuera.
- Copia masiva: `PIP B:=A:*.COM`, `PIP B:=GRANDE.BIN` (300K) y
  `PIP C:=B:*.*[V]`: todo idéntico byte a byte; también con SDHC y con RAM de
  expansión. Se comprobó que se ejecutan los tres caminos de DMA (directo al
  banco 1, buffer intermedio al cruzar página y XMOVE).
- G: (RAM) lectura/escritura, H: (flash) lectura y error R/O al escribir,
  I: `Invalid Drive`.
- `^C` en el indicador y durante `TYPE`; arranques en caliente desde la copia
  del CCP en el banco 2.
- Error de lectura y de escritura inyectado en la SD: mensaje del BIOS,
  error del BDOS y vuelta a `A>`; el sistema sigue funcionando.
- `GENCPM AUTO` en la placa genera un CPM3.SYS idéntico al del ordenador y
  arranca con él.
