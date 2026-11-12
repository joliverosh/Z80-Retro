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
| `ROGUE` | El calabozo de Rogue: baja, pelea, encuentra el Amuleto de Yendor y vuelve a subir (ver abajo) | `ROGUE` |
| `CHESS` | Ajedrez contra el computador o contra otra persona en otra consola (ver abajo) | `CHESS`, `CHESS DUEL` |
| `NAVAL` | La batalla naval entre dos consolas o contra el computador (ver abajo) | `NAVAL`, `NAVAL C` |
| `ZFM` | Administrador de archivos de dos paneles: copiar, mover, borrar, ver, abrir (ver abajo) | `ZFM`, `ZFM A: B:` |
| `ZWRITE` | Procesador de texto con las teclas de WordStar; guarda Markdown (ver abajo) | `ZWRITE CARTA.MD` |
| `ZDATA` | Base de datos de fichas sobre archivos `.DBF` de dBase III (ver abajo) | `ZDATA CLIENTES` |
| `ZBAS` | BASIC estructurado (ver abajo) | `ZBAS`, `ZBAS EJEMPLO` |
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

`TOP` (el uso de la CPU) y `TALK` usan los servicios 44 y 45 del XIOS: necesitan el `MPM.SYS` de noviembre de 2026 o posterior. `TOP`, `TALK` y `CLOCK` solo andan en MP/M, igual que los duelos de `CHESS` y `NAVAL` y el lanzar programas de `ZFM`; los demás también en CP/M 2.2.

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

Versión 1.2. Hoja de cálculo para CP/M 2.2, CP/M 3 y MP/M II, en una terminal ANSI de 80×24. Se maneja como las hojas de 1979: el cursor recorre la cuadrícula, lo que se escribe va a la celda y las órdenes empiezan con `/`. El código es propio; de aquellas hojas solo toma la forma de manejarla.

```
ZCALC [archivo[.ZC|.WKS|.WK1]]
```

Son dos archivos: `ZCALC.COM` y `ZCALC.OVL`, que va en la misma unidad (o en la actual, o en `A:`). En `ZCALC.OVL` están las partes que se usan de vez en cuando (cargar y guardar, las órdenes, la ayuda, los nombres, el gráfico, 1-2-3): se cargan cuando hacen falta en un lugar de 2,75 KB, así queda más memoria para las celdas.

