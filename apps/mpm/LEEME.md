# MP/M II 2.0 ZEPHYRUS 1.3

MP/M II 2.0 de Digital Research, el CP/M multiusuario de 1981, adaptado a ZEPHYRUS (corre también en la Z80 CPU Rev 2.2) con ZLoader/ZIOS v6. El XIOS es propio (`xios.asm`) y da el número de versión: 1.3. El resto son los archivos originales de Digital Research, con dos parches pequeños a `XDOS.SPR` (usuario 0 y el mensaje de arranque) y el título del cargador.

Probado en el emulador de la placa (`retroemu23`) con la v6 real. Funcionan:
- el arranque;
- `DIR`, `STAT`, `TYPE`, `PIP`, `ERA`, `MPMSTAT` y `TOD`;
- programas `.COM` y `.PRL`;
- MBASIC con los juegos;
- las dos consolas a la vez, en bancos distintos;
- tarjetas SDSC y SDHC;
- lo que MP/M escribe en la SD se lee después desde CP/M 2.2.

**Probado también en la placa real** (Z80 CPU Rev 2.2, flash MX29F040, 8/11/2026): arranca, toma la hora del DS1307 y `TOD` la muestra.

## Qué ofrece

| | |
|---|---|
| Consolas | 2: **SIO A** (la consola de siempre) y **SIO B** (segundo terminal o NUNTIUS). La salida va por interrupción, con un búfer de 32 caracteres por canal: un programa que escribe mucho ya no frena a los demás |
| Velocidad | La que dejó ZIOS. **`H:BAUD`** la muestra y la cambia en el momento, y la guarda en la NVRAM del DS1307 igual que la orden `BAUD` de ZLoader |
| Memoria | **De 1 a 7 bancos** de usuario de 48 KB (0000-BFFF), según la RAM: 5 con los 512 KB de la placa, 7 con RAM de expansión en el bus. La memoria común va de C000 a FFFF |
| Discos | **A-P**: las unidades de la SD con el mismo mapa de ZIOS (`SM`) y el mismo formato que CP/M 2.2; H: es el disco en flash, de solo lectura; **G:** es un disco en RAM |
| Disco en RAM | **G:**, con las páginas que sobran: 144 KB con los 512 KB de la placa; con la RAM de expansión, hasta 2 MB (880 KB con 1 MB). Se borra en cada arranque |
| Impresora | **`LST:` sale por SIO B** (la misma línea que la consola 1) **o a un archivo**, según `A:MPM.CFG` |
| Reloj | El tic de ZIOS: canal 1 del CTC, 120 Hz. MP/M recibe 60 tics por segundo |
| Hora | Se toma del DS1307 al arrancar. **Si se cambia con `TOD`, se escribe en el DS1307** |
| Caché de disco | 64 KB de RAM: el directorio y los programas no se vuelven a leer de la SD. Escritura inmediata: la SD siempre está al día |
| Historial | **`^W`** en el indicador repite la última orden; otro `^W`, la anterior (8 órdenes por consola) |
| Arranque | Si existe **`A:STARTUP.SUB`** (usuario 0), se ejecuta solo al arrancar |
| Servicios de ZIOS | Los programas que llaman a ZIOS con `RST 30h` funcionan: consola (0, 4, 5, 6), mapa de unidades (10, 11), hora (28), tics (31), I2C (34) y datos de una unidad (36) |
| Errores de la SD | Si una lectura o escritura falla, el XIOS vuelve a iniciar la tarjeta y reintenta. Si vuelve a fallar, avisa en la consola del programa qué unidad, pista y sector |
| Cambio de tarjeta | Se puede cambiar la SD con MP/M andando: después de cambiarla, `H:DSKRESET`. Cada unidad que se registra olvida lo que la caché tenía de su tarjeta |
| Volver a ZLoader | **`H:ZLOADER`**, sin RESET |

## Cómo se usa

1. Graba `zloader_sst39sf040_v6_mpm.bin` con la T48. Es la v6 con MP/M en el disco H:, en lugar de los programas de CP/M 3.
2. Arranca CP/M 2.2 con `BOS 1`.
3. Escribe `H:MPMLDR`.

**Arranque directo desde ZLoader** (sin pasar por CP/M). Una sola vez, en ZLoader:

```
L
```

