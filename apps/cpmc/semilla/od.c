/* c/ejemplos/od.c - od-milla: volcado hexadecimal de la entrada.
 * Proyecto Semilla, version 1. */
/* od-milla: filtro de stdin a stdout.  Imprime el desplazamiento en hexadecimal
   (6 digitos) y los bytes en hexadecimal, 16 por linea, igual que
   `od -A x -t x1 -v`.  Al final imprime el tamano total. */
#include <stdio.h>

void hex6(long v)
{
    int i, d;
    for (i = 5; i >= 0; i--) {
        d = (v >> (4 * i)) & 15;
        putchar(d < 10 ? '0' + d : 'a' + d - 10);
    }
}

void hex2(int v)
{
    int d;
    d = (v >> 4) & 15;
    putchar(d < 10 ? '0' + d : 'a' + d - 10);
    d = v & 15;
    putchar(d < 10 ? '0' + d : 'a' + d - 10);
}

int main(void)
{
    long off;
    int c, col;
    off = 0;
    col = 0;
    while ((c = getchar()) != -1) {
        if (col == 0) hex6(off);
        putchar(' ');
        hex2(c);
        off++;
        col++;
        if (col == 16) { putchar('\n'); col = 0; }
    }
    if (col) putchar('\n');
    hex6(off);
    putchar('\n');
    return 0;
}