- **Hoja:** 63 columnas (`A`–`BK`) × 254 filas. Pantalla: fila 1 la celda y su contenido (a la derecha la memoria libre y `!` si falta recalcular), fila 2 la línea de edición y los mensajes, fila 3 las letras de las columnas y abajo 21 filas.
- **Números:** decimales de 9 cifras (mantisa de 32 bits y exponente de 10), así que 0,1 + 0,2 da exactamente 0,3 y los centavos suman bien. Van de 10⁻⁹⁹ a 10⁹⁹.
- **Mover:** flechas o `^E ^X ^S ^D`, `RePág`/`AvPág` (o `^R ^C`) de a 20 filas, `Inicio` a A1, `>` a una celda, `^F` busca un texto (en lo escrito y en las fórmulas, desde el cursor), `^U` deshace el último cambio de una celda.
- **Escribir:** lo que empieza con una cifra, `.`, `+`, `-`, `(`, `@`, `=` o `$` es un valor o una fórmula; lo demás es texto (con `"` delante, texto aunque parezca número). `Enter` o una flecha lo guardan (la flecha además mueve); `ESC` cancela. Al escribir una fórmula, una flecha después de un operador, `(`, `,` o `:` **señala** celdas: la referencia se va escribiendo sola.
- **Fórmulas:** `+ - * / ^` (potencia entera), `= <> < > <= >=` (dan 1 o 0; entre textos los comparan sin mirar mayúsculas), `&` (une textos; un número se escribe como en formato general), paréntesis, textos entre comillas (`"total: "`; `""` es una comilla), referencias `A1` o fijas `$A$1`, `A$1`, rangos `A1:B5` (o `A1...B5`), nombres de rango (`/N`). Funciones: `@SUM @AVG @MIN @MAX @COUNT` (listas y rangos), `@LOOKUP(x,rango)` (la última celda del rango con valor ≤ x; da la de al lado o la de abajo), `@ABS @INT @ROUND(x,n) @SQRT @MOD(a,b) @IF(c,a,b) @AND @OR @NOT @PI @NA @ERROR @ISNA @ISERROR`; trigonometría y logaritmos `@SIN @COS @TAN @ATAN @LN @LOG @EXP` (en radianes, unas 8 cifras); finanzas `@PMT(tasa,n,capital)` (la cuota), `@PV(tasa,n,cuota)`, `@FV(tasa,n,cuota)`, `@NPV(tasa,flujos)` (el primero al final del período 1), `@IRR(tasa inicial,flujos)` (0 = 10 %; hasta 48 flujos); fechas como número de días (1 = 1/1/1900) `@DATE(año,mes,día)`, `@TODAY`, `@NOW` (con la fracción del día, del reloj de MP/M o CP/M 3), `@YEAR @MONTH @DAY`; textos `@LEFT(t,n) @RIGHT(t,n) @MID(t,desde,n)` (la primera letra es la 1), `@LEN @UPPER @LOWER @PROPER @TRIM`, `@VALUE(t)` (el número escrito en el texto), `@STRING(x,decimales)`, `@FIND(buscado,t[,desde])` (dónde está, desde 1; ERROR si no está), `@REPEAT(t,n) @CHAR(código) @CODE(t) @EXACT(a,b)`, `@ISSTR @ISNUM`. Una referencia a una celda de texto da el texto (en una cuenta vale 0, y las listas como `@SUM` lo saltan); una fórmula puede dar un texto. El `@` es opcional. Un error da `ERROR`, una referencia circular también.
- **Órdenes:** `/B` borra la celda, `/C` limpia la hoja, `/D` y `/I` borran o insertan una fila o columna (las fórmulas se ajustan; una referencia a lo borrado queda `#REF`), `/E` edita la celda, `/F` formato de la celda (`D` el global, `G` general, `I` entero, `$` dos decimales, `0`–`9` decimales, `*` gráfico de asteriscos, `/` fecha dd/mm/aa, `:` hora hh:mm, `L`/`R` alineación, `W` ancho de la columna), `/G` lo global (`C` ancho, `F` formato, `R` recálculo automático o manual con `!`), `/K` copia un rango al portapapeles y `/V` lo pega con su esquina en el cursor (con las referencias relativas corridas), `/L` protege o desprotege un rango (una celda protegida no se escribe, edita ni borra), `/M` mueve un bloque (las fórmulas que lo usan lo siguen), `/N` nombres de rango (`C` crea o cambia, `D` borra: las fórmulas que lo usaban quedan con las coordenadas, `L` lista; hasta 24; en las fórmulas se escriben como `@SUM(GASTOS)` y siguen al rango si se insertan o borran filas), `/O` ordena las filas de un rango por una columna (`A` ascendente, `D` descendente; las fórmulas de las filas movidas se ajustan), `/R` replica (copia con las referencias relativas corridas; una celda a un rango, una columna a varias columnas, una fila a varias filas), `/T` títulos (fija las filas de arriba o las columnas de la izquierda del cursor), `/W` ventanas (`H` parte la pantalla en dos a la altura del cursor, cada mitad con su posición; `;` pasa de una a la otra; `1` vuelve a una), `/X` gráfico de barras a pantalla completa (los valores, los rótulos y el título; hasta 34 barras, con los negativos hacia abajo), `/-` texto repetido (`/-=` hace una raya), `/P` imprime un rango en la impresora o en un archivo `.PRN`, `/A` muestra la versión y la memoria libre, `/S` carga (un `.ZC`; un `.WKS` o `.WK1` de Lotus 1-2-3; o un `.CSV` con su esquina en el cursor: los números como valores y lo demás como texto), guarda, exporta `.CSV` (`X`), guarda para 1-2-3 (`W`, un `.WKS`) o sale (`Q`), `/Q` sale, `?` ayuda.
- **Archivos `.ZC`:** texto, una línea por celda (`B4|03|1500000`: celda, formato en hex y lo escrito), más el ancho y formato globales (`G`), los anchos de columna (`W`) y los nombres de rango (`N GASTOS $B$4:$B$8`). Se pueden leer y escribir a mano. `EJEMPLO.ZC` es un presupuesto mensual.
- **Lotus 1-2-3:** de un `.WKS` o `.WK1` lee los textos, los números, los anchos de columna y las fórmulas: las que ZCALC sabe escribir (las cuentas, las referencias relativas y fijas, los rangos y las funciones que tiene; `@PMT @PV @FV` cambian el orden de sus argumentos) quedan como fórmulas, y las otras con el valor que traen. Al guardar un `.WKS` van los textos, los números (los dobles de IEEE se arman exactos con enteros de 64 bits) y el valor de cada fórmula, no la fórmula.
- **Memoria:** con MP/M quedan unos 11 KB para celdas: unos 780 números o unas 400 fórmulas (un número ocupa 14 bytes, un texto 10 más sus letras, una fórmula de 20 a 35). Con CP/M hay unos 3 KB más.
- **Por dentro:** las fórmulas se guardan compiladas (referencias de 3 bytes, números de 6, enteros chicos de 2) y se vuelven texto para mostrarlas y guardarlas. El recálculo sigue las referencias (cada celda se calcula una vez por recálculo y antes que las que dependen de ella). En ensamblador (`zcalc_a.s`) están la aritmética, el evaluador, la compilación de fórmulas y su vuelta a texto, el formato de los números y las funciones; las de finanzas, fechas y trigonometría son programas cortos de una pequeña calculadora de registros (16 registros, un byte o dos por instrucción), así ocupan poco. `@LN`, `@EXP` y las trigonométricas tardan menos de 0,3 s. Una cadena de 200 fórmulas encadenadas se recalcula y redibuja en unos 2 s. `mkzcalc.sh` arma los dos archivos (`mk.sh zcalc` lo llama): enlaza `ZCALC.COM` y después cada parte de `zcov*.c` (compilada con `--codeseg OVL --dataseg OVL`) en el lugar `ovlreg`, revisa que no cambie el programa principal ni traiga funciones de biblioteca que este no tenga, y junta las partes en `ZCALC.OVL` con una marca de la versión (`zcovh.s` les pone al principio el salto a `ovl_entry`). Se compila con `--max-allocs-per-node 200000` (unos 5 minutos; con `FAST=1`, sin esa opción). Los textos que se arman al calcular van en un lugar de 400 bytes que se vacía en cada celda; el texto que da una fórmula se guarda en un bloque del heap.

