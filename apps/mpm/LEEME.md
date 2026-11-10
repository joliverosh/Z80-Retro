# MP/M II 2.0 ZEPHYRUS 1.4

MP/M II 2.0 de Digital Research, el CP/M multiusuario de 1981, adaptado a ZEPHYRUS (corre también en la Z80 CPU Rev 2.2) con ZLoader/ZIOS v6. El XIOS es propio (`xios.asm`) y da el número de versión: 1.4. El resto son los archivos originales de Digital Research, con tres parches pequeños a `XDOS.SPR` (usuario 0, el mensaje de arranque y la pila al terminar un programa) y el título del cargador.

Probado en el emulador de la placa (`retroemu23`) con la v6 real. Funcionan:
- el arranque;
- `DIR`, `STAT`, `TYPE`, `PIP`, `ERA`, `MPMSTAT` y `TOD`;
- programas `.COM` y `.PRL`;
- MBASIC con los juegos;
- las cinco consolas a la vez, en bancos distintos: cuatro virtuales en la SIO A (Ctrl-F1..F4) y la SIO B;
- tarjetas SDSC y SDHC;
- lo que MP/M escribe en la SD se lee después desde CP/M 2.2.

**Probado también en la placa real** (Z80 CPU Rev 2.2, flash MX29F040, 8/11/2026): arranca, toma la hora del DS1307 y `TOD` la muestra.

**La 1.3 en la placa real** (9/11/2026): arranca con 7 bancos, 64 KB de caché y G: de 48 KB; `DIR H:` y `MPMSTAT` salen completos con la salida por interrupción; `TOD` da la hora del DS1307; PI1K desde G: calcula los 1000 decimales en 27 s; PRIMOS tarda 7 s; `H:ZLOADER` vuelve a ZLoader sin RESET.

**La 1.4 en la placa real** (9/11/2026): Ctrl-F1..F3 cambian de consola y los programas corren a la vez en varias (PI1K y otro). Lo de la segunda tanda (historial, atributos, línea de estado ampliada, `H:VC`, `CONSOLE4=`, `H:XFER`, SD más rápida) está probado en el emulador.

**Actualizar por la SD en la placa real** (9/11/2026): `H:XFER R A:MPM.SYS` con picocom `--flow h` pasó los 322 bloques con 5 reintentos (844 BPS; sin control de flujo, 2 o 3 reintentos por bloque), y `H:MPMLDR` arrancó ese `MPM.SYS` desde A:. RTS y CTS tienen que ir cruzados entre el adaptador y la placa: con `--flow h` y sin cruzar, el teclado no hace nada. Al pegar texto en la placa real, con el teclado por `RAWQ` y `KDRAIN`: 6 de 8 líneas de 66 caracteres llegaron enteras y en las otras faltaron 2 letras seguidas (el despachador de MP/M, con las interrupciones apagadas, coincide con la llegada; el FTDI manda un par más después de que baja RTS). Se deja así.

**La 1.4** (9/11/2026). Novedades:
- **consolas virtuales como en Linux**: la SIO A tiene cuatro consolas (0-3), cada una con su pantalla, y Ctrl-F1..F4 elige la que se ve;
- **línea de estado** en la fila 24 (`STATUS=ON` en `A:MPM.CFG`);
- **`A:MPM.CFG` ampliado**: impresora, línea de estado, velocidades y mapa de unidades;
- **la RAM del disco en RAM de ZIOS** en el bus de expansión vuelve a MP/M;
- **memoria común liberada**: los discos y su búfer pasaron a la parte con bancos;
- **arreglo de XDOS**: un programa que terminaba con `RET` podía hacer caer a otro (ver *Parches a XDOS.SPR*);
- **historial hacia atrás** en cada consola: Shift-RePag / Shift-AvPag (24 filas guardadas);
- **atributos guardados**: negrita, subrayado, parpadeo, inverso y color del texto se ven igual al volver a una consola;
- **línea de estado** con el programa de la consola que se ve y cuánto trabaja la CPU;
- **`H:VC n`** cambia de consola desde un programa o un SUBMIT; **`CONSOLE4=`** en `A:MPM.CFG` deja la SIO B como terminal, sin consola o la vuelve una quinta consola virtual (Ctrl-F5);
- **`H:XFER`**: archivos por XMODEM desde y hacia el PC, sin sacar la SD;
- **la SD lee un 31 % más rápido** (bucle de SPI desenrollado);
- **más memoria común libre**: la fecha y el I2C pasaron a la parte con bancos;
- **MP/M se actualiza desde la SD**: si A: tiene `MPM.SYS`, el cargador usa ese y no el de la flash.

