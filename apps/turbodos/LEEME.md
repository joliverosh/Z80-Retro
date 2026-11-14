# TurboDOS 1.3 para la Z80-Retro / ZEPHYRUS

Port de TurboDOS 1.30 (Software 2000, distribución de IMS International) a la
Z80-Retro, en dos versiones de un solo usuario:

- **Con bancos** (`OSMASTER.SYS`, la de siempre). El sistema queda en el banco
  0 y los programas tienen un banco propio. El TPA llega hasta FAFF, unos
  62 KB.
- **Sin bancos** (`OSSINGLE.SYS`). Es más simple, pero el TPA llega solo hasta
  B8xx, unos 46 KB. Para usarla hay que renombrarla a `OSMASTER.SYS`.

Las dos se arrancan desde CP/M 3 con `OSLOAD`.

Los módulos de TurboDOS no están en este repositorio. Son de Software 2000 y
la distribución de IMS se puede bajar de la página de Dave Dunfield
(imstbdos). Aquí están solo los drivers de la placa y los archivos de
generación.

## Archivos

| Archivo | Qué es |
|---|---|
| `zrdrv.z80` | `HDWNIT`, consola, impresora y disco (va en los sistemas y en el cargador) |
| `zrbank.z80` | memoria común: `SELBNK`, tabla de vectores IM 2 y entradas de las interrupciones |
| `zrpage.z80` | segmento `?PAGE?`: anillo de la consola (256 bytes) |
| `zrrtc.z80` | `RTCNIT` (lee el DS1307 al arrancar) y `ZRSDT` (lo escribe al poner la fecha) |
| `zrlqry.z80` | `BNKQRY`, solo en el cargador: le pregunta a ZIOS las páginas para los bancos |
| `zrbnit.z80` | `BNKSET`, solo en el sistema con bancos: toma esas páginas |
| `ZRBNKS.GEN` / `.PAR` | el sistema con bancos, `OSMASTER.SYS` |
| `ZRSINGL.GEN` / `.PAR` | el sistema sin bancos, `OSSINGLE.SYS` |
| `ZRLOADR.GEN` / `.PAR` | el cargador, `OSLOAD.COM` |
| `tdate.z80`, `tdate.py` | parche del DATE.COM de IMS para los años 2000 |

### Drivers

- **Consola (SIO A).** Los caracteres que llegan entran por interrupción a un
  anillo de 256 bytes. Con 192 caracteres en el anillo se baja RTS y se vuelve a
  subir cuando quedan menos de 64. El tic también revisa la FIFO de la SIO, por
  si una interrupción de recepción se perdió. La salida es por encuesta y,
  mientras el transmisor está ocupado, le cede la CPU a TurboDOS (`DELAY 0`). La
  velocidad es la que dejó ZIOS.
- **Impresora (SIO B).** Salida por encuesta.
- **Disco.** Son los discos virtuales de 4 MB de ZIOS en la SD, con el mismo
  formato que CP/M: bloques de 2 KB, 512 entradas de directorio, sectores de
  512 bytes, 128 sectores por pista y una pista reservada. `ZDMAP` asigna a cada
  unidad una tarjeta y un disco virtual. Por omisión, A: es el disco virtual 1
  de la tarjeta 0, B: el 2, y así hasta P:, que es el 16. Un FF en la tarjeta
  significa que la unidad no existe. El mapa se cambia en el `.PAR`: cada
  unidad ocupa dos bytes, así que `ZDMAP+4 = 0,5` hace que C: sea el disco
  virtual 5 de la tarjeta 0.
- **Reloj.** El canal 1 del CTC queda a 120 Hz, como lo deja ZIOS. Uno de cada
  dos tics es el tic de TurboDOS (60 Hz), y uno de cada 60 de esos llama a
  `RTCSEC`. Al arrancar, `RTCNIT` lee el DS1307 y pone la fecha y la hora. Si el
  reloj no responde, no se cambia nada. Cuando se pone la fecha o la hora
  (T-función 9, C-función 104 o el comando `TDATE`), `ZRSDT` también la escribe
  en el DS1307. El `.PAR` hace que el final de `SDTFCN` salte a `ZRSDT`.

### Bancos

La ventana 3 (C000-FFFF) es la memoria común. GEN pone ahí, con `;KC000`, todo
lo que va en `?BANK?` y en `?PAGE?`. El resto del sistema queda en el banco 0,
debajo de C000. El banco 1 (el TPA) son otras tres páginas en las ventanas 0-2.