## ZWRITE

Procesador de texto para escribir cartas, informes y notas. Se maneja con las teclas de WordStar y guarda **Markdown**: el archivo es texto que se lee en cualquier parte (y `MD` lo abre), con `**negrita**`, `*cursiva*`, `#` títulos y listas. Los párrafos son líneas largas que la pantalla parte entre palabras.

```
ZWRITE archivo        ZWRITE -V archivo   (solo mirar la vista formateada)
```

- **Moverse:** el diamante `^E ^X ^S ^D` (o las flechas), `^A ^F` palabra anterior y siguiente, `^R ^C` pantalla arriba y abajo, `^W ^Z` corre la pantalla una fila. `^Q` y otra tecla: `S D` principio y fin de la línea, `E X` arriba y abajo de la pantalla, `R C` principio y fin del texto, `F` busca, `A` busca y reemplaza (opciones: `U` sin mirar mayúsculas, `G` en todo el texto, `N` sin preguntar), `Y` borra hasta el fin de la línea, `I` va a una línea; `^L` repite la búsqueda.
- **Cambiar:** `^G` borra la letra, `^T` la palabra, `^Y` la línea; `^V` escribe encima o mete; `^N` parte la línea; `^U` deshace; `^P B` y `^P Y` ponen o quitan negrita y cursiva en la palabra; Enter sigue una lista.
- **Bloques y archivos (`^K`):** `B` y `K` marcan el principio y el fin, `H` lo oculta o muestra, `C` lo copia al cursor, `V` lo mueve, `Y` lo borra, `W` lo escribe en un archivo, `R` lee un archivo en el cursor; `S` guarda y sigue, `D` o `X` guardan y salen, `Q` sale sin guardar (pregunta), `P` imprime.
- **Ver e imprimir:** `^O D` muestra el texto formateado. `^K P` imprime en la impresora o en un `.PRN`: justificado, con páginas, el encabezado y el número de página abajo. Las órdenes de impresión van en comentarios que el Markdown no muestra: `<!-- .page -->` (página nueva), `<!-- .header texto -->`, `<!-- .width 65 -->`, `<!-- .margin 8 -->`, `<!-- .lines 60 -->`, `<!-- .nonumber -->`. En la impresora la negrita se hace pasando dos veces.
- `^J` muestra la ayuda. La línea de estado dice la línea, la columna y los bytes libres.

