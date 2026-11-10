/* c/ejemplos/rev.c - rev-milla: invierte cada linea de la entrada.
 * Proyecto Semilla, version 1. */
/* rev-milla: filtro de stdin a stdout.  Invierte los caracteres de cada linea,
   como `rev`. */
#include <stdio.h>
#include <string.h>

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
    int n, i, j, t;
    while ((n = linea(b, 512)) != -1) {
        i = 0;
        j = n - 1;
        while (i < j) {
            t = b[i]; b[i] = b[j]; b[j] = t;
            i++; j--;
        }
        printf("%s\n", b);
    }
    return 0;
}
