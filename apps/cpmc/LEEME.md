# Programas en C para MP/M II ZEPHYRUS (y CP/M 2.2)

Programas escritos en C con SDCC 4.2 y una biblioteca chica propia (`cpm.c`). Cada uno es un `.COM` que se pasa a la SD con `XFER` (YMODEM: `sb` desde la Mac) y se ejecuta desde A:.

## Los programas

| Programa | Qué hace | Uso |
|---|---|---|
| `VI` | Un editor como vi (ver abajo) | `VI NOTAS.TXT` |
| `MD` | Editor y visor de Markdown, con las teclas de hoy (ver abajo) | `MD LEEME.MD`, `MD -V LEEME.MD` |
| `TOP` | Los procesos de MP/M (consola, segmento, prioridad, estado), el uso de la CPU, la fecha y la hora; se actualiza cada segundo | `TOP` (una tecla sale) |
| `TALK` | Manda un mensaje a otra consola | `TALK 2 hola, ya termine` |
| `CLOCK` | Un reloj grande en la pantalla | `CLOCK` |
| `BENCH` | Mide la CPU (MHz), la criba de Eratóstenes, cuentas de 16 y 32 bits, la consola y el disco (escribe y lee 64 KB) | `BENCH` o `BENCH B:` |
| `MANDEL` | El conjunto de Mandelbrot en colores, con aritmética de punto fijo | `MANDEL` |
| `LIFE` | El juego de la vida de Conway, 78 × 22 | `LIFE` |
| `TETRIS` | Flechas o WASD/IJKL; arriba gira, espacio la deja caer, P pausa, Q sale | `TETRIS` |
| `SNAKE` | La víbora: come los `*` sin chocar | `SNAKE` |
| `CAT` | Muestra archivos de texto seguidos, sin pausas | `CAT NOTAS.TXT`, `CAT *.ASM` |
| `MORE` | Un archivo de texto por pantallas (espacio, RETURN, Q) | `MORE LEEME.TXT` |
| `GREP` | Busca un patrón con el motor de grep-milla de Semilla (`.` `* + ?` `^ $` `[a-z]` `[^...]` `\c`); `-N` números de línea, `-V` las que no, `-C` cuántas, `-L` los archivos. Escrito en la línea no distingue mayúsculas; con `?` lo pide por teclado y sí las distingue | `GREP -N ^ORG *.ASM`, `GREP ? *.TXT` |
| `WC` | Líneas, palabras y caracteres | `WC *.TXT` |
| `CMP` | Compara dos archivos byte a byte | `CMP A.COM B:A.COM` |
| `HEXDUMP` | Un archivo en hexadecimal y ASCII, desde un desplazamiento | `HEXDUMP PIP.COM 100` |
| `I2CSCAN` | El mapa del bus I2C, la hora del DS1307 y su RAM; escribe en la RAM libre (18-3F) | `I2CSCAN`, `I2CSCAN T 20 HOLA`, `I2CSCAN W 18 01 02`, `I2CSCAN Z` |
| `SHA256` | La suma SHA-256, con el formato de `sha256sum` | `SHA256 *.COM`, `SHA256 -T NOTAS.TXT` |
| `ZIP` | Hace un `.ZIP` con deflate | `ZIP COPIA *.ASM *.COM`, `ZIP -T TEXTOS *.TXT` |
| `UNZIP` | Saca los archivos de un `.ZIP` (guardados o con deflate, también los hechos en la Mac) y comprueba el CRC | `UNZIP COPIA`, `UNZIP -L COPIA`, `UNZIP COPIA B:` |

`TOP` (el uso de la CPU) y `TALK` usan los servicios 44 y 45 del XIOS: necesitan el `MPM.SYS` de noviembre de 2026 o posterior. `TOP`, `TALK` y `CLOCK` solo andan en MP/M; los demás también en CP/M 2.2.

## Los filtros de Semilla

Las utilidades de C-milla del proyecto Semilla (`semilla/*.c`), compiladas con SDCC casi sin cambios. Allá son filtros de la entrada a la salida, con las opciones en la primera línea; `filtro.c` les arma eso desde la línea de órdenes de CP/M:

```
PROG [opciones] [archivo...] [>salida]
```

- Lo que nombra un archivo que existe (con `*` y `?`) es la entrada, uno detrás de otro; sin archivos se lee la consola, línea por línea, y `^Z` al principio de una línea termina.
- Lo demás son las opciones. CP/M pasa la línea en mayúsculas: las que empiezan con `-` pasan a minúsculas (`-R` es `-r`), el resto queda en mayúsculas.
- `?` pide las opciones por teclado (`Options:`), con minúsculas, comillas y espacios tal cual: hace falta para `AWK` y para `SED` o `TR` con minúsculas.
- `>ARCH` manda la salida a un archivo (CR LF y relleno con `^Z`).

| Programa | Como en Linux | Ejemplo |
|---|---|---|
| `SORT` | `sort` (`-r`, `-u`) | `SORT -R NOMBRES.TXT >ORDEN.TXT` |
| `UNIQ` | `uniq` (`-c`) | `UNIQ -C ORDEN.TXT` |
| `TR` | `tr SET1 SET2`, `tr -d SET` | `TR -D AEIOU TEXTO.TXT`, `TR ? TEXTO.TXT` → `a-z A-Z` |
| `CUT` | `cut -dX -fLISTA` | `CUT -D, -F1,3 DATOS.CSV` |
| `HEAD`, `TAIL` | `head -n N`, `tail -n N` | `TAIL -N 5 LOG.TXT` |
| `REV`, `TAC`, `NL` | `rev`, `tac`, `nl -ba` | `NL PROG.ASM` |
| `OD` | `od -A x -t x1 -v` | `OD DATOS.BIN` |
| `BASE64` | `base64`, `base64 -d` | `BASE64 PROG.COM >PROG.B64`, `BASE64 -D PROG.B64 >PROG.COM` |
| `CKSUM` | `cksum` (CRC de POSIX y tamaño) | `CKSUM PROG.COM` |
| `FACTOR` | `factor` (32 bits) | `FACTOR 360 65537` |
| `SEQ` | `seq` | `SEQ 1 2 10` |
| `SED` | `sed s/RE/repl/[g]` (`&` es lo casado) | `SED S/ALFA/BETA/G T.TXT`, `SED ? T.TXT` |
| `AWK` | un awk chico: campos, `NF` `NR`, `BEGIN` `END`, `/re/`, `if` `while` `for` `for (k in a)`, arreglos, `length` `substr` `index` `int` `split` | `AWK ? DATOS.TXT` → `{s+=$3} END{print s/NR}` |
| `CALC` | calculadora de 16 bits con signo | `CALC 12+30*2`, o `CALC` y una expresión por línea |
| `PRIMOS`, `HANOI`, `VIDA` | las demostraciones de Semilla | `PRIMOS` |

Se probaron en el emulador contra las herramientas de Linux, byte a byte, con un archivo de 43 líneas: `SORT` (y `-r`, `-u`), `UNIQ -C`, `TR -D`, `CUT`, `HEAD`, `TAIL`, `REV`, `NL`, `TAC`, `OD`, `BASE64` (ida y vuelta), `CKSUM`, `FACTOR`, `SEQ` y `SED` dan lo mismo que en Linux, y `AWK` da lo mismo que `awk` en 8 programas de prueba. En `AWK` los números son `float` (en SDCC el `double` es de 32 bits): unos 7 dígitos, y algunos límites más chicos que en Semilla (líneas de 256, cadenas de 40, 200 tokens; ver el principio de `semilla/awk.c`).

Cambios a las fuentes de Semilla, todos para SDCC: prototipos al principio de `awk.c` y `calc.c` (SDCC no acepta llamar sin declarar), un cast en el `qsort` de `sort.c`, `%lu` en `cksum.c` y `factor.c` (allá el `int` era de 32 bits), `S` y `G` en mayúscula en `sed.c`, los límites de `awk.c` bajo `#ifdef __SDCC`, y `hanoi.c` y `primos.c` pasados del C de 1980 a funciones con prototipo. Se compilan con `mks.sh`.