## ZDATA

Base de datos de fichas sobre archivos `.DBF` de **dBase III**, que también abren Clipper, LibreOffice y Excel. Las fichas quedan en el disco y se leen de a una, así que el archivo puede ser más grande que la memoria.

```
ZDATA [archivo[.DBF]]
```

- **La tabla:** una ficha por fila y los campos en columnas. Flechas (o `^E ^X ^S ^D`) mueven, RePág/AvPág, Inicio/Fin van al primer y al último campo, `^R`/`^C` a la primera y la última ficha. Enter cambia el campo; `A` agrega una ficha; `F` la muestra entera en una pantalla (para editar campo por campo); `Supr` la marca para borrar (`*`) o la desmarca; `P` limpia el archivo de las marcadas.
- **Buscar y filtrar:** `B` busca un texto en el campo del cursor y `^L` sigue buscando; `X` filtra con una condición `CAMPO op valor` (`= <> < > <= >=`, y `$` para "contiene"; los números se comparan como números y las fechas como fechas); `X` con Enter vacío quita el filtro.
- **Ordenar:** `O` ordena el archivo por un campo, de menor a mayor o al revés.
- **Informe:** `I` imprime las fichas que pasan el filtro, con los campos que caben, en la impresora o en un `.PRN`, de 80 o 132 columnas, con título, páginas y la suma de los campos numéricos.
- **Crear:** `N` pide el nombre del archivo y después cada campo: el nombre, el tipo (`C` texto, `N` número, `D` fecha, `L` sí/no), el ancho y los decimales; hasta 32 campos.
- `?` muestra la ayuda y `Q` sale. Los cambios se escriben en el disco al momento. `EJEMPLO.DBF` tiene doce clientes inventados.

## ZBAS

BASIC estructurado para CP/M 2.2, CP/M 3 y MP/M II: los programas se escriben sin números de línea (o con ellos), con bloques, `SUB` y `FUNCTION` con variables locales y recursión. Los números son los de ZCALC: decimales de 9 cifras, así que 0,1 + 0,2 da exactamente 0,3. Los mensajes van en inglés.

```
ZBAS                 el intérprete: se escriben las líneas, RUN, LIST, SAVE...
ZBAS programa        carga programa.BAS, lo corre y vuelve a CP/M
```

Son dos archivos: `ZBAS.COM` y `ZBAS.OVL`, que va en la misma unidad (o en la actual, o en `A:`). En MP/M quedan **unos 11,5 KB** para el programa y sus datos.