manda `MPMLDR.HEX` (con `envia.py`) y después:

```
WI 70:A 0100 18FF
WB 5 70:A 0100 1800 0100 01 MP/M
```

Desde entonces `BOS 5` arranca MP/M. El cargador queda en los sectores 70h-7Bh de A:, en la zona de sistema que no usa nadie (CP/M 2.2 usa 0-10h, CP/M 3 40h-48h y OASIS 60h-61h).

```
a>H:MPMLDR
...
ZEPHYRUS XIOS 1.3 (OLIVEROS 2026): 2 consolas, 5 bancos, unidades A-P
64 KB de cache de disco
G: disco en RAM de 144 KB
A:STARTUP.SUB
MP/M II 2.0 ZEPHYRUS 1.3
(C) 1981 Digital Research
0A>TOD
Thu 10/15/26 10:30:02
```

- **El indicador** es `usuario` + `unidad` + `>`. Las dos consolas arrancan en `0A>`. Los programas del disco H: llevan el atributo SYS, así que se ven desde cualquier usuario y unidad.
- **PIP de MP/M es `H:PIP`.** Si en A: hay un `PIP.COM` de CP/M 3, ese gana al escribir solo `PIP` y responde `REQUIRES CP/M 3`.
- **Programas útiles:** `MPMSTAT` muestra procesos, bancos y colas. `ABORT nombre` detiene un programa. `CONSOLE` dice en qué consola estás.
- **Copiar un programa de H:** como es SYS, `PIP` necesita la opción `[R]`: `PIP A:=H:PRIMOS.COM[R]`.
- **Los programas de la placa que llaman a ZIOS** (`RST 30h`) reciben los servicios de consola, hora y tics, así que PRIMOS, BOMBE y PI miden bien el tiempo. `MOUNT` funciona (servicios 10 y 11): cambia el disco virtual de una unidad que ya está en la SD, si nadie tiene archivos abiertos en ella. Los servicios que no están devuelven A=FFh. `FORMAT` no sirve bajo MP/M porque llama al BIOS directamente: los discos nuevos se formatean desde ZLoader.
- **Las unidades I-P** existen si el mapa de ZIOS (`SM`) les asigna un disco de la SD. Un disco nuevo hay que formatearlo una vez desde ZLoader, por ejemplo la I: con `F 0 0 E5` y después `WI 80:I 8000 8000`.
- **`A:STARTUP.SUB`** es un archivo de SUBMIT normal, una orden por línea. Al arrancar, la consola 0 recibe `H:SUBMIT A:STARTUP`. Presionar una tecla mientras corre lo detiene (así es SUBMIT en MP/M).
- **El historial** (`^W`) solo actúa en el indicador `0A>`: dentro de un programa `^W` llega tal cual.
- **La impresora** (`LST:`, `^P`, `PIP LST:=archivo`) se elige en **`A:MPM.CFG`** (usuario 0), un archivo de texto que el XIOS lee al arrancar:

  ```
  ; configuracion de MP/M
  LST=B
  ```

  `LST=B`, o sin el archivo, la manda a SIO B: si ahí hay un terminal, la salida aparece en él. `LST=A:IMPRESOR.TXT` (cualquier nombre, con o sin unidad; sin unidad es A:) la guarda en ese documento. Lo impreso se agrega al final, así que el archivo crece hasta que lo borres. Al arrancar se ejecuta solo `H:LSTFILE`, que queda corriendo suelto (ocupa un banco) y pasa lo impreso al archivo cada medio segundo. Lo cierra tras 2 s sin impresión: mientras se imprime, `TYPE` responde `File Currently Open`; hay que esperar un momento.
- **`H:BAUD`** sin parámetros muestra la velocidad guardada de cada canal; `H:BAUD B 9600` la cambia y la guarda. Velocidades: 230400, 115200, 9600, 4800, 2400, 1200, 600 y 300 (con la CPU a 14,7456 MHz, el doble). Las de 9600 o menos usan el CTC: el puente del reloj de la SIO tiene que estar en CLK0_OUT (P6 para el canal A, P3 para el B), y los dos canales comparten esa constante. El mismo `BAUD.COM` funciona en CP/M 2.2 (allí cambia la velocidad con el servicio 32 de ZIOS; bajo MP/M programa la SIO directamente).
- **Para volver a ZLoader**: `H:ZLOADER`. Pide confirmación, espera a que nadie esté usando el disco y deja la máquina como después de un RESET. Lo que está corriendo se pierde, pero lo escrito en la SD ya está en la tarjeta.
- **Con RAM de expansión** en el bus (ZEPHYRUS), MP/M la usa sola: más bancos (hasta 7) y un G: más grande. El mensaje de arranque dice cuántos bancos y cuánto G: quedaron.

