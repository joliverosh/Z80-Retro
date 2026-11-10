/* c/ejemplos/head.c - head-milla: las primeras lineas de la entrada.
 * Proyecto Semilla, version 1. */
/* head-milla: filtro de stdin a stdout.  La 1ra linea de la entrada son las
   opciones: "-n N" (por omision 10).  Imprime las primeras N lineas. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int linea(char *b, int max)
{
    int c, n, hay;
    n = 0; hay = 0;
    while ((c = getchar()) != -1) {
        hay = 1;
        if (c == '\n') break;
        if (n < max - 1) b[n++] = c;
    }
    b[n] = 0;
    if (!hay) return -1;
    return n;
}

int main(void)
{
    char op[64], b[512];
    int n, k, r;
    linea(op, 64);
    n = 10;
    if (op[0] == '-' && op[1] == 'n') {
        n = atoi(op + 2);
    }
    k = 0;
    while (k < n && (r = linea(b, 512)) != -1) {
        printf("%s\n", b);
        k++;
    }
    return 0;
}
