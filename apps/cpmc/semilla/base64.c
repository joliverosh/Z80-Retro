/* c/ejemplos/base64.c - base64-milla: codifica o decodifica base64 (RFC 4648).
 * Proyecto Semilla, version 1. */
/* base64-milla: filtro de stdin a stdout.  La 1ra linea de la entrada son las
   opciones: vacia para codificar, "-d" para decodificar.  Codifica en lineas
   de 76 caracteres, igual que `base64`. */
#include <stdio.h>

char *alfabeto(void) { return "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"; }

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

int valor(int c)
{
    char *t;
    int i;
    t = alfabeto();
    for (i = 0; i < 64; i++)
        if (t[i] == c) return i;
    return -1;
}

void codifica(void)
{
    int buf[3], n, c, col;
    long v;
    char *t;
    t = alfabeto();
    col = 0;
    for (;;) {
        n = 0;
        while (n < 3) {
            c = getchar();
            if (c == -1) break;
            buf[n++] = c;
        }
        if (n == 0) break;
        v = 0;
        if (n > 0) v = v | ((long)buf[0] << 16);
        if (n > 1) v = v | ((long)buf[1] << 8);
        if (n > 2) v = v | (long)buf[2];
        putchar(t[(v >> 18) & 63]);
        putchar(t[(v >> 12) & 63]);
        if (n > 1) putchar(t[(v >> 6) & 63]); else putchar('=');
        if (n > 2) putchar(t[v & 63]); else putchar('=');
        col = col + 4;
        if (col == 76) { putchar('\n'); col = 0; }
    }
    if (col) putchar('\n');
}

void decodifica(void)
{
    int c, v, q[4], n;
    n = 0;
    for (;;) {
        c = getchar();
        if (c == -1) break;
        if (c == '=') break;
        v = valor(c);
        if (v < 0) continue;
        q[n++] = v;
        if (n == 4) {
            putchar((q[0] << 2) | (q[1] >> 4));
            putchar(((q[1] & 15) << 4) | (q[2] >> 2));
            putchar(((q[2] & 3) << 6) | q[3]);
            n = 0;
        }
    }
    if (n >= 2) putchar((q[0] << 2) | (q[1] >> 4));
    if (n >= 3) putchar(((q[1] & 15) << 4) | (q[2] >> 2));
}

int main(void)
{
    char op[64];
    linea(op, 64);
    if (op[0] == '-' && op[1] == 'd') decodifica();
    else codifica();
    return 0;
}