## Más de Semilla

- **`SBASIC`**: SEMILLA BASIC, escrito en Tallo y compilado a Z80 por Semilla (`ejemplos/basic.tl`). Usa solo la consola de CP/M. `SBASIC`, después `LIST`, `RUN`, `NEW` y líneas numeradas.
- **`extra/ZEXDOC.COM`**: el ejercitador de instrucciones del Z80 (Frank Cringle, GPL; la copia de github.com/agn453/ZEXALL). Prueba 67 grupos de instrucciones contra el CRC de un Z80 real. En MP/M a 7,37 MHz tarda un par de horas: conviene correrlo en otra consola (`^D` para dejarlo atrás, o desde otra terminal).

## MD

Editor de Markdown sin modos, con las teclas de los editores de hoy, y una vista formateada. Terminal ANSI de 80 columnas en UTF-8 (el de la Mac): las tildes y los `ñ` se ven y se guardan tal cual.

- **Teclas:** flechas, Inicio, Fin, RePág, AvPág; `^S` guarda, `^O` guarda como, `^Q` sale (pregunta si hay cambios), `^F` busca (sin distinguir mayúsculas; Enter vacío repite), `^G` va a una línea, `^K` corta la línea (varias seguidas se juntan), `^U` pega, `^Z` deshace (varias veces), `^P` vista formateada, `^L` redibuja, `^A` y `^E` principio y fin de la línea. Tab pone espacios hasta la columna múltiplo de 4.
- **Edición:** las líneas largas se parten en la pantalla (no en el archivo); arriba y abajo van por filas de pantalla. Se marcan en colores los títulos (`#`, un color por nivel), los bloques de código, las citas, las reglas, las marcas de lista, la **negrita**, la *cursiva* (subrayada), el `código` y los enlaces. Enter sigue una lista (`-`, `*`, `+`, `1.` con el número siguiente, y las citas `>`); Enter en un punto vacío termina la lista.
- **Vista (`^P`, o `MD -V archivo` para solo mirar):** títulos con raya debajo, párrafos acomodados a 80 columnas, `•` en las listas (con sangría para las anidadas), citas con `│`, bloques de código en verde, tablas con las columnas alineadas, reglas, enlaces con la dirección entre `< >`, negrita, cursiva y código. Se mueve con las flechas, RePág/AvPág, Inicio/Fin; `Q` vuelve.
- En MP/M caben unos 23 KB de texto. Guarda en un `.$$$` y después le cambia el nombre, con CR LF y `^Z`, igual que VI.
- Al correr la pantalla una fila usa una región de desplazamiento (`ESC[1;21r`), así no toca la barra, la ayuda ni la línea de estado de MP/M.

## VI

Un editor como vi para terminal ANSI de 80 columnas. El texto va en memoria: en MP/M caben unos 21 KB (en CP/M 2.2, más). Filas 1 a 22: el texto; la 23: mensajes y órdenes.

- **Moverse:** `h j k l` y flechas, `w b e`, `0 ^ $` (Inicio, Fin), `G`, `gg`, `NG`, `H M L`, `f F t T` con `;` y `,`, `%`, `^F ^B` (RePág, AvPág), `^D ^U ^E ^Y`. Cuentas: `5j`, `3w`.
- **Cambiar:** `i a I A o O` (con sangría automática), `x X r ~ J`, `dd D C s S cc`, `d c y` con cualquier movimiento (`dw`, `c$`, `y3j`, `dG`, `d%`), `yy Y p P`, `u` (deshacer; otra vez, rehacer), `.` (repetir el último cambio).
- **Buscar:** `/texto`, `?texto`, `n N` (distingue mayúsculas).
- **Órdenes:** `:w [archivo]`, `:q`, `:q!`, `:wq`, `:x`, `ZZ`, `:e archivo`, `:e!`, `:r archivo`, `:N` (ir a la línea), `:$`, `:[rango]d`, `:[rango]s/viejo/nuevo/[g]` con rango `N`, `N,M`, `.`, `$` o `%`. `^G` dice dónde se está y cuánto queda libre; `^L` redibuja.
- Guarda en un `.$$$` y después lo cambia de nombre: si el disco se llena, el archivo de antes queda. Escribe CR LF y rellena con `^Z`.
- Las líneas largas no se parten: la pantalla se corre a los lados.
- Lee el teclado con BDOS 6 y escribe con BDOS 6: BDOS 2, 9 y 11 se llevan teclas a un búfer que BDOS 6 no ve (pasaba al pegar texto o con `.`).

