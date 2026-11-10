# Programas en C para MP/M II ZEPHYRUS (y CP/M 2.2)

Programas escritos en C con SDCC 4.2 y una biblioteca chica propia (`cpm.c`). Cada uno es un `.COM` que se pasa a la SD con `XFER` (YMODEM: `sb` desde la Mac) y se ejecuta desde A:.

## Los programas

| Programa | Qué hace | Uso |
|---|---|---|
| `VI` | Un editor como vi (ver abajo) | `VI NOTAS.TXT` |
| `TOP` | Los procesos de MP/M (consola, segmento, prioridad, estado), el uso de la CPU, la fecha y la hora; se actualiza cada segundo | `TOP` (una tecla sale) |
| `TALK` | Manda un mensaje a otra consola | `TALK 2 hola, ya termine` |
| `CLOCK` | Un reloj grande en la pantalla | `CLOCK` |
| `BENCH` | Mide la CPU (MHz), la criba de Eratóstenes, cuentas de 16 y 32 bits, la consola y el disco (escribe y lee 64 KB) | `BENCH` o `BENCH B:` |
| `MANDEL` | El conjunto de Mandelbrot en colores, con aritmética de punto fijo | `MANDEL` |
| `LIFE` | El juego de la vida de Conway, 78 × 22 | `LIFE` |
| `TETRIS` | Flechas o WASD/IJKL; arriba gira, espacio la deja caer, P pausa, Q sale | `TETRIS` |
| `SNAKE` | La víbora: come los `*` sin chocar | `SNAKE` |
| `MORE` | Un archivo de texto por pantallas (espacio, RETURN, Q) | `MORE LEEME.TXT` |
| `GREP` | Busca un patrón (`.` `x*` `^` `$`) sin distinguir mayúsculas; `-N` números de línea, `-V` las que no, `-C` cuántas, `-L` los archivos | `GREP -N ^ORG *.ASM` |
| `WC` | Líneas, palabras y caracteres | `WC *.TXT` |
| `CMP` | Compara dos archivos byte a byte | `CMP A.COM B:A.COM` |
| `HEXDUMP` | Un archivo en hexadecimal y ASCII, desde un desplazamiento | `HEXDUMP PIP.COM 100` |
| `I2CSCAN` | El mapa del bus I2C, la hora del DS1307 y su RAM; escribe en la RAM libre (18-3F) | `I2CSCAN`, `I2CSCAN T 20 HOLA`, `I2CSCAN W 18 01 02`, `I2CSCAN Z` |
| `SHA256` | La suma SHA-256, con el formato de `sha256sum` | `SHA256 *.COM`, `SHA256 -T NOTAS.TXT` |
| `ZIP` | Hace un `.ZIP` con deflate | `ZIP COPIA *.ASM *.COM`, `ZIP -T TEXTOS *.TXT` |
| `UNZIP` | Saca los archivos de un `.ZIP` (guardados o con deflate, también los hechos en la Mac) y comprueba el CRC | `UNZIP COPIA`, `UNZIP -L COPIA`, `UNZIP COPIA B:` |

`TOP` (el uso de la CPU) y `TALK` usan los servicios 44 y 45 del XIOS: necesitan el `MPM.SYS` de noviembre de 2026 o posterior. `TOP`, `TALK` y `CLOCK` solo andan en MP/M; los demás también en CP/M 2.2.

## VI

Un editor como vi para terminal ANSI de 80 columnas. El texto va en memoria: en MP/M caben unos 21 KB (en CP/M 2.2, más). Filas 1 a 22: el texto; la 23: mensajes y órdenes.