## Cómo está hecho

- **`MPMLDR.COM`** es el cargador de Digital Research con nuestro `LDRBIOS` (`ldrbios.asm`) en 1700h. Corre como programa de CP/M y lee `MPM.SYS` de H: con el servicio 17 de ZIOS.
- **`MPM.SYS`** lo arma `GENSYS` con estas opciones:
  - tope en la página FD: deja libre FE00-FFFF, donde está el puente de ZIOS;
  - 2 consolas, RST 7 para el depurador y 60 tics por segundo;
  - unidad del sistema H: y memoria común desde C000;
  - 7 segmentos de usuario (el XIOS deja en SYSDAT solo los que caben en la RAM).
- **`SYSTEMINIT` del XIOS** se aprovecha de que ZIOS todavía está debajo:
  - le pregunta qué páginas tiene el banco 0 (servicio 1);
  - le pide el mapa de unidades (servicio 11);
  - le pide el tamaño del disco en flash (servicio 36) y los tics por segundo (servicio 31);
  - le pide la fecha del DS1307 (servicio 28) y la escribe en la hora de XDOS, cuya dirección está en SYSDAT+252. Si el reloj no responde o la fecha no es válida, MP/M arranca con su fecha de fábrica (14/09/81);
  - le pide todas sus páginas libres (servicio 2) para saber qué RAM de expansión hay: ZIOS ya probó el bus al arrancar.

  Después desactiva las interrupciones y toma la máquina:
  - encuentra la página común;
  - junta las páginas libres (las de la placa y las del bus) y decide los bancos: (páginas − 13) / 3, entre 1 y 7. Pone ese número de segmentos en SYSDAT+15. Las que sobran van a la caché (4) y a G: (el resto, hasta 128);
  - escribe la página cero de cada banco;
  - pone sus rutinas en la tabla de vectores IM 2 de ZIOS: SIO en FFE0-FFEE y CTC en FFF0-FFF6;
  - activa la recepción y la transmisión por interrupción en las dos SIO;
  - averigua con CMD58 si cada tarjeta es SDHC.
