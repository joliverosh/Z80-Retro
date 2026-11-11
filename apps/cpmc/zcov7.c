/* zcov7.c - parte de ZCALC que se carga de ZCALC.OVL: el grafico de barras (/X)
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include "zcalc.h"

#define MAXB 34                  /* barras */
#define CH 17                    /* filas del grafico */
#define CTOP 3                   /* su primera fila en pantalla */
#define CX 11                    /* su primera columna */

static num bv[MAXB];             /* los valores */
static int8_t bh[MAXB];          /* su alto en filas (con signo) */
static uint8_t bc[MAXB], br[MAXB];   /* de que celda sale el rotulo */
static uint8_t nb;

/* el valor de una celda (0 si no es un numero) */
static void cval(cell *x, num *v)
{
    nset(v, 0);
    if (x && KIND(x) >= K_NUM && !VT(x)) *v = *NUMP(x);
}
/* filas que ocupa v en un grafico donde span ocupa CH filas */
static int8_t rows(const num *v, const num *span)
{
    static num t, k;
    ndiv(&t, v, span);
    nset(&k, CH);
    nmul(&t, &t, &k);
    nround(&t, &t, 0);
    return (int8_t)ntoi(&t);
}
static void ylabel(uint8_t row, const num *v)
{
    gotoxy(1, row);
    fmtnum(sb, v, 1, 9);
    pstr(sb);
}
static void chart(void)
{
    static uint8_t c1, r1, c2, r2, l1, m1, l2, m2, c, r, i, j, w, x, haslab, zrow;
    static num top, bot, span, z;
    static char title[40];
    curref(sb);
    if (!input("Chart values: ", sb) || !prange(eb, &c1, &r1, &c2, &r2)) return;
    haslab = 0;
    if (input("Labels (Enter = none): ", "") && eb[0]) {
        if (!prange(eb, &l1, &m1, &l2, &m2)) { msg("Bad range"); return; }
        haslab = 1;
    }
    if (!input("Title: ", "")) return;
    strncpy(title, eb, 39); title[39] = 0;
    nb = 0;
    nset(&top, 0); nset(&bot, 0);
    for (r = r1; r <= r2 && r >= r1; r++)
        for (c = c1; c <= c2; c++) {
            if (nb == MAXB) break;
            cval(find(c, r), &bv[nb]);
            if (ncmp(&bv[nb], &top) > 0) top = bv[nb];
            if (ncmp(&bv[nb], &bot) < 0) bot = bv[nb];
            bc[nb] = 0;
            if (haslab) {                    /* el rotulo: el que le toca en el rango de rotulos */
                i = (r - r1) * (c2 - c1 + 1) + (c - c1);
                if (l1 == l2) { bc[nb] = l1; br[nb] = m1 + i; }
                else { bc[nb] = l1 + i; br[nb] = m1; }
            }
            nb++;
        }
    if (!nb) return;
    nset(&z, 0);
    nset(&span, 0);
    span = bot; span.m = -span.m;
    nadd(&span, &top, &span);            /* top - bot */
    if (!span.m) { msg("All values are zero"); return; }
    for (i = 0; i < nb; i++) bh[i] = rows(&bv[i], &span);
    zrow = rows(&top, &span);            /* filas sobre el cero */
    for (w = 9; w > 2 && nb * w > 80 - CX; w--) ;
    pstr(CLS);
    gotoxy((80 - strlen(title)) >> 1, 1);
    pstr(title);
    ylabel(CTOP, &top);
    if (bot.m) ylabel(CTOP + CH - 1, &bot);
    if (zrow > 0 && zrow < CH) ylabel(CTOP + zrow, &z);
    for (j = 0; j < CH; j++) { gotoxy(CX - 1, CTOP + j); putch('|'); }
    gotoxy(CX - 1, CTOP + zrow); for (i = 0; i < nb * w + 1; i++) putch('-');
    for (i = 0; i < nb; i++) {
        x = CX + i * w;
        for (j = 0; j < CH; j++) {          /* la fila j (0 arriba) */
            int8_t d = (int8_t)zrow - (int8_t)j;   /* > 0 sobre el cero */
            if ((bh[i] > 0 && d > 0 && d <= bh[i]) || (bh[i] < 0 && d < 0 && -d <= -bh[i])) {
                gotoxy(x, CTOP + j);
                pstr(INV);
                for (c = 1; c < w; c++) putch(' ');
                pstr(NORM);
            }
        }
        if (bc[i] && br[i] <= NR) {
            gotoxy(x, CTOP + CH + 1);
            cellstr(sb, bc[i], br[i], w - 1);
            pstr(sb);
        }
    }
    gotoxy(1, 24);
    pstr("Press any key.");
    getk();
    pstr(CLS);
    dirty = 1;
}
void ovl_entry(uint8_t op)
{
    (void)op;
    chart();
}