## ZAS

Ensamblador Z80 con los mnemónicos de Zilog (`LD A,(HL)`, `DJNZ`, `LDIR`, IX/IY), para CP/M 2.2 y MP/M II. Dos pasadas; saca el `.COM` directo, sin `LOAD`.

```
ZAS archivo[.Z80] [-L] [-H]
```

- Sin extensión busca `.Z80` y luego `.ASM`. Saca `archivo.COM` con los bytes desde el primer `ORG` (100h si no hay) hasta el último; `-L` deja el listado en `archivo.PRN` (dirección, hasta 4 bytes, la línea; `*` donde hubo error) y `-H` también `archivo.HEX` (Intel). Con errores no deja el `.COM`.
- **Instrucciones:** todas las del Z80, también las de IX/IY, `(IX+d)`, las no documentadas `IXH IXL IYH IYL` (o `HX LX`, `XH XL`), `SLL`, `IN F,(C)` y `OUT (C),0`.
- **Directivas:** `ORG`, `EQU`, `DEFL`, `=` o `SET` (redefinibles), `DB DEFB DEFM DM`, `DW DEFW`, `DS DEFS` (`DS n,relleno`), `END`, `IF ELSE ENDIF` anidados, `INCLUDE archivo` (hasta 3 niveles). `TITLE`, `PAGE`, `.Z80`, `NAME` y `LIST` se saltan.
- **Expresiones:** números `123`, `0FFH`, `$FF`, `0xFF`, `1010B`, `%1010`, `17Q`, `'A'`; `$` = la dirección de la línea; `+ - * / %` (`MOD`), `& | ^ ~` (`AND OR XOR NOT`), `<< >>` (`SHL SHR`), `HIGH`, `LOW`, comparaciones `= <> < > <= >=` (verdadero = 0FFFFh) y paréntesis. Sin distinguir mayúsculas; nombres de hasta 31 caracteres.
- **Etiquetas:** en la columna 1, con o sin `:`, o con `:` en cualquier lugar. Si la palabra de la columna 1 es una instrucción o directiva y no lleva `:`, se toma como instrucción.
- **Comprobado:** las 705 formas de instrucción del archivo de prueba salen igual que con `z80asm` en Linux, y seis programas del repositorio (`XFER`, `RTC`, `VC`, `BAUD`, `SETBOOT`, `LSTFILE`, escritos para zmac) salen byte a byte iguales. `XFER` (1179 líneas) se ensambla en unos 16 s a 7,19 MHz.
- No tiene macros ni archivos relocalizables: para eso están `MAC`, `RMAC` y `LINK` de Digital Research (mnemónicos 8080). Ejemplo: `HOLA.Z80`.
- Para depurar lo ensamblado: `ZDB` (`apps/zdb`), que desensambla con la misma sintaxis.

## ZCALC

Versión 1.0. Hoja de cálculo para CP/M 2.2, CP/M 3 y MP/M II, en una terminal ANSI de 80×24. Se maneja como las hojas de 1979: el cursor recorre la cuadrícula, lo que se escribe va a la celda y las órdenes empiezan con `/`. El código es propio; de aquellas hojas solo toma la forma de manejarla.

```
ZCALC [archivo[.ZC]]
```