- **Parche a `XDOS.SPR`** (lo hace `gensys.py` antes de llamar a GENSYS): Digital Research pone a cada consola en el usuario igual a su número (`tmp$pd.disk$slct = i` en `mpm.asm`), así que la B arrancaba en `1A>`. Se cambian 3 bytes para que todas arranquen en el usuario 0. Otro parche, del mismo largo, cambia el mensaje `MP/M II V2.0` por `MP/M II 2.0 ZEPHYRUS 1.2`; `build.sh` hace lo mismo con el título de `MPMLDR`.
- **`mkspr.py`** agrega un byte si el código mide un múltiplo exacto de 128: GENSYS reubica mal esos módulos (ver `gensys.txt` en cpm.z80.de). También cuida que la parte común del XIOS quede en C000 o más arriba: GENSYS pone el módulo debajo de XDOS alineado a 256 bytes, así que si el redondeo la empuja más abajo, agrega relleno en la parte con bancos. La parte común no puede pasar de 2560 bytes; `build.sh` avisa si no cabe.
- **La caché de disco** usa las páginas de RAM que no son de ningún banco ni la común (4 páginas con 512 KB de RAM). Guarda bloques de 512 bytes de la SD, asociativa de 2 vías, en la parte del XIOS con bancos. La página de la caché se pone un momento en la ventana 0, con las interrupciones apagadas de 64 en 64 bytes para no perder caracteres. Las escrituras van a la SD en el acto y también a la caché.
- **El disco en RAM (G:)** usa las páginas que quedan después de la caché (9 con 512 KB). Con menos de 16 páginas tiene bloques de 1 KB y 64 entradas de directorio; con 16 o más, bloques de 2 KB y 128 entradas. `SYSTEMINIT` lo crea vacío.
- **La salida de las consolas** va a un búfer circular por canal. Si el transmisor está parado, el carácter sale directo; si no, la interrupción de transmisor vacío manda el siguiente. Con el búfer lleno el proceso espera una bandera de MP/M (12 para A, 13 para B), que pone la interrupción al liberar un lugar. Por si se pierde una interrupción, el tic revisa cada canal.
- **Memoria alta:** de FE00 a FFFF, sobre el tope de MP/M, van los búferes de entrada (64 bytes por consola), el búfer de directorio, la pila de las interrupciones, los búferes de salida y los vectores.
- **Impresora a un archivo:** `SYSTEMINIT` busca `A:MPM.CFG` al mismo tiempo que `STARTUP.SUB` y lee su primer registro. Con `LST=` y algo que no sea `B`, toma una página de 16 KB para un anillo: `LIST` deja ahí cada carácter (con la página un momento en la ventana 0) y, si está lleno, espera un tic. El bloque de control está en FFCC-FFD2: modo, página, cabeza, cola y la página de la ventana 2 del banco puesto, que `SELMEM` anota para que `LSTFILE` pueda devolverla. `LSTFILE` pone la página del anillo en su ventana 2, con las interrupciones apagadas, de 64 en 64 bytes. Las órdenes del arranque (`H:LSTFILE` y `H:SUBMIT A:STARTUP`) se entregan por `CONIN`; mientras quedan, `CONST` dice que no hay nada, porque el TMP vacía lo tecleado antes de leer.
- **Errores de la SD:** cada lectura o escritura que falla se reintenta una vez después de iniciar la tarjeta otra vez (CMD0, CMD8, ACMD41, CMD58) y olvidar su caché.
- **La hora al DS1307:** una vez por segundo el XIOS compara la hora de XDOS con la del arranque más los segundos contados. Si difieren en más de 3 s (alguien usó `TOD`), escribe la fecha nueva en el DS1307 por I2C.
- **`RST 30h`** apunta en cada banco a `ZEMU`, en la memoria común, que imita los servicios 0, 4, 5, 6, 10, 11, 28, 31, 34 y 36 de ZIOS. El 10 libera antes la unidad con la función 37 del BDOS.
- **Historial y STARTUP.SUB:** `CONIN` y `CONST` miran si el proceso que corre se llama `Tmp...`. Si es así, guardan cada línea y reproducen la pedida con `^W` (borra la línea con `^X` y la escribe de nuevo). La orden de `STARTUP.SUB` se entrega por `CONIN` sin anunciarla en `CONST`, porque el TMP descarta lo que ve tecleado antes de leer.
- **La SD** usa un driver SPI propio, con los métodos de `zlib/libspi.asm` y un búfer de 512 bytes en la memoria común.
- **El disco en flash** se lee mapeando la página de flash en la ventana 0 por un momento.
- **El directorio y los DPB** van en la memoria común: `READ` copia con el banco del usuario puesto, y los programas leen el DPB con la función 31.

## Construir

Hace falta:
- zmac;
- z80pack de Udo Munk, con `cpmsim/srcsim` y `cpmsim/srctools` compilados: GENSYS corre dentro de `cpmsim`;
- `pip install pexpect`.

```
git clone https://github.com/udo-munk/z80pack ~/z80pack
make -C ~/z80pack/cpmsim/srcsim && make -C ~/z80pack/cpmsim/srctools
apps/mpm/build.sh
```

**Archivos:**
- **Nuestros:** `xios.asm`, `ldrbios.asm`, `rtc.asm`, `zloader.asm`, `baud.asm`, `lstfile.asm`, `mkspr.py` (arma el SPR ensamblando en 0000h y en 0100h), `gensys.py` (responde a GENSYS dentro de cpmsim) e `ibm3740.py` (lee y escribe discos de 8" para cpmsim).
- **De Digital Research** (MP/M II 2.0, distribución libre desde 2001):
  - `dri/` (`GENSYS.COM`, `MPMLDR.COM` y los SPR);
  - `prl/` (las utilidades);
  - vienen de los discos de MP/M II de z80pack.

## Pendiente

- CP/NET con el NUNTIUS y oli.
- La memoria común (C000-FFFF) no se puede achicar con provecho: las ventanas de la placa son de 16 KB, así que los bancos de usuario ya tienen los 48 KB máximos.
