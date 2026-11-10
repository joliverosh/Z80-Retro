/* c/ejemplos/tr.c - tr-milla: traduce o borra caracteres.
 * Proyecto Semilla, version 1. */
/* tr-milla: filtro de stdin a stdout.  La 1ra linea de la entrada son los
   argumentos, como en `tr`: "SET1 SET2" traduce, "-d SET1" borra.  Los sets
   admiten rangos (a-z).  Si SET2 es mas corto, se repite su ultimo caracter. */
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

/* siguiente palabra de s (separada por espacios) en dst; devuelve su largo */
int palabra(char *s, int *pos, char *dst)
{
    int n;
    n = 0;
    while (s[*pos] == ' ') (*pos)++;
    while (s[*pos] && s[*pos] != ' ') dst[n++] = s[(*pos)++];
    dst[n] = 0;
    return n;
}

/* expande un set con rangos a-z en out; devuelve cuantos caracteres son */
int expande(char *s, int *out)
{
    int i, n, c, lo, hi;
    i = 0; n = 0;
    while (s[i]) {
        if (s[i + 1] == '-' && s[i + 2]) {
            lo = s[i];
            hi = s[i + 2];
            for (c = lo; c <= hi; c++) out[n++] = c;
            i += 3;
        } else {
            out[n++] = s[i];
            i++;
        }
    }
    return n;
}

int main(void)
{
    char op[256], w1[256], w2[256];
    int pos, borrar, n1, n2, i, c;
    int set1[512], set2[512], mapa[256], borra[256];
    linea(op, 256);
    pos = 0;
    palabra(op, &pos, w1);
    borrar = strcmp(w1, "-d") == 0;
    if (borrar) palabra(op, &pos, w1);
    palabra(op, &pos, w2);
    for (c = 0; c < 256; c++) { mapa[c] = c; borra[c] = 0; }
    n1 = expande(w1, set1);
    if (borrar) {
        for (i = 0; i < n1; i++) borra[set1[i]] = 1;
    } else {
        n2 = expande(w2, set2);
        for (i = 0; i < n1; i++) {
            if (n2 == 0) break;
            mapa[set1[i]] = i < n2 ? set2[i] : set2[n2 - 1];
        }
    }
    while ((c = getchar()) != -1) {
        if (borra[c]) continue;
        putchar(mapa[c]);
    }
    return 0;
}
