/* c/ejemplos/nl.c - nl-milla: numera todas las lineas de la entrada.
 * Proyecto Semilla, version 1. */
/* nl-milla: filtro de stdin a stdout.  Numera cada linea con 6 digitos a la
   derecha, un tabulador y la linea, igual que `nl -ba`. */
#include <stdio.h>

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
    int num;
    num = 0;
    while (linea(b, 512) != -1) {
        num++;
        printf("%6d", num);
        putchar(9);
        printf("%s\n", b);
    }
    return 0;
}
