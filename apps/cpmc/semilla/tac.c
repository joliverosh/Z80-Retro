/* c/ejemplos/tac.c - tac-milla: imprime las lineas de la entrada al reves.
 * Proyecto Semilla, version 1. */
/* tac-milla: filtro de stdin a stdout.  Imprime las lineas en orden inverso,
   como `tac`.  Guarda hasta 2000 lineas de hasta 511 caracteres. */
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
    char b[512];
    int total, i, len;
    total = 0;
    while ((len = linea(b, 512)) != -1) {
        lineas[total] = malloc(len + 1);
        strcpy(lineas[total], b);
        total++;
    }
    for (i = total - 1; i >= 0; i--) printf("%s\n", lineas[i]);
    return 0;
}
