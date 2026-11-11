/* zcova.c - parte de ZCALC que se carga de ZCALC.OVL: las formulas de una hoja de
   Lotus 1-2-3, que zcov8 dejo en wkl, a formulas de ZCALC (las que se pueden escribir;
   las otras quedan con su valor)
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include "zcalc.h"



static uint8_t fc_, fr_;         /* la celda de la formula (para las relativas) */
static uint8_t sp_;              /* la pila de la formula: donde empieza cada operando en eb */
static uint8_t st[16];
static uint8_t ep;               /* lo que va de eb */
static uint8_t bad;

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

/* la formula en eb: put agrega texto */
static void put(const char *s)
{
    while (*s) { if (ep < MAXE - 1) eb[ep++] = *s; else bad = 1; s++; }
    eb[ep] = 0;
}
static void push_(void) { if (sp_ < 16) st[sp_++] = ep; else bad = 1; }
/* inserta s en la posicion p de eb */
static void ins(uint8_t p, const char *s)
{
    static uint8_t n;
    n = strlen(s);
    if (ep + n >= MAXE) { bad = 1; return; }
    memmove(eb + p + n, eb + p, ep - p + 1);
    memcpy(eb + p, s, n);
    ep += n;
}
/* columna o fila de una referencia: el bit 15 la hace relativa (un desplazamiento de 14 bits) */
static uint8_t rc(uint16_t v, uint8_t base, uint8_t *abs_)
{
    static int16_t d;
    *abs_ = !(v & 0x8000);
    if (v & 0x8000) { d = v & 0x3FFF; if (d >= 0x2000) d -= 0x4000; return base + d; }
    return v;
}
static void ref(const uint8_t *p)
{
    static uint8_t ac, ar, c, r;
    c = rc(w16(p), fc_, &ac) + 1;
    r = rc(w16(p + 2), fr_, &ar) + 1;
    if (c < 1 || c > NC || r < 1 || r > NR) { bad = 1; return; }
    ep += refname(eb + ep, c, r, ac | ar << 1);
    if (ep >= MAXE) bad = 1;
}
/* los nombres de las funciones de 1-2-3 que ZCALC tiene, por su codigo, y sus argumentos */
static const uint8_t fcode[] = { 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 43, 46, 47, 49, 50, 55, 59, 60, 61, 62,
                                 80, 81, 82, 83, 84, 86, 89, 56, 57, 58 };
static const char *const fnm[] = { "NA", "ERROR", "ABS", "INT", "SQRT", "LOG", "LN", "PI", "SIN", "COS", "TAN",
                                     "ATAN", "EXP", "MOD", "ISNA", "ISERROR", "TODAY", "IF", "DAY", "MONTH", "ROUND",
                                     "SUM", "AVG", "COUNT", "MIN", "MAX", "NPV", "IRR", "PMT", "PV", "FV" };
static const uint8_t fargs[] = { 0, 0, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 2, 1, 1, 0, 3, 1, 1, 2,
                                 255, 255, 255, 255, 255, 2, 2, 3, 3, 3 };
static void func(uint8_t i, uint8_t n)
{
    static uint8_t a, k, p0, p1, p2;
    if (!n) { push_(); put("@"); put(fnm[i]); return; }
    if (n > sp_) { bad = 1; return; }
    a = sp_ - n;
    if (i >= 28 && n == 3) {               /* @PMT @PV @FV de 1-2-3: (monto, tasa, plazo) -> (tasa, plazo, monto) */
        p0 = st[a]; p1 = st[a + 1]; p2 = st[a + 2];
        k = p1 - p0;
        if (k >= sizeof sb) { bad = 1; return; }
        memcpy(sb, eb + p0, k);            /* el monto, al final */
        memmove(eb + p0, eb + p1, ep - p1 + 1);
        ep -= k;
        memcpy(eb + ep, sb, k); ep += k; eb[ep] = 0;
        st[a + 1] = p2 - k;
        st[a + 2] = ep - k;
    }
    for (k = n - 1; k; k--) ins(st[a + k], ",");
    put(")");
    ins(st[a], "(");
    ins(st[a], fnm[i]);
    ins(st[a], "@");
    sp_ = a + 1;
}
static const char *const bops[] = { "+", "-", "*", "/", "^", "=", "<>", "<=", ">=", "<", ">" };
/* el codigo de la formula (rb + 15) -> texto de ZCALC en eb; 0 si no se pudo */
static uint8_t decomp(uint8_t *p, uint8_t *e)
{
    static uint8_t op, i, a;
    static num v;
    sp_ = 0; ep = 0; bad = 0; eb[0] = 0;
    put("+");
    while (p < e && !bad) {
        op = *p++;
        switch (op) {
        case 0:                            /* numero */
            push_(); d2n(p, &v); p += 8;
            if (!(op = nplain(eb + ep, &v, -1, 22))) op = nsci(eb + ep, &v, 22);
            ep += op;
            break;
        case 1: push_(); ref(p); p += 4; break;
        case 2:                            /* rango */
            push_(); ref(p); put(":"); ref(p + 4); p += 8;
            break;
        case 3: p = e; break;
        case 4: if (!sp_) { bad = 1; break; } ins(st[sp_ - 1], "("); put(")"); break;
        case 5: push_(); nset(&v, (int16_t)w16(p)); p += 2;       /* entero */
            ep += nplain(eb + ep, &v, -1, 22); break;
        case 8: case 23:                   /* signo */
            if (!sp_) { bad = 1; break; }
            ins(st[sp_ - 1], op == 8 ? "-" : "+");
            break;
        default:
            if (op >= 9 && op <= 19) {        /* binarios (#AND# y #OR# no estan) */
                if (sp_ < 2) { bad = 1; break; }
                ins(st[--sp_], bops[op - 9]);
                break;
            }
            if (op == 22) { bad = 1; break; }
            for (i = 0; i < sizeof fcode && fcode[i] != op; i++) ;
            if (i == sizeof fcode) { bad = 1; break; }
            if (fargs[i] == 255) func(i, *p++); else func(i, fargs[i]);
        }
    }
    if (sp_ != 1) bad = 1;
    return !bad;
}

/* wkl: una lista de formulas: siguiente (2), columna, fila, largo y el codigo */
void ovl_entry(uint8_t op)
{
    static uint8_t *p, *nx;
    static uint8_t c, r, f;
    static cell *x;
    (void)op;
    for (p = wkl; p; p = nx) {
        nx = *(uint8_t **)p;
        c = p[2]; r = p[3];
        fc_ = c - 1; fr_ = r - 1;
        x = find(c, r);
        f = x ? x->f : 0;
        if (decomp(p + 5, p + 5 + p[4]) && !setcell(c, r, eb, 0) && (x = find(c, r))) x->f = f;
        zfree(p);
    }
    wkl = 0;
    recalc();
    modified = 0;
    dirty = 1;
}
