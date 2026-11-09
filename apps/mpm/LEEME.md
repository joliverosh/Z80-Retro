# MP/M II en la Z80-Retro

MP/M II 2.0 de Digital Research, el CP/M multiusuario de 1981, sobre la Z80-Retro (Z80 CPU Rev 2.2 o ZEPHYRUS Rev 2.3) con ZLoader/ZIOS v6. El XIOS es propio (`xios.asm`); el resto son los archivos originales de Digital Research.

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
| Consolas | 2: **SIO A** (la consola de siempre) y **SIO B** (segundo terminal o NUNTIUS), a la velocidad que dejó ZIOS |
| Memoria | 7 bancos de usuario de 48 KB (0000-BFFF) más el banco del sistema. La memoria común va de C000 a FFFF |
| Discos | A-F en la SD, con el mismo mapa de ZIOS (`SM`) y el mismo formato que CP/M 2.2. H: es el disco en flash, de solo lectura |
| Reloj | El tic de ZIOS: canal 1 del CTC, 120 Hz. MP/M recibe 60 tics por segundo |
| Hora | Se toma del DS1307 al arrancar. `H:RTC` la vuelve a leer |
| Caché de disco | Las páginas de RAM que sobran (64 KB): el directorio y los programas no se vuelven a leer de la SD. Escritura inmediata: la SD siempre está al día |

G: no existe en MP/M: el disco en RAM de ZIOS se pierde porque sus páginas pasan a ser los bancos de usuario.

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
Z80-Retro XIOS 1.2 (OLIVEROS 2026): 2 consolas, 7 bancos, SD y flash
64 KB de cache de disco
MP/M II V2.0
0A>TOD
Thu 10/15/26 10:30:02
```

- **El indicador** es `usuario` + `unidad` + `>`. Las dos consolas arrancan en `0A>`. Los programas del disco H: llevan el atributo SYS, así que se ven desde cualquier usuario y unidad.
- **PIP de MP/M es `H:PIP`.** Si en A: hay un `PIP.COM` de CP/M 3, ese gana al escribir solo `PIP` y responde `REQUIRES CP/M 3`.
- **Programas útiles:** `MPMSTAT` muestra procesos, bancos y colas. `ABORT nombre` detiene un programa. `CONSOLE` dice en qué consola estás.
- **Copiar un programa de H:** como es SYS, `PIP` necesita la opción `[R]`: `PIP A:=H:PRIMOS.COM[R]`.
- **Los programas de la Z80-Retro que llaman a ZIOS** (`RST 30h`, por ejemplo para la hora) no se cuelgan: encuentran un `RET`. Por eso marcan 00:00:00.
- **Para volver a ZLoader** hay que presionar RESET. MP/M se queda con la máquina.

## Cómo está hecho

- **`MPMLDR.COM`** es el cargador de Digital Research con nuestro `LDRBIOS` (`ldrbios.asm`) en 1700h. Corre como programa de CP/M y lee `MPM.SYS` de H: con el servicio 17 de ZIOS.
- **`MPM.SYS`** lo arma `GENSYS` con estas opciones:
  - tope en la página FD: deja libre FE00-FFFF, donde está el puente de ZIOS;
  - 2 consolas, RST 7 para el depurador y 60 tics por segundo;
  - unidad del sistema H: y memoria común desde C000;
  - 7 segmentos de usuario.
- **`SYSTEMINIT` del XIOS** se aprovecha de que ZIOS todavía está debajo:
  - le pregunta qué páginas tiene el banco 0 (servicio 1);
  - le pide el mapa de unidades (servicio 11);
  - le pide el tamaño del disco en flash (servicio 36) y los tics por segundo (servicio 31);
  - le pide la fecha del DS1307 (servicio 28) y la escribe en la hora de XDOS, cuya dirección está en SYSDAT+252. Si el reloj no responde o la fecha no es válida, MP/M arranca con su fecha de fábrica (14/09/81).

  Después desactiva las interrupciones y toma la máquina:
  - encuentra la página común;
  - reparte las páginas libres entre los bancos 1-7;
  - escribe la página cero de cada banco;
  - pone sus rutinas en la tabla de vectores IM 2 de ZIOS: SIO en FFE0-FFEE y CTC en FFF0-FFF6;
  - activa la recepción por interrupción en las dos SIO;
  - averigua con CMD58 si cada tarjeta es SDHC.
- **Parche a `XDOS.SPR`** (lo hace `gensys.py` antes de llamar a GENSYS): Digital Research pone a cada consola en el usuario igual a su número (`tmp$pd.disk$slct = i` en `mpm.asm`), así que la B arrancaba en `1A>`. Se cambian 3 bytes para que todas arranquen en el usuario 0.
- **`mkspr.py`** agrega un byte si el código mide un múltiplo exacto de 128: GENSYS reubica mal esos módulos (ver `gensys.txt` en cpm.z80.de).
- **La caché de disco** usa las páginas de RAM que no son de ningún banco ni la común (4 páginas con 512 KB de RAM). Guarda bloques de 512 bytes de la SD, asociativa de 2 vías, en la parte del XIOS con bancos. La página de la caché se pone un momento en la ventana 0, con las interrupciones apagadas de 64 en 64 bytes para no perder caracteres. Las escrituras van a la SD en el acto y también a la caché.
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
- **Nuestros:** `xios.asm`, `ldrbios.asm`, `rtc.asm`, `mkspr.py` (arma el SPR ensamblando en 0000h y en 0100h), `gensys.py` (responde a GENSYS dentro de cpmsim) e `ibm3740.py` (lee y escribe discos de 8" para cpmsim).
- **De Digital Research** (MP/M II 2.0, distribución libre desde 2001):
  - `dri/` (`GENSYS.COM`, `MPMLDR.COM` y los SPR);
  - `prl/` (las utilidades);
  - vienen de los discos de MP/M II de z80pack.

## Pendiente

- G: (el disco en RAM) no está en MP/M.
- Impresora: `LIST` descarta lo que recibe.
- La memoria común (C000-FFFF) no se puede achicar con provecho: las ventanas de la placa son de 16 KB, así que los bancos de usuario ya tienen los 48 KB máximos.