- **El intérprete:** una línea con número se guarda en el programa (o lo cambia; un número solo la borra); sin número se ejecuta en el momento. `RUN ["archivo"]`, `LIST [n][-m]`, `EDIT n` (la línea para cambiarla), `AUTO [n[,paso]]`, `DELETE n[-m]`, `RENUM [desde[,paso]]`, `NEW`, `LOAD "archivo"`, `SAVE "archivo"` (texto: se puede escribir con `MD`, `VI` o `ZWRITE`), `FILES`, `CONT` (sigue después de `STOP` o de `^C`/ESC), `TRON`/`TROFF`, `SYSTEM` (vuelve a CP/M). Un programa sin números de línea se numera solo al cargarlo y se guarda sin ellos si no hay `GOTO` a un número.
- **Nombres:** largos, sin distinguir mayúsculas; `$` al final para los textos (`nombre$`). Etiquetas: un nombre con `:` al principio de la línea (`fin:`), para `GOTO`, `GOSUB` y `RESTORE`.
- **Bloques:** `IF ... THEN ... ELSEIF ... ELSE ... END IF` (o en una línea: `IF x THEN PRINT x ELSE GOTO fin`), `FOR i = a TO b [STEP s] ... NEXT`, `WHILE ... WEND`, `DO [WHILE|UNTIL c] ... LOOP [WHILE|UNTIL c]`, `EXIT FOR|DO|WHILE|SUB|FUNCTION`, `SELECT CASE x` con `CASE 1, 3`, `CASE 5 TO 9`, `CASE IS > 10`, `CASE "pera"` y `CASE ELSE`, `END SELECT`.
- **SUB y FUNCTION:** `SUB nombre(a, b$) ... END SUB` se llama con `CALL nombre(1, "x")` (o sin `CALL`); `FUNCTION nombre(n) ... END FUNCTION` da su valor asignándolo a su nombre o con `RETURN valor`. Los parámetros son locales; `LOCAL x, y$` hace locales otras variables. Con recursión.
- **Más sentencias:** `PRINT` (`;` pega, `,` va a la columna siguiente de 14, `TAB(n)`, `SPC(n)`; los números llevan un espacio delante y otro detrás, como en todos los BASIC), `INPUT ["pregunta";] a, b$`, `LINE INPUT a$`, `LET`, `DIM a(10), m$(3, 4)` (hasta 3 dimensiones, desde 0; sin `DIM`, 10), `ERASE`, `READ`/`DATA`/`RESTORE [etiqueta]`, `GOTO`, `GOSUB`/`RETURN`, `ON n GOTO|GOSUB a, b, c`, `SWAP`, `RANDOMIZE`, `CLS`, `LOCATE fila, columna`, `COLOR n`, `SLEEP segundos`, `BEEP`, `STOP`, `END`, `REM` o `'`.
- **Archivos:** `OPEN "archivo" FOR INPUT|OUTPUT|APPEND AS #n` (de 1 a 4), `PRINT #n, ...`, `INPUT #n, a, b$` (campos separados por comas), `LINE INPUT #n, a$`, `EOF(n)`, `CLOSE [#n]`, `KILL "archivo"`.
- **Operadores:** `+ - * / ^` (potencia), `MOD`, `= <> < > <= >=` (verdadero es -1), `AND OR XOR NOT`, `+` también une textos.
- **Funciones:** `ABS INT FIX SGN SQR SIN COS TAN ATN LOG LOG10 EXP RND PI ROUND(x,n) MIN(a,b) MAX(a,b)`; las finanzas de ZCALC `PMT(tasa,n,capital) PV FV`; fechas `DATE(año,mes,día) TODAY NOW YEAR MONTH DAY`, `DATE$` y `TIME$` (del reloj de MP/M o CP/M 3); textos `LEN LEFT$ RIGHT$ MID$(t,desde[,n]) INSTR([desde,]t,buscado) UCASE$ LCASE$ STR$ VAL CHR$ ASC SPACE$ STRING$(n,t) TRIM$ LTRIM$ RTRIM$ HEX$ FORMAT$(x,decimales)`; `INKEY$` (la tecla, sin esperar), `FRE` (memoria libre), `POS` (la columna).
- **Ejemplo:** `EJEMPLO.BAS` (la tabla de un préstamo, las torres de Hanói, una `FUNCTION` recursiva, `SELECT CASE`, una matriz ordenada).
- **Velocidad:** los ocho benchmarks de Rugg/Feldman (Kilobaud, 1977) y la criba de BYTE están en `bench/` (con números de línea, así corren igual en MBASIC). En el emulador, a 7,37 MHz y contando cargar el programa:

  | | BM1 | BM2 | BM3 | BM4 | BM5 | BM6 | BM7 | BM8 | Criba |
  |---|---|---|---|---|---|---|---|---|---|
  | ZBAS | 3,5 s | 6,1 s | 16,0 s | 15,8 s | 16,6 s | 25,2 s | 37,4 s | 19,5 s | 66,7 s |
  | MBASIC 5.21 | 1,8 s | 3,3 s | 7,0 s | 7,0 s | 7,7 s | 13,4 s | 20,5 s | 4,0 s | 40,5 s |

  MBASIC usa números binarios de 7 cifras; los de ZBAS son decimales de 9 (0,1 + 0,2 da 0,3 exacto).
