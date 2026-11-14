# TurboDOS 1.3 para la Z80-Retro / ZEPHYRUS

Port de TurboDOS 1.30 (Software 2000, distribución de IMS International) a la
Z80-Retro. Es la versión de un solo usuario y sin bancos (`STDSINGL`). Se
arranca desde CP/M con `OSLOAD`.

Los módulos de TurboDOS no están en este repositorio. Son de Software 2000 y
la distribución de IMS se puede bajar de la página de Dave Dunfield
(imstbdos). Aquí están solo los drivers de la placa y los archivos de
generación.

## Archivos

| Archivo | Qué es |
|---|---|
| `zrdrv.z80` | `HDWNIT`, consola, impresora y disco (va en el sistema y en el cargador) |
| `zrpage.z80` | segmento `?PAGE?`: anillo de la consola (256 bytes) y tabla de vectores IM 2 |
| `zrrtc.z80` | `RTCNIT`: lee el DS1307 al arrancar (solo en el sistema) |
| `ZRSINGL.GEN` / `.PAR` | el sistema, `OSMASTER.SYS` |
| `ZRLOADR.GEN` / `.PAR` | el cargador, `OSLOAD.COM` |

### Drivers

- **Consola (SIO A).** Los caracteres que llegan entran por interrupción a un
  anillo de 256 bytes. Con 192 caracteres en el anillo se baja RTS y se vuelve a
  subir cuando quedan menos de 64. La salida es por encuesta y, mientras el
  transmisor está ocupado, le cede la CPU a TurboDOS (`DELAY 0`). La velocidad
  es la que dejó ZIOS.
- **Impresora (SIO B).** Salida por encuesta.
- **Disco.** Son los discos virtuales de 4 MB de ZIOS en la SD, con el mismo
  formato que CP/M: bloques de 2 KB, 512 entradas de directorio, sectores de
  512 bytes, 128 sectores por pista y una pista reservada. `ZDMAP` asigna a cada
  unidad una tarjeta y un disco virtual. Por omisión, A: es el disco virtual 1
  de la tarjeta 0, B: el 2, y así hasta P:, que es el 16. Un FF en la tarjeta
  significa que la unidad no existe. El mapa se cambia en el `.PAR`: cada unidad ocupa dos bytes, así que `ZDMAP+4 = 0,5`
  hace que C: sea el disco virtual 5 de la tarjeta 0.
- **Reloj.** El canal 1 del CTC queda a 120 Hz, como lo deja ZIOS. Uno de cada
  dos tics es el tic de TurboDOS (60 Hz), y uno de cada 60 de esos llama a
  `RTCSEC`. Al arrancar, `RTCNIT` lee el DS1307 y pone la fecha y la hora. Si el
  reloj no responde, no se cambia nada.

### Tres detalles del enlace (zmac --rel con GEN)

- zmac no reubica bien una referencia que va de un bloque COMMON a otro. Por eso
  los vectores y el anillo están en su propio módulo, `zrpage.z80`.
- GEN no acepta referencias externas dentro de `?PAGE?`, y tampoco que el bloque
  termine con `DEFS` (en los dos casos dice "Load address out-of-bounds"). Por
  eso `HDWNIT` copia los vectores a la tabla y el bloque termina con un `DEFB`.
- El semáforo de TurboDOS de un solo usuario (DSPSGL) cuenta en un byte con
  signo. Por eso la consola solo hace `SIGNAL` cuando el anillo estaba vacío y
  hay alguien esperando en `WAIT`; si no, al pegar texto rápido la cuenta pasaba
  de 127 y `WAIT` no volvía.

## Uso

1. Pasar `TDOS.zip` (`OSLOAD.COM` y `OSMASTER.SYS`) al disco A: de CP/M.
   Opcionalmente, pasar también `TDUTIL.zip`, que trae los comandos de TurboDOS.
   Los que se llaman igual que comandos de CP/M 3 van con una T delante:
   `TDATE`, `TDIR`, `TDUMP`, `TRENAME`, `TSET`, `TSHOW` y `TTYPE`.
2. Arrancar CP/M (`BOS 2`) y escribir `OSLOAD`. El cargador busca `OSMASTER.SYS`
   en las unidades A: a P:, lo carga y lo arranca. El indicador de TurboDOS es
   `0A}`, es decir, usuario 0 en la unidad A:.
3. Para volver a CP/M hay que hacer un reset.

Los programas de CP/M corren sin cambios. Se probaron MBASIC, Turbo Pascal 3,
Zork I y los DIR, TYPE y SHOW de CP/M 3. El TPA llega hasta B8xx (unos 46 KB).

### Ojo con el directorio

La primera vez que TurboDOS usa un disco de CP/M, mueve las primeras entradas
del directorio al final y en su lugar escribe su etiqueta y su mapa de bloques.
CP/M ve esas entradas como borradas, así que el disco se sigue leyendo bien
desde CP/M 3. Pero si CP/M escribe en ese disco, el mapa de TurboDOS queda
desactualizado. Si CP/M pisa la etiqueta, TurboDOS lo nota y vuelve a armar el
mapa (esto se probó). Si no, hay que correr `FIXMAP x:` en TurboDOS antes de
escribir en el disco.

### Conocido

- `TDATE` (el DATE de IMS) muestra el año 2026 como `<6`, porque escribe
  año − 1900 con dos cifras. La fecha que guarda TurboDOS es la correcta.

## Generar

En CP/M, en un disco que tenga los `.REL` de IMS, estos tres `.REL` y los
`.GEN` y `.PAR`:

```
PACKAGE STDLOADR
GEN ZRLOADR OSLOAD.COM
GEN ZRSINGL OSMASTER.SYS
```

Con `;M;S` después del nombre de salida, GEN manda a la impresora el mapa y la
tabla de símbolos. Los `.REL` se arman con
`zmac --rel -o x.rel -o x.lst x.z80`.

## Pendiente

- La versión con bancos (`BNKSINGL`: buffers y parte del sistema en otro banco,
  con `SELBNK` sobre los registros de página), para tener más TPA.
