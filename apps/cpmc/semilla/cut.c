/* c/ejemplos/cut.c - cut-milla: corta campos de cada linea.
 * Proyecto Semilla, version 1. */
/* cut-milla: filtro de stdin a stdout.  La 1ra linea de la entrada son las
   opciones: "-dX" (delimitador X, por omision tabulador) y "-fLISTA" (campos
   separados por coma, como 1,3).  Las lineas sin delimitador salen enteras,
   como en `cut`. */
#include <stdio.h>
#include <string.h>

int sel[64];
int delim;

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

void procesa(char *s)
{
    int k, i, j, first, hayd;
    hayd = 0;
    for (i = 0; s[i]; i++)
        if (s[i] == delim) hayd = 1;
    if (!hayd) {
        printf("%s\n", s);
        return;
    }
    k = 1; i = 0; first = 1;
    for (;;) {
        j = i;
        while (s[j] && s[j] != delim) j++;
        if (k < 64 && sel[k]) {
            if (!first) putchar(delim);
            while (i < j) putchar(s[i++]);
            first = 0;
        }
        if (!s[j]) break;
        i = j + 1;
        k++;
    }
    putchar('\n');
}

int main(void)
{
    char op[256], b[512];
    int i, n, num;
    linea(op, 256);
    delim = 9;
    for (i = 0; i < 64; i++) sel[i] = 0;
    i = 0;
    while (op[i]) {
        if (op[i] == '-' && op[i + 1] == 'd') {
            delim = op[i + 2];
            i += 3;
        } else if (op[i] == '-' && op[i + 1] == 'f') {
            i += 2;
            num = 0;
            while (op[i] >= '0' && op[i] <= '9') {
                num = num * 10 + op[i] - '0';
                i++;
                if (op[i] == ',' || !op[i]) {
                    if (num < 64) sel[num] = 1;
                    num = 0;
                    if (op[i] == ',') i++;
                }
            }
        } else {
            i++;
        }
    }
    while ((n = linea(b, 512)) != -1) procesa(b);
    return 0;
}