- **Las páginas.** Los registros de página no se pueden leer. Por eso `OSLOAD`,
  que todavía corre con ZIOS, averigua con `BNKQRY` qué páginas tienen las
  ventanas 0-2 y le pide a ZIOS tres páginas libres. Deja todo en 0040h, y el
  sistema lo toma al arrancar. Si no encuentra esa información, avisa y se
  detiene.
- **Las interrupciones.** Las entradas están en la memoria común y pasan a una
  pila común. Si estaba puesto el banco 1, ponen el banco 0, llaman al manejador
  y después vuelven a poner el banco que había.

### Detalles del enlace (zmac --rel con GEN)

- zmac no reubica bien una referencia que va de un bloque COMMON a otro. Por eso
  `?BANK?` y `?PAGE?` están en sus propios módulos y solo se usan desde otros
  módulos como externos.
- GEN no acepta referencias externas dentro de esos bloques, y tampoco que un
  bloque termine con `DEFS` (en los dos casos dice "Load address
  out-of-bounds"). Una referencia externa repetida en `DEFW` también sale mal.
  Por eso la tabla de vectores se arma con código (`VSET`), las direcciones de
  los manejadores las escribe `HDWNIT`, y los bloques terminan con un `DEFB`.
- El semáforo de TurboDOS de un solo usuario (DSPSGL) cuenta en un byte con
  signo. Por eso la consola solo hace `SIGNAL` cuando el anillo estaba vacío y
  hay alguien esperando en `WAIT`. Si no, al pegar texto rápido la cuenta
  pasaba de 127 y `WAIT` no volvía.

## Uso

1. Pasar `TDOS.zip` (`OSLOAD.COM`, `OSMASTER.SYS` y `OSSINGLE.SYS`) al disco
   A: de CP/M. Opcionalmente, pasar también `TDUTIL.zip`, que trae los comandos
   de TurboDOS. Los que se llaman igual que comandos de CP/M 3 van con una T
   delante: `TDATE`, `TDIR`, `TDUMP`, `TRENAME`, `TSET`, `TSHOW` y `TTYPE`.
2. Arrancar CP/M 3 (`BOS 2`) y escribir `OSLOAD`. El cargador busca
   `OSMASTER.SYS` en las unidades A: a P:, lo carga y lo arranca. El indicador
   de TurboDOS es `0A}`, es decir, usuario 0 en la unidad A:.
3. Para volver a CP/M hay que hacer un reset.

Probado en el emulador:

- WordStar 4, MBASIC (38.703 bytes libres con bancos), Turbo Pascal 3 y Zork I.
- Los DIR, TYPE y SHOW de CP/M 3.
- `COPY` entre discos, con el archivo igual al original.
- Pegar 30 líneas seguidas en MBASIC, con RTS.
- `LPRINT` a la SIO B.
- Poner la fecha con `TDATE` y que quede en el DS1307.

En la línea de comandos de TurboDOS, Ctrl-C no borra la línea: queda como un
carácter más. Para cancelar la línea se usa Ctrl-X o Ctrl-U.

### El directorio

La primera vez que TurboDOS usa un disco de CP/M, mueve las primeras entradas
del directorio al final y en su lugar escribe su etiqueta y su mapa de bloques.
CP/M ve esas entradas como borradas, así que el disco se sigue leyendo y
escribiendo bien desde CP/M 3. En las pruebas, después de que CP/M escribió
en el disco, TurboDOS no usó los bloques nuevos de CP/M, tanto cuando CP/M
pisó la etiqueta como cuando agregó un bloque a un archivo sin tocarla. Si hay
dudas, `FIXMAP x:` rehace el mapa.

### TDATE

El DATE de IMS guarda el año como año − 1900. Sin parche muestra 2026 como `<6`
y toma un año de dos cifras siempre como 19xx. El `TDATE.COM` de `TDUTIL.zip`
está parchado con `tdate.z80`: muestra `26` y toma los años de dos cifras
menores que 48 como 20xx. Para aplicar el parche a un DATE.COM original:

```
zmac -o tdate.cim tdate.z80
python3 tdate.py DATE.COM tdate.cim TDATE.COM
```

`TDATE 29 Feb 28` pone la fecha y luego pide la hora. Las dos quedan en
TurboDOS y en el DS1307.

## Generar

En CP/M, en un disco que tenga los `.REL` de IMS, estos `.REL` y los `.GEN` y
`.PAR`:

```
PACKAGE STDLOADR
GEN ZRLOADR OSLOAD.COM
GEN ZRBNKS OSMASTER.SYS ;KC000
GEN ZRSINGL OSSINGLE.SYS
```

Con `;M;S` después del nombre de salida, GEN manda a la impresora el mapa y la
tabla de símbolos. Los `.REL` se arman con
`zmac --rel -o x.rel -o x.lst x.z80`.
