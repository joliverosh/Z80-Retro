# CP/M 2.2

This directory contains my port of CP/M to my Retro80 computer.

+ `cpm22.asm` is the combined CCP and BDOS. Essentially unchanged from the original Digital Research version.
+ `bios.asm` is my heavily customised BIOS. Most of the actual I/O is delegated to my ZIOS core system which is accessed via RST 30h.

Low level disk management is implemented by ZIOS which supports 1023 virtual 'disks' to be hosted on a single SDCard. Each virtual disk is 4MB is size. Any of the virtual disks can be mounted on one of the four logical drives in CP/M: A-D.

A `MOUNT.COM` CP/M programme can change be used to change which disks are mounted onto which drives.

## Programas residentes (corrección)

Dos fallas impedían que se quedaran residentes programas como SmartKey, que enganchan la tabla de saltos del BIOS:

- **El CCP medía 80Ch en lugar de 800h.** Las 6 instrucciones agregadas a `COMMAND` (vaciar el buffer y saltar de línea) desplazaban el BDOS a E412h y el BIOS a F20Ch. Muchos programas de CP/M 2.2 suponen el BDOS en xx06h y el BIOS al principio de una página (`LHLD 1` y luego `MVI L,xx`). Ahora esos 12 bytes salen del espacio libre del final del CCP: el BDOS vuelve a E406h y el BIOS a F200h, como en el CP/M de Digital Research.
- **El arranque en caliente leía un sector de más** (`INC H` sin redondear) y pisaba la tabla de saltos del BIOS con la copia de la SD, borrando los ganchos de los residentes. Ahora redondea hacia arriba.

La entrada de arranque se escribe con la nueva dirección de ejecución:

```
> WI 0:A DC00 FDFF
> WB 1 0:A DC00 2200 F200 01 CP/M
```

Con el CP/M nuevo y la entrada vieja (F20C) la placa se cuelga al arrancar.
