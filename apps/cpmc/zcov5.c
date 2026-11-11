/* zcov5.c - parte de ZCALC que se carga de ZCALC.OVL: las ordenes /L /O /K /V
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include "zcalc.h"

/* /L: bloquear o desbloquear un rango */
static void cmd_lock(void)
{
    static uint8_t k, c1, r1, c2, r2, c, r;
    static cell *x;
    k = ask("Lock: L(ock) U(nlock)");
    if (k != 'L' && k != 'U') return;
    curref(sb);
    if (!input("Range: ", sb) || !prange(eb, &c1, &r1, &c2, &r2)) return;
    for (r = r1; r <= r2 && r >= r1; r++)
        for (c = c1; c <= c2; c++) {
            x = find(c, r);
            if (k == 'L') {
                if (!x && !(x = newcell(c, r, K_LAB, 0))) { msg("Memory full"); return; }
                x->f |= 0x40;
            } else if (x) {
                x->f &= ~0x40;
                if (KIND(x) == K_LAB && !x->n && !x->f) delcell(c, r);
            }
        }
    modified = dirty = 1;
}
/* /O: ordenar las filas de un rango por una columna */
static uint8_t *srow, *smap, skc, sdesc;   /* en el heap mientras se ordena */
/* el texto de una celda para ordenar (el de su formula si da texto) */
static void stext(cell *x, char *o)
{
    static uint8_t n;
    static char *p;
    if (KIND(x) == K_FRM) { p = STRP(x); n = STRN(x); } else { p = (char *)x->d; n = x->n; }
    if (n > 40) n = 40;
    memcpy(o, p, n); o[n] = 0;
}
/* compara las claves de las filas a y b: <0, 0, >0 */
static int8_t skey(uint8_t a, uint8_t b)
{
    static cell *x, *y;
    static uint8_t ka, kb;
    static val va, vb;
    x = find(skc, a); y = find(skc, b);
    ka = !x ? 3 : KIND(x) < K_NUM || VT(x) == V_STR ? 2 : VT(x) ? 1 : 0;   /* numero, error, texto, vacia */
    kb = !y ? 3 : KIND(y) < K_NUM || VT(y) == V_STR ? 2 : VT(y) ? 1 : 0;
    if (ka != kb) return ka < kb ? -1 : 1;
    if (ka == 0) return ncmp(NUMP(x), NUMP(y));
    if (ka == 2) {
        stext(x, sb); stext(y, eb);
        for (ka = 0; sb[ka] && (sb[ka] & 0xDF) == (eb[ka] & 0xDF); ka++) ;
        return (sb[ka] & 0xDF) < (eb[ka] & 0xDF) ? -1 : (sb[ka] & 0xDF) > (eb[ka] & 0xDF);
    }
    return 0;
}
static void cmd_sort(void)
{
    static uint8_t c1, r1, c2, r2, mc, mr, i, j, t, n;
    static cell *x;
    static int8_t s;
    if (!usedmax(&mc, &mr)) return;
    strcpy(sb, "A1:"); refname(sb + 3, mc, mr, 0);
    if (!input("Sort rows: ", sb) || !prange(eb, &c1, &r1, &c2, &r2)) return;
    colname(sb, cc);
    if (!input("By column: ", sb)) return;
    strcat(eb, "1");
    if (!isarg(eb, &skc, &t)) return;
    sdesc = ask("A(scending) D(escending)") == 'D';
    n = r2 - r1 + 1;
    if (!(srow = zalloc(2 * NR))) { msg("Memory full"); return; }
    smap = srow + NR;
    for (i = 0; i < n; i++) srow[i] = r1 + i;
    for (i = 1; i < n; i++)                  /* por insercion: los iguales no cambian de orden */
        for (j = i; j > 0; j--) {
            s = skey(srow[j - 1], srow[j]);
            if (sdesc) s = -s;
            if (s <= 0) break;
            t = srow[j]; srow[j] = srow[j - 1]; srow[j - 1] = t;
        }
    for (i = 0; i < n; i++) smap[srow[i] - r1] = i;   /* fila vieja -> lugar nuevo */
    FOR_CELLS(x)
        if (x->c >= c1 && x->c <= c2 && x->r >= r1 && x->r <= r2) {
            t = r1 + smap[x->r - r1];
            if (KIND(x) == K_FRM) shiftform(TOK(x), 0, (int16_t)t - x->r);
            x->r = t;
        }
    zfree(srow);
    rehash();
    modified = dirty = 1;
}

/* /K copia un rango al portapapeles (copias de las celdas, fuera de la hoja);
   /V lo pega con su esquina en el cursor, con las referencias relativas corridas */
static void cmd_copy(void)
{
    static uint8_t c1, r1, c2, r2, n;
    static cell *x, *y, *nx;
    curref(sb);
    if (!input("Copy range: ", sb) || !prange(eb, &c1, &r1, &c2, &r2)) return;
    for (x = clip; x; x = nx) { nx = x->nx; zfree(x); }
    clip = 0; n = 0;
    FOR_CELLS(x)
        if (x->c >= c1 && x->c <= c2 && x->r >= r1 && x->r <= r2) {
            if (!(y = zalloc(sizeof(cell) - 1 + x->n))) { msg("Memory full"); return; }
            memcpy(y, x, sizeof(cell) - 1 + x->n);
            if (KIND(y) == K_FRM) { SETVT(y, 0); memset(y->d, 0, 6); }
            y->nx = clip; clip = y; n++;
        }
    kc = c1; kr = r1;
    utoa_(n, sb); strcpy(sb + ndig(n), " cells copied; /V pastes them at the cursor");
    msg(sb);
}
static void cmd_paste(void)
{
    static cell *x;
    static int16_t c, r;
    if (!clip) { msg("Nothing copied (/K copies)"); return; }
    for (x = clip; x; x = x->nx) {
        c = (int16_t)cc + x->c - kc; r = (int16_t)cr + x->r - kr;
        if (c > NC || r > NR) continue;
        if (copycell(x, c, r)) { msg("Memory full"); return; }
    }
}
void ovl_entry(uint8_t op)
{
    if (op == 'L') cmd_lock();
    else if (op == 'O') cmd_sort();
    else if (op == 'K') cmd_copy();
    else cmd_paste();
}