- **Hoja:** 63 columnas (`A`–`BK`) × 254 filas. Pantalla: fila 1 la celda y su contenido (a la derecha la memoria libre y `!` si falta recalcular), fila 2 la línea de edición y los mensajes, fila 3 las letras de las columnas y abajo 21 filas.
- **Números:** decimales de 9 cifras (mantisa de 32 bits y exponente de 10), así que 0,1 + 0,2 da exactamente 0,3 y los centavos suman bien. Van de 10⁻⁹⁹ a 10⁹⁹.
- **Mover:** flechas o `^E ^X ^S ^D`, `RePág`/`AvPág` (o `^R ^C`) de a 20 filas, `Inicio` a A1, `>` a una celda.
- **Escribir:** lo que empieza con una cifra, `.`, `+`, `-`, `(`, `@`, `=` o `$` es un valor o una fórmula; lo demás es texto (con `"` delante, texto aunque parezca número). `Enter` o una flecha lo guardan (la flecha además mueve); `ESC` cancela. Al escribir una fórmula, una flecha después de un operador, `(`, `,` o `:` **señala** celdas: la referencia se va escribiendo sola.
- **Fórmulas:** `+ - * / ^` (potencia entera), `= <> < > <= >=` (dan 1 o 0), paréntesis, referencias `A1` o fijas `$A$1`, `A$1`, rangos `A1:B5` (o `A1...B5`). Funciones: `@SUM @AVG @MIN @MAX @COUNT` (listas y rangos), `@LOOKUP(x,rango)` (la última celda del rango con valor ≤ x; da la de al lado o la de abajo), `@ABS @INT @ROUND(x,n) @SQRT @MOD(a,b) @IF(c,a,b) @AND @OR @NOT @PI @NA @ERROR @ISNA @ISERROR`. El `@` es opcional. Un error da `ERROR`, una referencia circular también.
- **Órdenes:** `/B` borra la celda, `/C` limpia la hoja, `/D` y `/I` borran o insertan una fila o columna (las fórmulas se ajustan; una referencia a lo borrado queda `#REF`), `/E` edita la celda, `/F` formato de la celda (`D` el global, `G` general, `I` entero, `$` dos decimales, `0`–`9` decimales, `*` gráfico de asteriscos, `L`/`R` alineación, `W` ancho de la columna), `/G` lo global (`C` ancho, `F` formato, `R` recálculo automático o manual con `!`), `/M` mueve un bloque (las fórmulas que lo usan lo siguen), `/R` replica (copia con las referencias relativas corridas; una celda a un rango, una columna a varias columnas, una fila a varias filas), `/T` títulos (fija las filas de arriba o las columnas de la izquierda del cursor), `/-` texto repetido (`/-=` hace una raya), `/P` imprime un rango en la impresora o en un archivo `.PRN`, `/A` muestra la versión y la memoria libre, `/S` carga, guarda, exporta `.CSV` (`X`) o sale (`Q`), `/Q` sale, `?` ayuda.
- **Archivos `.ZC`:** texto, una línea por celda (`B4|03|1500000`: celda, formato en hex y lo escrito), más el ancho y formato globales (`G`) y los anchos de columna (`W`). Se pueden leer y escribir a mano. `EJEMPLO.ZC` es un presupuesto mensual.
- **Memoria:** con MP/M quedan unos 10 KB para celdas: unas 350 fórmulas o 600 números (un número ocupa unos 18 bytes, una fórmula de 25 a 40). Con CP/M hay unos 3 KB más.
- **Por dentro:** las fórmulas se guardan compiladas (referencias de 4 bytes, números de 6) y se vuelven texto para mostrarlas y guardarlas. El recálculo sigue las referencias (cada celda se calcula una vez por recálculo y antes que las que dependen de ella). La aritmética de 32 y 64 bits está en ensamblador (`zcalc_a.s`). Una cadena de 200 fórmulas encadenadas se recalcula y redibuja en unos 2 s.

## Detalles

