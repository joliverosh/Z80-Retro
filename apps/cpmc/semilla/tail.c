/* c/ejemplos/tail.c - tail-milla: las ultimas lineas de la entrada.
 * Proyecto Semilla, version 1. */
/* tail-milla: filtro de stdin a stdout.  La 1ra linea de la entrada son las
   opciones: "-n N" (por omision 10).  Imprime las ultimas N lineas.  Guarda
   hasta 2000 lineas de hasta 511 caracteres. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

char *lineas[2000];

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
    int n, total, i, desde, len;
    linea(op, 64);
    n = 10;
    if (op[0] == '-' && op[1] == 'n') n = atoi(op + 2);
    total = 0;
    while ((len = linea(b, 512)) != -1) {
        lineas[total] = malloc(len + 1);
        strcpy(lineas[total], b);
        total++;
    }
    desde = total - n;
    if (desde < 0) desde = 0;
    for (i = desde; i < total; i++) printf("%s\n", lineas[i]);
    return 0;
}
