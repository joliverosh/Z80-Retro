/* c/ejemplos/sort.c - sort-milla: ordena las lineas de la entrada.
 * Proyecto Semilla, version 1. */
/* sort-milla: filtro de stdin a stdout.  La 1ra linea de la entrada son las
   opciones: "-r" (inverso), "-u" (sin repetidos) o vacia.  Ordena por bytes,
   como `LC_ALL=C sort`.  Hasta 2000 lineas de hasta 511 caracteres. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

char *lineas[2000];
int nlin;
int rev;

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

int cmp(char *a, char *b)
{
    char **pa, **pb;
    int r;
    pa = (char **)a;
    pb = (char **)b;
    r = strcmp(*pa, *pb);
    return rev ? -r : r;
}

int main(void)
{
    char op[64], b[512];
    int uniq, i, n;
    linea(op, 64);
    rev = strcmp(op, "-r") == 0 || strcmp(op, "-ru") == 0;
    uniq = strcmp(op, "-u") == 0 || strcmp(op, "-ru") == 0;
    nlin = 0;
    while ((n = linea(b, 512)) != -1) {
        lineas[nlin] = malloc(n + 1);
        strcpy(lineas[nlin], b);
        nlin++;
    }
    qsort((char *)lineas, nlin, sizeof(char *), (int (*)(const void *, const void *))cmp);
    for (i = 0; i < nlin; i++) {
        if (uniq && i > 0 && strcmp(lineas[i], lineas[i - 1]) == 0) continue;
        printf("%s\n", lineas[i]);
    }
    return 0;
}
