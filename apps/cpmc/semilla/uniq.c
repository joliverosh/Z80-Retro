/* c/ejemplos/uniq.c - uniq-milla: quita o cuenta lineas repetidas seguidas.
 * Proyecto Semilla, version 1. */
/* uniq-milla: filtro de stdin a stdout.  La 1ra linea de la entrada son las
   opciones: "-c" para anteponer el conteo (formato de `uniq -c`), o vacia.
   Como `uniq`, solo quita repetidos que estan seguidos. */
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

void imprime(char *s, int cuenta, int cflag)
{
    if (cflag) printf("%7d %s\n", cuenta, s);
    else printf("%s\n", s);
}

int main(void)
{
    char op[64], prev[512], cur[512];
    int cuenta, hayPrev, cflag, n;
    linea(op, 64);
    cflag = strcmp(op, "-c") == 0;
    cuenta = 0;
    hayPrev = 0;
    while ((n = linea(cur, 512)) != -1) {
        if (hayPrev && strcmp(cur, prev) == 0) {
            cuenta++;
            continue;
        }
        if (hayPrev) imprime(prev, cuenta, cflag);
        strcpy(prev, cur);
        cuenta = 1;
        hayPrev = 1;
    }
    if (hayPrev) imprime(prev, cuenta, cflag);
    return 0;
}