- **Por dentro:** las líneas se guardan compiladas: las palabras en un byte, los números ya convertidos, los textos con su largo y cada nombre como el número de su variable, así al correr no se busca nada. Las variables de texto y las matrices van en un heap que se vacía al cambiar el programa. Lo que no hace falta para correr (compilar las líneas que se escriben, `LIST`, `EDIT`, `LOAD`, `SAVE`, `RENUM`, `FILES`, los mensajes de error) está en `ZBAS.OVL`, en tres partes de 2 a 6 KB: la que hace falta se carga arriba del heap, en una dirección múltiplo de 256 (se corrigen solo los bytes altos de sus direcciones), y queda ahí hasta que el programa necesita el lugar. `mkzbas.sh` arma los dos archivos: enlaza cada parte dos veces (en C000h y en C100h) y de la diferencia saca la lista de lo que hay que corregir, y revisa que el programa principal no cambie. La aritmética es la de ZCALC (`znum_a.s`, `znum.c`).

## ROGUE

El calabozo de Rogue en 80×24: cuartos, pasillos, monstruos (`A`–`Z`, de murciélagos a dragones), pociones y pergaminos que hay que probar para saber qué son, armas, armaduras y comida. Hay que bajar al piso 13 o más abajo, tomar el Amuleto de Yendor (`,`) y volver a subir con él. Cada partida es distinta.

- **Teclas:** `h j k l y u b n` (o las flechas) mueven y en mayúscula corren; caminar hacia un monstruo es pelear; `>` baja la escalera y `<` sube (solo con el amuleto); `i` el inventario, `q` bebe, `r` lee, `e` come, `w` empuña un arma, `W` se pone una armadura, `T` se la quita, `d` suelta, `s` o `.` descansa, `^R` redibuja, `?` la ayuda, `Q` sale.
- Abajo: el piso, el oro, los puntos de vida, la fuerza, la armadura y el nivel de experiencia; y si hay hambre. Los mensajes van arriba (`--More--` si hay varios).

## CHESS

Ajedrez contra el computador, con el tablero en colores.

- **Jugadas:** las casillas de salida y llegada: `e2e4` (o `e2-e4`, `e4xd5`); para coronar algo que no sea dama, la pieza al final: `e7e8n`. Enroque: `O-O` y `O-O-O`. Las blancas en mayúsculas, las negras en minúsculas.
- **Órdenes:** `new` (partida nueva), `undo` (deshace la última jugada de cada uno), `go` (el computador juega con el bando que mueve), `both` (dos personas), `level 1`–`6` (de 1 a 90 segundos por jugada), `flip` (gira el tablero), `duel` (contra otra persona en otra consola), `help`, `quit`. ESC mientras piensa lo hace jugar con lo que tiene.
- **A duelo:** `duel` (o `CHESS DUEL`) en dos consolas de MP/M II, por ejemplo la del terminal y la de la SIO B, o dos consolas virtuales (Ctrl-F1, Ctrl-F2). El primero espera y juega con blancas; el segundo se une y juega con negras, con el tablero girado. Mientras juega el otro, cualquier tecla abre la línea de órdenes: `say texto` (le escribe al otro), `draw` (ofrece tablas, o las acepta si el otro las ofreció), `resign` (abandona), `quit`.
- Conoce el enroque, la captura al paso, la coronación, el mate, el ahogado, la regla de las 50 jugadas y la falta de material.
- **Por dentro:** tablero 0x88 con las listas de piezas de cada bando, búsqueda alfa-beta con profundización iterativa, extensión de los jaques y las capturas al final (las más valiosas con las menos valiosas primero); la evaluación es el material más tablas por casilla, sumada al mover. `attacked` (si una casilla está atacada) está en ensamblador (`chess_a.s`) con una tabla de 239 direcciones. A 7,37 MHz mira unas 350 posiciones por segundo: con el nivel 3 (8 s) ve tres jugadas. `perft N` (orden escondida) cuenta las posiciones a `N` jugadas desde la de ahora, para probar las reglas.

## ZFM

Administrador de archivos de dos paneles, al estilo del Norton Commander. Cada panel muestra una unidad y un usuario (al empezar, los de la consola; `ZFM B: C:` abre otras), con el tamaño de cada archivo y los KB libres.

