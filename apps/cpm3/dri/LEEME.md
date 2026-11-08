# Ficheros de Digital Research

Componentes de CP/M 3 (CP/M Plus) de Digital Research. Su redistribución está
permitida: ver http://www.cpm.z80.de/license.html (Lineo/Caldera autorizó la
distribución del código y los binarios de CP/M).

Proceden de la distribución de CP/M 3 parcheada por John Elliott (todos los
parches de `cpm3fix.pat` aplicados, fechas Y2K), tal como la incluye RomWBW
(https://github.com/wwarthen/RomWBW, `Source/CPM3` y `Source/Images/d_cpm3`).

| Fichero | Uso |
|---|---|
| `cpmldr.asm`, `makedate.lib` | Fuente del cargador CPMLDR (se ensambla con RMAC) |
| `scb.asm` | Definición del System Control Block para el BIOS |
| `resbdos3.spr`, `bnkbdos3.spr` | BDOS residente y BDOS con bancos |
| `ccp.com` | Procesador de órdenes (se copia a A:) |
| `gencpm.com` | Generador del sistema (CPM3.SYS) |
| `rmac.com`, `link.com` | Ensamblador y enlazador de DRI (los usa `mk.sh` bajo zxcc) |
| `util/` | Utilidades transitorias de CP/M 3 |
| `readme.1st`, `cpm3fix.pat` | Notas originales de la distribución y de los parches |
