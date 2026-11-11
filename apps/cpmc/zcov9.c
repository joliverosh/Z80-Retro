/* zcov9.c - parte de ZCALC que se carga de ZCALC.OVL: guardar una hoja de Lotus 1-2-3
   (.WKS): los textos, los numeros, los anchos y los valores de las formulas.
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include "zcalc.h"

static void o16(uint16_t v) { oc(v & 255); oc(v >> 8); }
static void rec(uint16_t t, uint16_t n) { o16(t); o16(n); }
/* en zcalc_a.s: los primeros 53 bits de m / d (m de 8 bytes), y m * 10 */
uint8_t bdiv(uint8_t *m, uint32_t d, uint8_t *q) __sdcccall(0);
uint8_t bx10(uint8_t *m) __sdcccall(0);
/* num -> double de IEEE (8 bytes, el bajo primero): m * 10^e con enteros de 64 bits
   (m / 10^-e bit a bit); lo muy grande o muy chico se lleva antes a 30 bits con el num */
static void n2d(const num *v, uint8_t *d)
{
    static num t, two, lim;
    static uint8_t m8[8], q[8];
    static uint32_t dv;
    static int16_t k, ex;
    static uint8_t neg, e;
    memset(d, 0, 8);
    if (!v->m) return;
    neg = v->m < 0;
    t = *v; if (neg) t.m = -t.m;
    k = 0;
    if (t.e < -9) {                      /* muy chico: m de 30 bits por 2^k */
        nset(&two, 2);
        mk32(&lim, (uint32_t)1 << 29, 0, 0);
        while (ncmp(&t, &lim) < 0) { nmul(&t, &t, &two); k--; }
        ntrunc(&t, &t);
    }
    memset(m8, 0, 8);
    memcpy(m8, &t.m, 4);
    for (e = t.e; (int8_t)e > 0; e--)
        if (bx10(m8)) return;            /* mas de 1.8E19: no hace falta tanto */
    for (dv = 1; e; e++) dv = (dv << 3) + (dv << 1);
    k += 64 - bdiv(m8, dv, q);           /* valor = q * 2^k, q de 53 bits */
    ex = k + 52 + 1023;
    if (ex <= 0 || ex >= 2047) return;
    memcpy(d, q, 6);
    d[6] = (ex & 15) << 4 | (q[6] & 15);
    d[7] = neg << 7 | ex >> 4;
}
static uint8_t lfmt(uint8_t f)
{
    f &= 15;
    if (f >= 3 && f <= 12) return 0x80 | (f - 3);       /* fijo con decimales */
    if (f == 1) return 0xF1;                            /* general */
    if (f == 13) return 0xF2;                           /* fecha */
    return 0xFF;
}
static void label(cell *x, const char *s, uint8_t n, char pre)
{
    rec(15, n + 7);
    oc(0xFF); o16(x->c - 1); o16(x->r - 1);
    oc(pre);
    while (n--) oc(*s++);
    oc(0);
}
static void wks(void)
{
    static cell *x;
    static uint8_t mc, mr, i, n;
    static uint8_t d[8];
    static num *v;
    static int16_t iv;
    if (!usedmax(&mc, &mr)) return;
    strcpy(sb, fname_);
    if (strchr(sb, '.')) *strchr(sb, '.') = 0;
    if (*sb) strcat(sb, ".WKS");
    if (!input("1-2-3 file: ", sb) || !eb[0]) return;
    defext(eb, ".WKS");
    if (ofile(eb)) { msg("Can't create file"); return; }
    rec(0, 2); o16(0x0404);
    rec(6, 8); o16(0); o16(0); o16(mc - 1); o16(mr - 1);
    for (i = 1; i <= NC; i++) if (cw[i]) { rec(8, 3); o16(i - 1); oc(cw[i]); }
    FOR_CELLS(x) {
        if (KIND(x) == K_LAB) label(x, (char *)x->d, x->n > 239 ? 239 : x->n, (x->f & 0x30) == 0x20 ? '"' : '\'');
        else if (KIND(x) == K_REP) label(x, (char *)x->d, x->n > 239 ? 239 : x->n, '\\');
        else if (VT(x) == V_STR) label(x, STRP(x), STRN(x), '\'');
        else if (VT(x)) label(x, VT(x) == V_ERR ? "ERROR" : "NA", VT(x) == V_ERR ? 5 : 2, '"');
        else {
            v = NUMP(x);
            n = v->e >= 0 && v->e <= 4;
            iv = ntoi(v);
            if (n) { nset((num *)d, iv); n = !memcmp(d, v, 5); }   /* entero chico: INTEGER */
            if (n) { rec(13, 7); oc(lfmt(x->f)); o16(x->c - 1); o16(x->r - 1); o16(iv); }
            else {
                n2d(v, d);
                rec(14, 13); oc(lfmt(x->f)); o16(x->c - 1); o16(x->r - 1);
                for (i = 0; i < 8; i++) oc(d[i]);
            }
        }
    }
    rec(1, 0);
    if (oclose()) msg("Disk full");
}
void ovl_entry(uint8_t op)
{
    (void)op;
    wks();
}