**Tercera tanda de la 1.4** (9/11/2026, probada en el emulador):
- **`H:XFER` más rápido y con YMODEM**: bloques de 1K (`sx -k`), varios archivos de una vez con su nombre (`sb` / `rb`), CRC con tabla y sin dormir un tic por bloque;
- **escrituras en la SD agrupadas**: el bloque de 512 bytes en curso va a la tarjeta al pasar a otro (el directorio, en el acto), y un bloque recién asignado no se lee antes de escribirlo: copiar un archivo de 40 KB pasa de 328 a 94 escrituras;
- **`H:SETBOOT`** graba el cargador de `BOS 5` en A: desde MP/M (lo que antes era `L` + `WI` en ZLoader);
- **la consola 4 en modo crudo** (XFER por la SIO B) va al mismo anillo rápido, y RTS se maneja en las dos SIO;
- **G: sin páginas**: el arranque dice `G: no RAM disk (all memory in use)`;
- **más memoria común libre**: los servicios 10, 11 y 36 de ZIOS y el mapa de unidades pasaron a la parte con bancos (quedan unos 80 bytes);
- **el teclado**: lo que llega por la SIO A va a un anillo de 512 bytes en la interrupción y se procesa después (ver *Cómo está hecho*).

## Qué ofrece

| | |
|---|---|
| Consolas | 5: **0-3 virtuales en la SIO A** (Ctrl-F1..F4 elige la que se ve, como en Linux; cada una guarda su pantalla de 80 x 24 y lo tecleado) y la **4 en la SIO B** (segundo terminal o NUNTIUS). La salida va por interrupción, con un búfer de 32 caracteres por canal: un programa que escribe mucho ya no frena a los demás, y las consolas de atrás nunca esperan |
| Historial de pantalla | **Shift-RePag / Shift-AvPag** (o Ctrl-\\ U / D) miran 12 filas hacia atrás o adelante en la consola que se ve; se guardan 24 filas además de las que se ven. Cualquier tecla o salida vuelve al día |
| Atributos | Negrita, subrayado, parpadeo, inverso y color del texto se guardan con cada carácter y se repiten al redibujar |
| Línea de estado | Opcional (`STATUS=ON`): la fila 24 muestra cada segundo la versión, las consolas (la que se ve entre corchetes, `*` en las que escribieron algo que no se vio), el programa que escribió último en la consola que se ve, cuánto trabajó la CPU en el último segundo y la fecha y hora |
| Pasar archivos | **`H:XFER R archivo`** recibe y **`H:XFER S archivo`** manda por XMODEM (128 o 1K, CRC o suma); **`H:XFER R`** recibe por YMODEM uno o varios archivos con su nombre y **`H:XFER S A:*.COM`** los manda. Por la consola donde corre |
| Configuración | **`A:MPM.CFG`**: impresora, línea de estado, velocidad de cada SIO, unidades y qué es la consola 4 |
| Velocidad | La que dejó ZIOS. **`H:BAUD`** la muestra y la cambia en el momento, y la guarda en la NVRAM del DS1307 igual que la orden `BAUD` de ZLoader |
| Memoria | **7 bancos** de usuario de 48 KB (0000-BFFF), el máximo de MP/M II, ya con los 512 KB de la placa. La RAM es primero para MP/M: dos páginas para las consolas virtuales (pantallas y atributos) y los bancos; la caché y G: se llevan lo que sobra. La memoria común va de C000 a FFFF. Con RAM de expansión, también se usan las páginas del disco en RAM de ZIOS |
| Discos | **A-P**: las unidades de la SD con el mismo mapa de ZIOS (`SM`) y el mismo formato que CP/M 2.2; H: es el disco en flash, de solo lectura; **G:** es un disco en RAM |
| Disco en RAM | **G:**, solo con las páginas que sobran: 16 KB con los 512 KB de la placa (ninguno si la impresora va a un archivo); con RAM de expansión, hasta 2 MB (976 KB con 1 MB más). Se borra en cada arranque |
| Impresora | **`LST:` sale por SIO B** (la misma línea que la consola 4) **o a un archivo**, según `A:MPM.CFG` |
| Reloj | El tic de ZIOS: canal 1 del CTC, 120 Hz. MP/M recibe 60 tics por segundo |
| Hora | Se toma del DS1307 al arrancar. **Si se cambia con `TOD`, se escribe en el DS1307** |
| Caché de disco | 64 KB con la RAM de la placa, 128 KB con RAM de expansión: el directorio y los programas no se vuelven a leer de la SD. Las escrituras de un mismo bloque de 512 bytes se juntan y van a la tarjeta al pasar a otro bloque o al escribir el directorio (al cerrar un archivo todo queda en la SD) |
| Historial | **`^W`** en el indicador repite la última orden; otro `^W`, la anterior (8 órdenes por consola) |
| Arranque | Si existe **`A:STARTUP.SUB`** (usuario 0), se ejecuta solo al arrancar |
| Servicios de ZIOS | Los programas que llaman a ZIOS con `RST 30h` funcionan: consola (0, 4, 5, 6), mapa de unidades (10, 11), hora (28), tics (31), I2C (34) y datos de una unidad (36). Propios: 40 (ver la consola E, para `H:VC`), 41 (modo crudo de la consola, para `H:XFER`), 42 (lo que espera escribirse, a la SD: `H:ZLOADER`) y 43 (un registro a cualquier pista de una unidad: `H:SETBOOT`) |
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
ZEPHYRUS XIOS 1.4 (OLIVEROS 2026): 5 consoles, 7 banks, drives A-P
64 KB disk cache
G: RAM disk, 16 KB
A:STARTUP.SUB
MP/M II 2.0 ZEPHYRUS 1.4
(C) 1981 Digital Research
0A>TOD
Thu 10/15/26 10:30:02
```

**Actualizar MP/M sin grabar la flash.** El cargador (`MPMLDR`) busca primero `MPM.SYS` en el usuario 0 de A:, la SD; si no está, carga el de la flash (H:). Al arrancar dice cuál: `loading MPM.SYS from drive A:` o `H:`. Para pasar a una versión nueva basta copiar su `MPM.SYS` a A: y volver a arrancar:

- desde MP/M, con `H:XFER R A:MPM.SYS` y picocom (Ctrl-A Ctrl-S); si la transferencia falla o se cancela, `XFER` borra el archivo a medias y el siguiente arranque usa el de la flash;
- o desde CP/M 2.2 o con la SD en el PC, como cualquier otro archivo.

Para volver al de la flash: `ERA A:MPM.SYS` (o `REN A:MPMOLD.SYS=A:MPM.SYS`). Si la entrada de A: está rota (sin la extensión 0), el cargador la salta y usa el de la flash. Si un `MPM.SYS` de A: no arranca, se borra desde CP/M 2.2 (`BOS 1`). El `MPM.SYS` tiene que ser de la misma generación de ZLoader (v6), porque usa sus servicios. Los programas de H: (`XFER`, `VC`, `PIP`…) siguen en la flash; una versión nueva de uno de ellos copiada a A: gana, porque A: se busca antes. El cargador que hace esto es el de esta versión: el de `H:MPMLDR` viene con la flash, y el de `BOS 5` se pone otra vez con `L` + `WI` + `WB` como arriba.

- **El indicador** es `usuario` + `unidad` + `>`. Todas las consolas arrancan en `0A>`. Los programas del disco H: llevan el atributo SYS, así que se ven desde cualquier usuario y unidad.
- **PIP de MP/M es `H:PIP`.** Si en A: hay un `PIP.COM` de CP/M 3, ese gana al escribir solo `PIP` y responde `REQUIRES CP/M 3`.
- **Programas útiles:** `MPMSTAT` muestra procesos, bancos y colas. `ABORT nombre` detiene un programa. `CONSOLE` dice en qué consola estás.
- **Copiar un programa de H:** como es SYS, `PIP` necesita la opción `[R]`: `PIP A:=H:PRIMOS.COM[R]`.
- **Los programas de la placa que llaman a ZIOS** (`RST 30h`) reciben los servicios de consola, hora y tics, así que PRIMOS, BOMBE y PI miden bien el tiempo. `MOUNT` funciona (servicios 10 y 11): cambia el disco virtual de una unidad que ya está en la SD, si nadie tiene archivos abiertos en ella. Los servicios que no están devuelven A=FFh. `FORMAT` no sirve bajo MP/M porque llama al BIOS directamente: los discos nuevos se formatean desde ZLoader.
- **Las unidades I-P** existen si el mapa de ZIOS (`SM`) les asigna un disco de la SD. Un disco nuevo hay que formatearlo una vez desde ZLoader, por ejemplo la I: con `F 0 0 E5` y después `WI 80:I 8000 8000`.
- **`A:STARTUP.SUB`** es un archivo de SUBMIT normal, una orden por línea. Al arrancar, la consola 0 recibe `H:SUBMIT A:STARTUP`. Presionar una tecla mientras corre lo detiene (así es SUBMIT en MP/M).
- **El historial** (`^W`) solo actúa en el indicador `0A>`: dentro de un programa `^W` llega tal cual.
- **Las consolas virtuales.** El terminal de la SIO A muestra una de las consolas 0-3; al arrancar, la 0. **Ctrl-F1, Ctrl-F2, Ctrl-F3 y Ctrl-F4** pasan a la consola 0, 1, 2 o 3: la pantalla se borra y se vuelve a dibujar con lo que esa consola tenía, con el cursor donde estaba. Cada consola tiene su TMP (`0A>`), su historial y lo que se tecleó en ella. Los programas de las consolas que no se ven siguen corriendo y escribiendo en su pantalla guardada, sin esperar al terminal. `MPMSTAT` y `CONSOLE` dan el número de cada una.
  - Las teclas: las terminales de Linux (xterm, GNOME, Konsole) mandan `ESC [ 1 ; 5 P` (hasta `S`) con Ctrl-F1..F4, y picocom las pasa tal cual; con Alt o Mayúsculas en lugar de Ctrl también sirven. Si el escritorio se queda con Ctrl-F1..F4 (KDE las usa para los escritorios), está **Ctrl-\\ seguido de 1, 2, 3 o 4**; Ctrl-\\ dos veces manda un Ctrl-\\ al programa.
  - Un ESC solo llega al programa con 50 ms de demora (el XIOS espera a ver si es Ctrl-F); las flechas y las demás secuencias pasan sin cambio.
  - La pantalla guardada entiende lo que se usa con un terminal ANSI: CR, LF, BS, TAB, `ESC [ fila ; col H`, `ESC [ J`, `ESC [ K`, el movimiento del cursor y `ESC [ ... m` con negrita, subrayado, parpadeo, inverso y color del texto (hasta 3 parámetros). El color de fondo no se guarda.
  - **Mirar hacia atrás:** Shift-RePag sube 12 filas y Shift-AvPag baja 12 (también con Ctrl o Alt, o con **Ctrl-\\ U** y **Ctrl-\\ D**). Cada consola guarda 24 filas además de las que se ven. Mientras se mira hacia atrás el cursor no se ve y la línea de estado dice `HIST -n`; cualquier tecla o algo que escriba el programa vuelve al día. La terminal de GNOME y xterm usan Shift-RePag para su propio historial: ahí sirve Ctrl-RePag o Ctrl-\\ U.
  - **`H:VC n`** muestra la consola n (1 a 4, o 5): sirve en un `SUBMIT` o desde un programa (servicio 40).
  - **La consola 4** es la SIO B. Con `CONSOLE4=VIRTUAL` en `A:MPM.CFG` es una quinta consola virtual en la SIO A (Ctrl-F5 o Ctrl-\\ 5; cada consola guarda entonces 12 filas hacia atrás en lugar de 24); con `CONSOLE4=OFF` no tiene terminal (lo que escribe se pierde) y la SIO B queda solo para la impresora.
- **La línea de estado** (`STATUS=ON`): la fila 24 queda fija y los programas usan las filas 1-23 (el XIOS fija esa zona de desplazamiento en el terminal). Ejemplo:

  ```
   ZEPHYRUS 1.4 | [1] 2* 3  4  | PRIMOS   | CPU 100% | Mon 2026-11-09 12:23:45
  ```

  Se actualiza una vez por segundo, guardando y reponiendo el cursor (`ESC 7` / `ESC 8`), sin cortar una secuencia que un programa esté mandando. `PRIMOS` es el programa que escribió último en la consola que se ve (en el indicador, `Tmp0`); `CPU` es la parte del último segundo en que la CPU no estuvo libre.
- **`A:MPM.CFG`** (usuario 0) es un archivo de texto que el XIOS lee al arrancar, de hasta 512 bytes. Una opción por línea; lo que empieza con `;` o no se entiende se salta:

  ```
  ; configuracion de MP/M
  LST=B                ; impresora: B (SIO B) o un archivo: LST=A:IMPRESOR.TXT
  STATUS=ON            ; linea de estado en la fila 24 (OFF: sin ella)
  BAUD A=115200        ; velocidad de la SIO A (o B) para esta sesion
  DRIVE C=SD0:12       ; C: = disco virtual 12 de la tarjeta 0 (SD1:n, RAM, FLASH u OFF)
  CONSOLE4=B           ; la consola 4: B (la SIO B), OFF o VIRTUAL (Ctrl-F5)
  ```

  `BAUD` acepta las mismas velocidades que `H:BAUD` y no toca la NVRAM. `DRIVE` cambia el mapa de unidades que dejó ZIOS solo para MP/M: `RAM` es el disco en RAM, `FLASH` el disco en flash y `OFF` deja la unidad sin disco.
- **La impresora** (`LST:`, `^P`, `PIP LST:=archivo`) se elige con `LST=` en `A:MPM.CFG`. `LST=B`, o sin el archivo, la manda a SIO B: si ahí hay un terminal, la salida aparece en él. `LST=A:IMPRESOR.TXT` (cualquier nombre, con o sin unidad; sin unidad es A:) la guarda en ese documento. Lo impreso se agrega al final, así que el archivo crece hasta que lo borres. Al arrancar se ejecuta solo `H:LSTFILE`, que queda corriendo suelto (ocupa un banco) y pasa lo impreso al archivo cada medio segundo. Lo cierra tras 2 s sin impresión: mientras se imprime, `TYPE` responde `File Currently Open`; hay que esperar un momento.
- **`H:BAUD`** sin parámetros muestra la velocidad guardada de cada canal; `H:BAUD B 9600` la cambia y la guarda. Velocidades: 230400, 115200, 9600, 4800, 2400, 1200, 600 y 300 (con la CPU a 14,7456 MHz, el doble). Las de 9600 o menos usan el CTC: el puente del reloj de la SIO tiene que estar en CLK0_OUT (P6 para el canal A, P3 para el B), y los dos canales comparten esa constante. El mismo `BAUD.COM` funciona en CP/M 2.2 (allí cambia la velocidad con el servicio 32 de ZIOS; bajo MP/M programa la SIO directamente).
- **`H:XFER`** pasa archivos por XMODEM o YMODEM por la consola donde corre, que tiene que ser la que se ve en el terminal (o la 4, en la SIO B). Con picocom en oli (hace falta `lrzsz`):

  ```
  sudo apt install lrzsz
  picocom -b 115200 --flow h --send-cmd "sx -vv" --receive-cmd "rx -vv" /dev/ttyUSB0
  ```

  - **Del PC a la placa, un archivo:** en MP/M `H:XFER R A:ARCHIVO.EXT`; en picocom Ctrl-A Ctrl-S y el nombre del archivo. Con `-k` delante del nombre (`-k /home/oliveros/MPM.SYS`) sx manda bloques de 1K: va varias veces más rápido, porque cada bloque espera su respuesta y el FTDI la demora.
  - **Del PC a la placa, varios a la vez (YMODEM):** picocom abierto con `--send-cmd "sb -vv -k"`; en MP/M `H:XFER R` (o `H:XFER R B:` para otra unidad); en picocom Ctrl-A Ctrl-S y los nombres separados por espacios. Cada archivo queda con su nombre en mayúsculas, cortado a 8.3, y del tamaño que tenía (redondeado a 128 bytes).
  - **De la placa al PC, un archivo:** en MP/M `H:XFER S A:ARCHIVO.EXT`; en picocom Ctrl-A Ctrl-R y el nombre con que se guarda.
  - **De la placa al PC, varios (YMODEM):** con comodines, `H:XFER S A:*.COM`; en picocom con `--receive-cmd "rb -vv"`, Ctrl-A Ctrl-R (sin nombre: llegan con el suyo, en minúsculas).
  - **Más rápido todavía** en oli: `echo 1 | sudo tee /sys/bus/usb-serial/devices/ttyUSB0/latency_timer` (el FTDI espera 16 ms antes de pasar al PC lo poco que llega, como cada respuesta de XMODEM).
  - **`--flow h`** (RTS/CTS) hace falta para que no se pierdan bytes: mientras MP/M cambia de proceso, con las interrupciones apagadas, el XIOS baja RTS y el PC espera. Sin él funciona, pero con reintentos (`Retry 0: NAK on sector` en sx). ZLoader también usa RTS, así que el mismo picocom sirve para todo.
  - Si la transferencia se cancela o falla, el archivo a medias se borra.
  - Mientras dura, los bytes pasan tal cual: no hay Ctrl-F ni línea de estado. Al terminar, la pantalla se vuelve a dibujar y dice cuántos bloques pasaron.
  - Con XMODEM el archivo recibido queda con el último registro completado con lo que mande el otro lado (`^Z`, 1Ah, como es costumbre en CP/M); con YMODEM, con el tamaño que dice el bloque 0.
- **Para volver a ZLoader**: `H:ZLOADER`. Pide confirmación (`Y`), espera a que nadie esté usando el disco, pasa a la SD lo que esperaba escribirse y deja la máquina como después de un RESET. Lo que está corriendo se pierde, pero lo escrito en la SD ya está en la tarjeta.
- **`H:SETBOOT`** graba el cargador (`H:MPMLDR.COM`, u otro archivo: `H:SETBOOT A:MPMLDR.COM`) en los sectores 70h-7Bh de A:, los que carga `BOS 5`. Pide confirmación y toma el disco mientras escribe. La entrada 5 de la tabla de arranque se pone una sola vez en ZLoader (`WB 5 70:A 0100 1800 0100 01 MP/M`); después, cada cargador nuevo se pone con `SETBOOT`.
- **Con RAM de expansión** en el bus (ZEPHYRUS), MP/M la usa sola: la caché sube a 128 KB y G: crece. También recupera las páginas que ZIOS usaba para su disco en RAM (ZIOS no las entrega): las prueba una por una y toma las que guardan lo escrito y no son un espejo de otra. El mensaje de arranque dice cuántos bancos y cuánto G: quedaron.

## Cómo está hecho

Los mensajes que se ven en pantalla (arranque, errores, programas propios) están en inglés; los comentarios de los fuentes y esta documentación, en español.

- **`MPMLDR.COM`** es el cargador de Digital Research con nuestro `LDRBIOS` (`ldrbios.asm`) en 1700h. Corre como programa de CP/M y lee `MPM.SYS` de H: con el servicio 17 de ZIOS.
- **`MPM.SYS`** lo arma `GENSYS` con estas opciones:
  - tope en la página FD: deja libre FE00-FFFF, donde está el puente de ZIOS;
  - 5 consolas (5 TMP), RST 7 para el depurador y 60 tics por segundo; con 5 consolas XDOS empieza en C900;
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
  - junta las páginas libres (las de la placa, las del bus y las del disco en RAM de ZIOS), toma una para las pantallas de las consolas virtuales y decide los bancos: páginas / 3, hasta 7 (con la placa sola ya son 7). Pone ese número de segmentos en SYSDAT+15. Las que sobran van a la caché (8, 4, 2 o 1, potencia de 2), a la impresora si va a un archivo (1) y a G: (el resto, hasta 128);
  - escribe la página cero de cada banco;
  - pone sus rutinas en la tabla de vectores IM 2 de ZIOS: SIO en FFE0-FFEE y CTC en FFF0-FFF6;
  - activa la recepción y la transmisión por interrupción en las dos SIO;
  - averigua con CMD58 si cada tarjeta es SDHC.
- **Parches a `XDOS.SPR`** (los hace `gensys.py` antes de llamar a GENSYS):
  - Digital Research pone a cada consola en el usuario igual a su número (`tmp$pd.disk$slct = i` en `mpm.asm`), así que la B arrancaba en `1A>`. Se cambian 3 bytes para que todas arranquen en el usuario 0.
  - Otro parche, del mismo largo, cambia el mensaje `MP/M II V2.0` por `MP/M II 2.0 ZEPHYRUS 1.4`; `build.sh` hace lo mismo con el título de `MPMLDR`.
  - **La pila al terminar.** Cada programa empieza con la pila en una tabla de XDOS: 20 bytes por segmento de memoria, uno pegado al otro, con la dirección de retorno a "terminar" arriba. Un programa que termina con `RET` (DUMP, por ejemplo) vuelve a una rutina que guardaba AF, BC, DE y HL antes de llamar a la función 143; con eso XDOS bajaba 24 bytes y pisaba la dirección de retorno del segmento de abajo. Si el programa de ese segmento seguía corriendo y después también terminaba con `RET`, saltaba a cualquier parte y MP/M se caía. Pasaba con dos programas a la vez; con 5 consolas, en el emulador, con dos `DUMP` en dos consolas. Terminar no vuelve, así que el parche cambia esos 4 `PUSH` y sus 4 `POP` por `NOP`: la pila baja 16 bytes y queda dentro de lo suyo. Este error también estaba en la 1.3.
- **`mkspr.py`** agrega un byte si el código mide un múltiplo exacto de 128: GENSYS reubica mal esos módulos (ver `gensys.txt` en cpm.z80.de). También cuida que la parte común del XIOS quede en C000 o más arriba: GENSYS pone el módulo debajo de XDOS alineado a 256 bytes, así que si el redondeo la empuja más abajo, agrega relleno en la parte con bancos. Con XDOS en C900 la parte común no puede pasar de 2304 bytes (`XLIM`); `build.sh` avisa si no cabe y también si la parte con bancos queda debajo de 8000 (tiene que estar en la ventana 2 para `BKCALL`).
- **La caché de disco** usa las páginas de RAM que no son de ningún banco ni la común (hasta 8 páginas, 256 bloques). Guarda bloques de 512 bytes de la SD, asociativa de 2 vías, en la parte del XIOS con bancos. La página de la caché se pone un momento en la ventana 0, con las interrupciones apagadas de 64 en 64 bytes para no perder caracteres. Las escrituras van a la caché en el acto y a la SD así:
  - **escritura diferida de BUF**: `WRITE` deja el bloque de 512 en `BUF` con cambios (`BDIRTY`) y `FLCHK`, al principio de `GETBLK`, lo pasa a la tarjeta (`FLUSH`) cuando se pide otro bloque. El directorio (los 128 registros después de la pista de sistema) se escribe en el acto: MP/M manda C = 1 también con los datos, así que el tipo de escritura no sirve para reconocerlo. `CPURGE` (`DSKRESET`) y el servicio 42 (`H:ZLOADER`) también vacían `BUF`;
  - **bloques nuevos sin leer**: MP/M pone el bit 1 de C en el primer registro de un bloque de asignación nuevo (2 KB, 16 registros). Mientras se escriban sus registros en orden (`UNCHK`), el bloque de 512 no se lee antes (`GBNEW`) y su copia vieja en la caché se olvida.
- **El disco en RAM (G:)** usa las páginas que quedan después de la caché (3 con 512 KB). Con menos de 16 páginas tiene bloques de 1 KB y 64 entradas de directorio; con 16 o más, bloques de 2 KB y 128 entradas. `SYSTEMINIT` lo crea vacío.
- **La salida de las consolas** va a un búfer circular por canal. Si el transmisor está parado, el carácter sale directo; si no, la interrupción de transmisor vacío manda el siguiente. Con el búfer lleno el proceso espera una bandera de MP/M (12 para A, 13 para B), que pone la interrupción cuando el búfer baja a 8 caracteres (no a cada uno). Por si se pierde una interrupción, el tic revisa cada canal.
- **Las consolas virtuales** viven en dos páginas de 16 KB, en la parte con bancos del XIOS:
  - `VTPG`: un anillo de 48 filas de 80 por consola (24 que se ven y 24 de historial; 36 con 5 consolas) en 0000-3BFF; el estado de cada consola (cursor, fila de arriba en el anillo, estado de la secuencia ESC, parámetros, atributo actual, filas guardadas); el trozo que se está mandando; lo tecleado en cada consola (64 bytes); la pila de `BKCALL` arriba;
  - `VTAPG`: el atributo de cada carácter, en el mismo lugar que el carácter (va en la ventana 1 durante `BKCALL`, así que el de `(HL)` está en `(HL+4000h)`), y el anillo de 256 bytes del modo crudo de `H:XFER`;
  - `BKCALL` (en la memoria común) llama a una rutina de la parte con bancos desde cualquier banco y desde las interrupciones: pone en la ventana 2 la página del banco 0, en la 0 la de las pantallas y en la 1 la de los atributos, cambia la pila, llama y repone todo (`SELBNK` anota las páginas de las ventanas 1 y 2 antes del `OUT`);
  - `CONOUT` de la consola que se ve deja el carácter en una cola de 32 (FE00) y lo manda a la SIO; la cola pasa a la pantalla de una vez, con una sola llamada al banco 0. Una consola de atrás solo escribe en su pantalla. La salida pesada cuesta alrededor de un 20 % más de CPU que en la 1.3;
  - la interrupción de recepción de la SIO A pasa cada carácter por `KEYIN`, que reconoce Ctrl-F1..F4 y Ctrl-\\ 1..4 y deja lo demás en la consola que se ve. Un ESC espera 6 tics al resto de la secuencia;
  - al cambiar de consola se vacía lo que faltaba mandar y la SIO A "genera" el redibujo: cuando su búfer se vacía, la interrupción lo vuelve a llenar con el siguiente trozo (CAN para cortar una secuencia a medias, `ESC [ 0 m`, la zona de desplazamiento, borrar, cada fila sin los espacios del final y la posición del cursor). Mientras tanto, la consola que se ve espera para escribir;
  - el redibujo manda cada fila en trozos de hasta 100 bytes, con `ESC [ 0 ; ... m` cada vez que cambia el atributo, y al final el atributo actual de la consola;
  - la línea de estado sale igual, una vez por segundo, desde el tic. La fecha se calcula solo cuando cambia el día. Para la CPU, el tic mira si interrumpió a `IDLE`;
  - el modo crudo (servicio 41): la interrupción de recepción de la SIO A pone el byte en el anillo de 256 bytes con solo la ventana 1 cambiada (unos 120 ciclos), sin `BKCALL` ni `KEYIN`; la cabeza y la cola están en la misma página (7CFEh-7CFFh). Por el camino largo no alcanzaba a 115200 baudios (un byte cada 640 ciclos) y la SIO perdía bytes: todo bloque llegaba mal. Además el despachador de MP/M corre con las interrupciones apagadas hasta unos 3400 ciclos, más de lo que aguanta la FIFO de 3 bytes de la SIO: por eso el tic solo despacha a 60 Hz (los tics de en medio vuelven directo al proceso) y, si en el último tic llegó algo en modo crudo (`RXACT`), tampoco despacha ese, así no cae en medio de un bloque. Además, en modo crudo el tic baja RTS de la SIO A (WR5 = E8h) al entrar, y `RAWGET` lo vuelve a subir (EAh) cuando el programa lee: con control de flujo en el PC, la línea se detiene mientras el despachador corre y mientras otro proceso tiene la CPU. `VSNAP` también lo sube, al salir del modo crudo. **Todo lo que llega por la SIO A** va primero al anillo `RAWQ` (256 bytes) en la interrupción, en unos 150 ciclos: `KEYIN` (las teclas de las consolas y el búfer de cada una) tarda unos 1300 ciclos por carácter, el doble de lo que tarda en llegar uno a 115200, y en la interrupción perdía la mitad del texto pegado. `KDRAIN` lo pasa por `KEYIN` de a uno, con las interrupciones prendidas entre uno y otro, cuando un programa pregunta o lee la consola (`CONST`, `CONIN`); el sondeo de MP/M (`POLLDEV`) despierta a quien espera si hay algo pendiente (`RXPEND`), y los tics que no despachan pasan uno por tic aunque nadie lea, para que Ctrl-F ande con un programa ocupado. Con el búfer de la consola que se ve en 60, lo demás espera en `RAWQ` hasta que lean. `VQFL` (la pantalla guardada) va de a 6 caracteres (`VQMAX`) para no tener las interrupciones apagadas mucho rato. El programa manda directo al búfer de la SIO, sin la pantalla guardada.
- **Memoria alta:** de FE00 a FFFF, sobre el tope de MP/M: la cola de la pantalla (FE00), la entrada de la SIO B (FE40), el búfer de directorio (FE80), el paso entre BUF y el DMA (FF00), la pila de las interrupciones (FF40-FF7F; las interrupciones de las SIO también la usan, para no gastar la pila corta del proceso), los búferes de salida, el control de la impresora, el contador de la cola (FFD3) y los vectores.
- **Memoria común:** la fecha (`DAY2YMD`) y el I2C están en la parte con bancos; los servicios 28 y 34 los llaman con `BKCALL` (el 34, un byte cada vez). Las rutinas de disco y BUF están en la parte con bancos (el BDOS las llama con el banco 0 puesto) y copian al DMA de 64 en 64 bytes por FF00. El historial, el búfer de `MPM.CFG` y las tablas de páginas usan la RAM baja del banco 0 (4000-54FF).
- **Impresora a un archivo:** `SYSTEMINIT` busca `A:MPM.CFG` al mismo tiempo que `STARTUP.SUB` y lee su primer registro. Con `LST=` y algo que no sea `B`, toma una página de 16 KB para un anillo: `LIST` deja ahí cada carácter (con la página un momento en la ventana 0) y, si está lleno, espera un tic. El bloque de control está en FFCC-FFD2: modo, página, cabeza, cola y la página de la ventana 2 del banco puesto, que `SELMEM` anota para que `LSTFILE` pueda devolverla. `LSTFILE` pone la página del anillo en su ventana 2, con las interrupciones apagadas, de 64 en 64 bytes. Las órdenes del arranque (`H:LSTFILE` y `H:SUBMIT A:STARTUP`) se entregan por `CONIN`; mientras quedan, `CONST` dice que no hay nada, porque el TMP vacía lo tecleado antes de leer.
- **Errores de la SD:** cada lectura o escritura que falla se reintenta una vez después de iniciar la tarjeta otra vez (CMD0, CMD8, ACMD41, CMD58) y olvidar su caché.
- **La hora al DS1307:** una vez por segundo el XIOS compara la hora de XDOS con la del arranque más los segundos contados. Si difieren en más de 3 s (alguien usó `TOD`), escribe la fecha nueva en el DS1307 por I2C.
- **`RST 30h`** apunta en cada banco a `ZEMU`, en la memoria común, que imita los servicios 0, 4, 5, 6, 10, 11, 28, 31, 34 y 36 de ZIOS. El 10 libera antes la unidad con la función 37 del BDOS.
- **Historial y STARTUP.SUB:** `CONIN` y `CONST` miran si el proceso que corre se llama `Tmp...`. Si es así, guardan cada línea y reproducen la pedida con `^W` (borra la línea con `^X` y la escribe de nuevo). La orden de `STARTUP.SUB` se entrega por `CONIN` sin anunciarla en `CONST`, porque el TMP descarta lo que ve tecleado antes de leer.
- **La SD** usa un driver SPI propio, con los métodos de `zlib/libspi.asm` y un búfer de 512 bytes en la parte con bancos. Los 512 bytes de un bloque se leen y escriben con el bucle desenrollado (`SPIRB`, `SPIWB`): leer pasó de unos 620 a 400 ciclos por byte. No hay lectura anticipada con CMD18: con la SPI por software, pasar el bloque (unos 30 ms) pesa mucho más que la espera de cada orden.
- **El disco en flash** se lee mapeando la página de flash en la ventana 0 por un momento.
- **`H:XFER`** lee los bloques directo del anillo de la SIO A (`RAWBLK`): pide la página con el servicio 41 (B = 4) y la pone en su ventana 1 de a 4 bytes, con las interrupciones apagadas, como hace la interrupción (cabeza en 7CFCh, cola en 7CFEh, datos en 7E00h, 512 bytes); después vuelve a poner su página (`CURPG1`, FFD4h). De a uno por el servicio no alcanzaba para un bloque de 1K a 115200. El CRC va con una tabla de 512 bytes que arma al arrancar, y antes de dormir un tic esperando un byte lo busca 40 veces.
- **El servicio 43** (`H:SETBOOT`) copia el registro del programa a `DIRBF` (con MXDisk tomado nadie más lo usa) y, con `BKCALL`, lee el bloque de 512 a `BUF`, cambia el registro y lo escribe, sin pasar por la caché (`CPYC` prende las interrupciones, y dentro de `BKCALL` no se puede); la copia en la caché, si había, se olvida.
- **El cargador** (`ldrbios.asm`, dentro de `MPMLDR.COM` en 1700h) recorre una vez las 512 entradas del directorio de A: (los registros 512-639, pista 1) con el servicio 17 de ZIOS. Si encuentra `MPM     SYS` en el usuario 0 y la extensión 0 (sin mirar los atributos), su unidad 0 pasa a ser A: con el DPB de la SD (DSM 2015, DRM 511); si no, o si A: no se lee, es H: con el DSM que da el servicio 36. El vector de asignación tiene 256 bytes, en 1901h, fuera de la imagen.
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
- **Nuestros:** `xios.asm`, `ldrbios.asm`, `rtc.asm`, `zloader.asm`, `baud.asm`, `lstfile.asm`, `vc.asm`, `xfer.asm`, `setboot.asm`, `mkspr.py` (arma el SPR ensamblando en 0000h y en 0100h), `gensys.py` (responde a GENSYS dentro de cpmsim) e `ibm3740.py` (lee y escribe discos de 8" para cpmsim).
- **De Digital Research** (MP/M II 2.0, distribución libre desde 2001):
  - `dri/` (`GENSYS.COM`, `MPMLDR.COM` y los SPR);
  - `prl/` (las utilidades);
  - vienen de los discos de MP/M II de z80pack.

## Pendiente

- Probar la 1.4 en la placa real: Ctrl-F1..F4 con picocom, la línea de estado, la consola 4 en la SIO B, `A:MPM.CFG` con `BAUD` y `DRIVE`.
- Consolas por WiFi con el NUNTIUS y CP/NET con oli (cuando el NUNTIUS esté instalado).
- Una consola en la tarjeta de video (cuando esté la tarjeta).
- La memoria común (C000-FFFF) no se puede achicar con provecho: las ventanas de la placa son de 16 KB, así que los bancos de usuario ya tienen los 48 KB máximos.
