/* zcov8.c - parte de ZCALC que se carga de ZCALC.OVL: leer hojas de Lotus 1-2-3
   (.WKS y .WK1): los textos, los numeros y los anchos de columna; las formulas quedan
   con su valor y en la lista wkl, que zcova vuelve formulas de ZCALC.
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include "zcalc.h"



static uint8_t rb[256];          /* el registro */
static uint16_t rt, rl;          /* su tipo y su largo */

static uint8_t rd16(uint16_t *v)
{
    static int a, b;
    a = rdc(); b = rdc();
    if (a < 0 || b < 0) return 1;
    *v = (uint8_t)a | (uint16_t)(uint8_t)b << 8;
    return 0;
}
static uint8_t rdrec(void)
{
    static uint16_t i;
    static int ch;
    if (rd16(&rt) || rd16(&rl)) return 1;
    for (i = 0; i < rl; i++) {
        if ((ch = rdc()) < 0) return 1;
        if (i < sizeof rb) rb[i] = ch;
    }
    return 0;
}
/* double de IEEE (8 bytes, el bajo primero) -> num, con 9 cifras */
static void d2n(const uint8_t *d, num *v)
{
    static uint32_t m;
    static int16_t ex;
    static num t, two;
    ex = ((uint16_t)(d[7] & 0x7F) << 4) | (d[6] >> 4);
    if (!ex) { nset(v, 0); return; }
    /* los 30 bits altos de la mantisa (con el 1 de adelante) */
    ((uint8_t *)&m)[0] = d[3] << 1 | d[2] >> 7;
    ((uint8_t *)&m)[1] = d[4] << 1 | d[3] >> 7;
    ((uint8_t *)&m)[2] = d[5] << 1 | d[4] >> 7;
    ((uint8_t *)&m)[3] = (d[6] & 15 | 16) << 1 | d[5] >> 7;
    ex -= 1023 + 29;
    while (!(m & 1)) { m >>= 1; ex++; }    /* sin ceros abajo: 0.5 sale exacto */
    mk32(v, m, d[7] >> 7, 0);
    nset(&two, 2);
    nset(&t, ex);
    npow(&t, &two, &t);
    nmul(v, v, &t);
}
static uint16_t w16(const uint8_t *p) { return p[0] | (uint16_t)p[1] << 8; }

static uint8_t wks(const char *name)
{
    static uint8_t c, r, n, e, i;
    static num v;
    static cell *x;
    static uint8_t *p;
    if (!mkfcb(&inf, name) || fopen(&inf)) return 1;
    inp = 128;
    clearall();
    gw = 9; gnf = 1; autoc = 1; nnm = 0;
    memset(cw, 0, sizeof cw);
    e = 0;
    if (rdrec() || rt != 0) { fclose(&inf); return 2; }
    while (!rdrec() && rt != 1) {
        if (rt >= 12 && rt <= 16 && rl >= 5) {
            c = w16(rb + 1) + 1; r = w16(rb + 3) + 1;
            if (rb[1 + 1] || rb[3 + 1] || c > NC || r > NR) { e = 2; continue; }
            n = 0;
            if (rt == 13) { nset(&v, (int16_t)w16(rb + 5)); n = 1; }
            else if (rt == 14) { d2n(rb + 5, &v); n = 1; }
            else if (rt == 15) {
                i = rb[5] == '"' ? 0x20 : 0;       /* " a la derecha */
                if (rb[5] == '\\') n = setcell(c, r, (char *)rb + 6, 2);
                else n = setcell(c, r, (char *)rb + 6, 1);
                if (n == 2) { e = 3; break; }
                if ((x = find(c, r))) x->f = i;
                continue;
            } else if (rt == 16) {               /* formula: su valor, y a la lista */
                d2n(rb + 5, &v); n = 1;
                if (rl <= sizeof rb && rl > 15 && rl - 15 < 250 && (p = zalloc(rl - 15 + 5))) {
                    *(uint8_t **)p = wkl; wkl = p;
                    p[2] = c; p[3] = r; p[4] = rl - 15;
                    memcpy(p + 5, rb + 15, rl - 15);
                }
            }
            if (n) {
                if (!nplain(sb, &v, -1, 30)) nsci(sb, &v, 22);
                if (setcell(c, r, sb, 0) == 2) { e = 3; break; }
            }
            if ((x = find(c, r)) && (rb[0] & 0x70) == 0 && (rb[0] & 15) <= 9) x->f = (x->f & 0xF0) | ((rb[0] & 15) + 3);
            else if (x && (rb[0] & 0x70) == 0x20) x->f = (x->f & 0xF0) | 5;
        } else if (rt == 8 && rl >= 3) {          /* ancho de columna */
            c = w16(rb) + 1;
            if (c <= NC && rb[2] >= 3 && rb[2] <= 40) cw[c] = rb[2];
        } else if (rt == 2 && rl >= 1) autoc = rb[0] != 0;   /* recalculo */
    }
    fclose(&inf);
    strncpy(fname_, name, 15);
    return e;
}
void ovl_entry(uint8_t op)
{
    (void)op;
    ovlret = wks(eb);
    if (ovlret == 1) msg("File not found");
    else if (ovlret == 2) msg("Some cells could not be read");
    else if (ovlret == 3) msg("Memory full");
}
