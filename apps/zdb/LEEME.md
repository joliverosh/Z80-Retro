# ZDB — depurador Z80 para CP/M y MP/M II

ZDB es un depurador al estilo de DDT/ZSID, con los mnemónicos de Zilog, para la Z80-Retro (ZEPHYRUS). Corre en MP/M II, CP/M 3 y CP/M 2.2. Ocupa 26 páginas (6,5 KB) de la TPA: con MP/M quedan unos 41 KB para el programa que se depura.

```
ZDB [archivo[.COM] [argumentos]]
```

Carga `archivo.COM` en 100h y le pasa los argumentos como si lo hubiera llamado el CCP (la línea en 80h, los FCB en 5Ch y 6Ch). El indicador de ZDB es `#`.

## Órdenes

Los números van en hexadecimal, sin `H`. Los argumentos se separan con comas o espacios.

| Orden | Qué hace |
|---|---|
| `D[ini][,fin]` | Volcado en hex y ASCII; sin `fin`, 128 bytes; sin `ini`, sigue donde quedó. |
| `L[ini][,fin]` | Desensamblado; sin `fin`, 12 instrucciones; sin `ini`, sigue donde quedó. |
| `G[dir][,p1[,p2]]` | Ejecuta desde `dir` (o desde PC) y para en `p1` o `p2` (puntos temporales) o en un punto permanente. |
| `T[n]` | Ejecuta `n` instrucciones (1 por omisión) y muestra los registros después de cada una. |
| `N[n]` | Igual que `T`, pero pasa por encima de `CALL` y `RST`. |
| `B` / `B dir[,dir,dir]` | Lista o pone puntos de parada permanentes (hasta 8). |
| `K` / `K dir` | Quita todos los puntos permanentes, o uno. |
| `X` / `Xr valor` | Muestra los registros (también los alternos) o cambia uno: `A F B C D E H L AF BC DE HL IX IY SP PC AF' BC' DE' HL'`. Se puede escribir `XHL 1234` o `XHL=1234`. |
| `S dir` | Cambia memoria: muestra cada byte y lee la línea; acepta varios bytes (`3E 05`) y texto entre comillas (`'Hola'`). Línea vacía = siguiente, `-` = anterior, `.` = fin. |
| `F ini,fin,byte` | Llena. |
| `M ini,fin,destino` | Copia (aunque se solapen). |
| `H a,b` / `H a` | Suma y resta en hex / `a` en decimal. |
| `I texto` | Pone la línea de órdenes del programa (80h) y los FCB 5Ch y 6Ch. |
| `R[desp]` | Lee el archivo nombrado con `I` en 100h+`desp` (sin nombre en `I`, vuelve a leer el último); pone PC = 100h. |
| `W archivo[,ini,fin]` | Graba memoria (por omisión de 100h hasta el fin de lo último leído) en registros de 128 bytes. |
| `Q` | Sale (también `^C` en el indicador en CP/M). |
| `?` | Ayuda. |

Después de `T`, `N` o de un punto de parada, ZDB muestra:

```
A=00 F=-Z-P-- BC=0000 DE=0118 HL=0000 IX=0000 IY=0000 SP=A4FE
0104  CD 16 01     CALL 0116H
```

`F` son las banderas `S Z H P N C` (`-` = apagada) y la segunda línea es la instrucción que va a ejecutarse. Una tecla corta un `T` o `N` largo y también `D` y `L` con rango.

## Cómo funciona

- **Se reubica:** `ZDB.COM` es un cargador más ZDB ensamblado en 0000h y un mapa de bits; el cargador lo copia justo debajo del BDOS (la página de `(6)`), suma la página a los bytes marcados y le salta. Luego `(6)` apunta a ZDB, así que la TPA del programa termina donde empieza ZDB.
- **Puntos de parada:** `RST 38h` (`FFh`) en la dirección; la Z80-Retro trabaja en IM 2 y `0038h` está libre en cada banco. Al parar se devuelven todos los bytes originales.
- **Pasos:** ZDB desensambla la instrucción en PC, pone puntos temporales en la siguiente y en el destino del salto (`JP`, `JR`, `DJNZ`, `CALL`, `RET`, `JP (HL)`, `JP (IX)`, `RETI`/`RETN`) y ejecuta. Los saltos al sistema (página 0, `CALL 5`, `RST`, todo lo que está de ZDB para arriba) se ejecutan enteros; un `JP 5` para en la dirección de regreso. Un `DJNZ $` corre hasta salir del bucle.
- **Fin del programa:** la función 0 o 143 del BDOS, un `JP 0` y un `RET` al final (ZDB deja `0000` en la pila) vuelven a ZDB con `Program ended`; PC y SP vuelven al principio, y la memoria queda como la dejó el programa.
- **Desensamblador:** todas las instrucciones del Z80, también las no documentadas (`IXH`, `SLL`, `IN F,(C)`, `OUT (C),0`, `RLC (IX+5),B`). La salida se puede volver a ensamblar: las 705 formas del archivo de prueba de ZAS, desensambladas por ZDB y ensambladas otra vez con zmac y con ZAS, salen byte a byte iguales.

## Límites

- El programa corre con las interrupciones habilitadas (ZDB hace `EI` al volver a él).
- `^C` mientras el programa corre lo termina como siempre (en MP/M termina también ZDB); un programa que nunca vuelve no se puede parar.
- No hay símbolos ni ensamblador en línea: para cambiar código, `S` con los bytes, o ZAS.

## Construir

`build.sh` (o `python3 mkzdb.py`): ensambla `zdb.asm` (con `zdbdis.asm`) en 0000h y en 0100h con zmac, saca el mapa de reubicación de la diferencia y arma `ZDB.COM` con `zdbldr.asm`. ZAS ensambla el mismo fuente con resultado idéntico al de zmac.

Probado en el emulador con MP/M II (PI1K bajo ZDB con puntos de parada y pasos, todas las órdenes) y con CP/M 3.
