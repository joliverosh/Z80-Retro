/* c/ejemplos/factor.c - factor-milla: descompone en factores primos.
 * Proyecto Semilla, version 1. */
/* factor-milla: lee numeros de stdin (separados por espacios o saltos de linea)
   y escribe "N: p1 p2 ..." con sus factores primos, como `factor`.  Enteros de
   32 bits sin signo (clase 32). */
#pragma clase 32
#include <stdio.h>

void factoriza(unsigned long n)
{
    unsigned long d;
    printf("%lu:", n);   /* (%lu: en SDCC el int es de 16 bits) */
    if (n >= 2) {
        d = 2;
        while (d <= n / d) {
            while (n % d == 0) {
                printf(" %lu", d);
                n = n / d;
            }
            d++;
        }
        if (n > 1) printf(" %lu", n);
    }
    putchar('\n');
}

int main(void)
{
    int c, tiene;
    unsigned long v;
    v = 0;
    tiene = 0;
    for (;;) {
        c = getchar();
        if (c >= '0' && c <= '9') {
            v = v * 10 + (c - '0');
            tiene = 1;
            continue;
        }
        if (tiene) factoriza(v);
        v = 0;
        tiene = 0;
        if (c == -1) break;
    }
    return 0;
}
