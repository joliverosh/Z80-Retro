/* c/ejemplos/vida.c - El juego de la vida de Conway en el C de Semilla.
 * Proyecto Semilla, version 1. */
/* El juego de la vida de Conway, en el C de Semilla. */
#define ANCHO 20
#define ALTO 10
#define GENERACIONES 4
#define CELDA(f, c) mundo[(f) * ANCHO + (c)]

char mundo[ANCHO * ALTO], nuevo[ANCHO * ALTO];

int vecinos(int f, int c)
{
    int n = 0, df, dc, ff, cc;
    for (df = -1; df <= 1; df++)
        for (dc = -1; dc <= 1; dc++) {
            ff = (f + df + ALTO) % ALTO; cc = (c + dc + ANCHO) % ANCHO;
            if ((df || dc) && CELDA(ff, cc)) n++;
        }
    return n;
}

void muestra(int g)
{
    char *s = "generacion ";
    int f, c;
    while (*s) putchar(*s++);
    putchar('0' + g);
    putchar('\n');
    for (f = 0; f < ALTO; f++) {
        for (c = 0; c < ANCHO; c++)
            putchar(CELDA(f, c) ? '#' : '.');
        putchar('\n');
    }
}

int main(void)
{
    int g, f, c, n, k;
    /* un planeador y un parpadeador */
    CELDA(1, 2) = CELDA(2, 3) = CELDA(3, 1) = CELDA(3, 2) = CELDA(3, 3) = 1;
    CELDA(6, 12) = CELDA(6, 13) = CELDA(6, 14) = 1;
    for (g = 0; g < GENERACIONES; g++) {
        muestra(g);
        for (f = 0; f < ALTO; f++)
            for (c = 0; c < ANCHO; c++) {
                n = vecinos(f, c);
                nuevo[f * ANCHO + c] = n == 3 || (n == 2 && CELDA(f, c));
            }
        for (k = 0; k < ANCHO * ALTO; k++) mundo[k] = nuevo[k];
    }
    muestra(GENERACIONES);
    return 0;
}