- **Archivos de CP/M y tamaños exactos.** CP/M guarda los archivos en registros de 128 bytes y no sabe dónde terminan. `SHA256` y `ZIP` toman el archivo entero; con `-T` (texto) cortan en el primer `^Z`. Para comprobar en la Mac un archivo recibido por XMODEM, que llega con relleno, conviene `SHA256 -T` si es texto, o comparar con la suma del archivo rellenado.
- **`ZIP`:** LZ77 con ventana de 4 KB y los códigos de Huffman fijos de deflate; `-1` más rápido, `-9` busca más, `-0` sin comprimir. Si comprimido sale más grande, lo guarda sin comprimir. El `.ZIP` termina justo al final del último registro (el relleno va en un campo extra del directorio), así `unzip` en la Mac no se queja. La fecha sale del reloj de MP/M. Comprime unos 1,2 KB por segundo a 7,37 MHz.
- **`UNZIP`:** inflate completo (bloques guardados, fijos y dinámicos, ventana de 32 KB). Los nombres pasan a 8.3 en mayúsculas sin carpetas (`docs/leeme_largo.markdown` → `LEEME_LA.MAR`); el último registro se rellena con `^Z`. Pregunta antes de reemplazar (`-O`: no pregunta). Necesita 46 KB de TPA (MP/M tiene 47). Saca unos 4,5 KB por segundo.
- **`SHA256`:** la compresión está en ensamblador (`sha256_a.s`): unos 1,1 KB por segundo a 7,37 MHz.
- **Teclas:** `GREP`, `WC`, `SHA256`, `ZIP` y los que recorren archivos se detienen con `^C`, `Q` o ESC.

## Cómo está hecho

- `crt0.s`: arranca en 100h, toma la pila de la dirección 6, pone a cero los datos y copia los inicializados; `exit` es BDOS 0.
- `cpm.h` / `cpm.c`: BDOS y ZIOS (`RST 30h`), consola (`putch`, `pstr`, `pf` con `%d %u %ld %lu %x %X %s %c`, ancho y ceros), teclado sin esperar, archivos por FCB (secuencial, directo, comodines con `glob`, lectura de a un byte), la línea de órdenes, tics, la hora de MP/M, números al azar y ANSI. La salida a la consola se junta en un búfer de 128 bytes: bajo el MP/M de ZEPHYRUS sale de una vez con el servicio 46 del XIOS, sin pasar por el BDOS (`BENCH` da unos 4900 caracteres por segundo, contra 2660 por el BDOS; `putch` está en asm); en CP/M o con un MP/M sin ese servicio, cada carácter va por el BDOS 6. Para leer, `freadn(f, buf, n)` trae hasta 16 registros con una sola llamada al BDOS (BDOS 44 de MP/M II; en CP/M 2.2, de a uno) y devuelve cuántos leyó; `RD`/`rgetc` (y con ellos `CAT`, `GREP`, `MORE`, `WC` y los filtros de Semilla) leen de a 1 KB, y `CMP`, `SHA256`, `MD` y `VI` también. Para escribir, `fwriten(f, buf, n)` hace lo mismo (0 = bien): la usan la salida de los filtros (`>archivo`), `UNZIP`, `MD` y `VI`. `rgetc` y `putch` están en asm (unos 160 y 90 ciclos por byte). `BENCH` mide las dos formas, de a 128 bytes y de a 1 KB, al leer y al escribir. El búfer se vacía antes de cualquier llamada al BDOS (leer el teclado, la hora, los archivos) y al terminar (`oflush()` lo vacía a mano).
- `crc32.h` + `crc32_a.s`: CRC-32 con tabla, en ensamblador. `unzip_a.s`: los bits y la decodificación de Huffman. `zip_a.s`: los bits de salida, la búsqueda de coincidencias y el corrimiento de las tablas de hash.
- **SDCC 4.2:** `(int32_t)a * b` con `a` y `b` de 16 bits con signo da mal; se usa `mul16()`. Por eso `MANDEL` salía todo de puntos.
- `mk.sh [programa...]` compila (con `--opt-code-size`), enlaza en 0110h y pasa el `.ihx` a `.COM`. Si existe `programa_a.s` lo agrega, y `crc32_a.s` si el programa usa `crc32.h`.

Se probaron en el emulador (`retroemu23`) con MP/M 1.4; los `.ZIP` hechos por `ZIP` se comprobaron con `unzip -t` y los de Python con `UNZIP`.