- **Moverse:** `h j k l` y flechas, `w b e`, `0 ^ $` (Inicio, Fin), `G`, `gg`, `NG`, `H M L`, `f F t T` con `;` y `,`, `%`, `^F ^B` (RePág, AvPág), `^D ^U ^E ^Y`. Cuentas: `5j`, `3w`.
- **Cambiar:** `i a I A o O` (con sangría automática), `x X r ~ J`, `dd D C s S cc`, `d c y` con cualquier movimiento (`dw`, `c$`, `y3j`, `dG`, `d%`), `yy Y p P`, `u` (deshacer; otra vez, rehacer), `.` (repetir el último cambio).
- **Buscar:** `/texto`, `?texto`, `n N` (distingue mayúsculas).
- **Órdenes:** `:w [archivo]`, `:q`, `:q!`, `:wq`, `:x`, `ZZ`, `:e archivo`, `:e!`, `:r archivo`, `:N` (ir a la línea), `:$`, `:[rango]d`, `:[rango]s/viejo/nuevo/[g]` con rango `N`, `N,M`, `.`, `$` o `%`. `^G` dice dónde se está y cuánto queda libre; `^L` redibuja.
- Guarda en un `.$$$` y después lo cambia de nombre: si el disco se llena, el archivo de antes queda. Escribe CR LF y rellena con `^Z`.
- Las líneas largas no se parten: la pantalla se corre a los lados.
- Lee el teclado con BDOS 6 y escribe con BDOS 6: BDOS 2, 9 y 11 se llevan teclas a un búfer que BDOS 6 no ve (pasaba al pegar texto o con `.`).

## Detalles

- **Archivos de CP/M y tamaños exactos.** CP/M guarda los archivos en registros de 128 bytes y no sabe dónde terminan. `SHA256` y `ZIP` toman el archivo entero; con `-T` (texto) cortan en el primer `^Z`. Para comprobar en la Mac un archivo recibido por XMODEM, que llega con relleno, conviene `SHA256 -T` si es texto, o comparar con la suma del archivo rellenado.
- **`ZIP`:** LZ77 con ventana de 4 KB y los códigos de Huffman fijos de deflate; `-1` más rápido, `-9` busca más, `-0` sin comprimir. Si comprimido sale más grande, lo guarda sin comprimir. El `.ZIP` termina justo al final del último registro (el relleno va en un campo extra del directorio), así `unzip` en la Mac no se queja. La fecha sale del reloj de MP/M. Comprime unos 1,2 KB por segundo a 7,37 MHz.
- **`UNZIP`:** inflate completo (bloques guardados, fijos y dinámicos, ventana de 32 KB). Los nombres pasan a 8.3 en mayúsculas sin carpetas (`docs/leeme_largo.markdown` → `LEEME_LA.MAR`); el último registro se rellena con `^Z`. Pregunta antes de reemplazar (`-O`: no pregunta). Necesita 46 KB de TPA (MP/M tiene 47). Saca unos 4,5 KB por segundo.
- **`SHA256`:** la compresión está en ensamblador (`sha256_a.s`): unos 1,1 KB por segundo a 7,37 MHz.
- **Teclas:** `GREP`, `WC`, `SHA256`, `ZIP` y los que recorren archivos se detienen con `^C`, `Q` o ESC.

## Cómo está hecho

- `crt0.s`: arranca en 100h, toma la pila de la dirección 6, pone a cero los datos y copia los inicializados; `exit` es BDOS 0.
- `cpm.h` / `cpm.c`: BDOS y ZIOS (`RST 30h`), consola (`putch`, `pstr`, `pf` con `%d %u %ld %lu %x %X %s %c`, ancho y ceros), teclado sin esperar, archivos por FCB (secuencial, directo, comodines con `glob`, lectura de a un byte), la línea de órdenes, tics, la hora de MP/M, números al azar y ANSI.
- `crc32.h` + `crc32_a.s`: CRC-32 con tabla, en ensamblador. `unzip_a.s`: los bits y la decodificación de Huffman. `zip_a.s`: los bits de salida, la búsqueda de coincidencias y el corrimiento de las tablas de hash.
- **SDCC 4.2:** `(int32_t)a * b` con `a` y `b` de 16 bits con signo da mal; se usa `mul16()`. Por eso `MANDEL` salía todo de puntos.
- `mk.sh [programa...]` compila (con `--opt-code-size`), enlaza en 0110h y pasa el `.ihx` a `.COM`. Si existe `programa_a.s` lo agrega, y `crc32_a.s` si el programa usa `crc32.h`.

Se probaron en el emulador (`retroemu23`) con MP/M 1.4; los `.ZIP` hechos por `ZIP` se comprobaron con `unzip -t` y los de Python con `UNZIP`.