| Tecla | Qué hace |
|---|---|
| flechas, RePag/AvPag, Inicio/Fin | moverse en la lista |
| Tab (o izquierda/derecha) | el otro panel |
| Espacio o Ins | marca o desmarca; `*` marca todo o nada |
| Enter | abre: `.BAS` con ZBAS, `.ZC` `.WKS` `.CSV` con ZCALC, `.DBF` con ZDATA, `.MD` `.TXT` con ZWRITE, `.SUB` con SUBMIT; `.COM` y `.PRL` se corren (pregunta la orden, para agregar argumentos); lo demás se muestra |
| V o F3 | ver un texto (los primeros 18 KB) |
| E o F4 | editarlo con ZWRITE |
| C o F5 / M o F6 | copiar / mover los marcados (o el del cursor) al otro panel |
| R | renombrar |
| D, Supr o F8 | borrar los marcados (o el del cursor), con confirmación |
| L / U | cambiar la unidad (A-P) / el usuario (0-15) del panel |
| S | volver a leer los directorios |
| ? o F1 | ayuda; Q, ESC o F10: salir |

- Copiar entre usuarios distintos cambia de usuario en cada lectura y escritura (BDOS 32), de a 2 KB. ESC o `Q` detiene la copia y borra la copia a medias.
- Los programas se lanzan con el BDOS 47 (*Chain To Program*): corren en la unidad y el usuario del panel y, al terminar, se vuelve al indicador (no a ZFM).
- **Los KB libres:** el vector de asignación del BDOS 27 no sirve en MP/M II (está en el banco del sistema); ZFM los cuenta en la misma pasada que lee el directorio, sumando los bloques de todas las entradas de todos los usuarios.

## NAVAL

La batalla naval, contra otra persona en otra consola o contra el computador. Cada uno tiene cinco barcos (portaaviones de 5, acorazado de 4, crucero y submarino de 3, destructor de 2) en un mar de 10 × 10, sin tocarse; se dispara por turnos.

- `NAVAL` espera a que alguien corra `NAVAL` en otra consola (`C`: jugar contra el computador); `NAVAL C` juega contra el computador de una vez. El que esperaba dispara primero.
- La flota se reparte sola: `R` otra disposición, Enter listo.
- **Disparar:** las flechas (o una letra y un número: `E5`) y Enter o Espacio. `T` le escribe al otro; `Q` abandona.
- A la izquierda, la flota propia (`#` barco, `X` tocado, `o` agua); a la derecha, el mar del otro (`X` tocado, `#` hundido, `o` agua). Al final se ven los barcos que no se encontraron.
- El computador busca en damero y, cuando toca, sigue la línea del barco.

**Cómo se hablan dos programas** (`duel.h`, que usan NAVAL y CHESS): por un archivo oculto de `A:` usuario 0 (`NAVAL.DAT`, `CHESS.DAT`) que los dos abren en modo sin bloqueo (atributo f5'). El XIOS tiene una sola caché de la SD, así que lo que escribe uno el otro lo lee en el acto. El registro 0 es la sala de espera (quién espera, desde qué consola y a qué hora: el que espera la escribe cada 2 segundos y una espera de más de 10 segundos no vale); hay 4 mesas de dos registros, uno por jugador, con el número del mensaje, el último que se leyó del otro, el tipo y los datos. Cada mensaje espera a que el otro lea el anterior; lo que llega mientras tanto se guarda. Las colas de MP/M (134-140) no sirven entre programas de usuario: el QCB tendría que estar en la memoria común, que es del sistema.

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
- `znum_a.s`, `znum.c`, `znum.h`: los números decimales de 9 cifras, su formato y las funciones (finanzas, fechas, trigonometría), los de ZCALC, que también usa ZBAS. Con `-DCPM_LITE`, `cpm.c` deja fuera lo que no usan los programas grandes (unos 1,9 KB).
- `mk.sh [programa...]` compila (con `--opt-code-size`), enlaza en 0110h y pasa el `.ihx` a `.COM`. Si existe `programa_a.s` lo agrega, y `crc32_a.s` si el programa usa `crc32.h`.

Se probaron en el emulador (`retroemu23`) con MP/M 1.4; los `.ZIP` hechos por `ZIP` se comprobaron con `unzip -t` y los de Python con `UNZIP`.
