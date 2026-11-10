/* c/ejemplos/seq.c - seq-milla: imprime una secuencia de enteros.
 * Proyecto Semilla, version 1. */
/* seq-milla: la 1ra linea de la entrada son los argumentos, como en `seq`:
   "ULTIMO", "PRIMERO ULTIMO" o "PRIMERO INCREMENTO ULTIMO".  Imprime un numero
   por linea. */
#include <stdio.h>
#include <string.h>

int palabra(char *s, int *pos, char *dst)
{
    int n;
    n = 0;
    while (s[*pos] == ' ') (*pos)++;
    while (s[*pos] && s[*pos] != ' ') dst[n++] = s[(*pos)++];
    dst[n] = 0;
    return n;
}

long numero(char *s)
{
    long v;
    int i, neg;
    v = 0; i = 0; neg = 0;
    if (s[0] == '-') { neg = 1; i = 1; }
    while (s[i] >= '0' && s[i] <= '9') {
        v = v * 10 + (s[i] - '0');
        i++;
    }
    return neg ? -v : v;
}

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
    char op[128], w[64];
    long primero, inc, ultimo, i;
    int pos, cuantos;
    linea(op, 128);
    pos = 0;
    cuantos = 0;
    primero = 1; inc = 1; ultimo = 0;
    while (palabra(op, &pos, w)) {
        if (cuantos == 0) ultimo = numero(w);
        else if (cuantos == 1) { primero = ultimo; ultimo = numero(w); }
        else { inc = ultimo; ultimo = numero(w); }
        cuantos++;
    }
    if (inc > 0) {
        for (i = primero; i <= ultimo; i += inc) printf("%ld\n", i);
    } else if (inc < 0) {
        for (i = primero; i >= ultimo; i += inc) printf("%ld\n", i);
    }
    return 0;
}
