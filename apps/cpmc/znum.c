/* znum.c - lo de los numeros decimales de 9 cifras que esta en C (lo comparten ZCALC
   y ZBAS; el resto esta en znum_a.s)
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include "znum.h"

static uint32_t uabs(int32_t m) { return m < 0 ? -(uint32_t)m : (uint32_t)m; }
static void nzero(num *x) { x->m = 0; x->e = 0; }
void nset(num *x, int16_t i) { x->m = i; x->e = 0; if (!i) return; while (!(x->m % 10)) { x->m /= 10; x->e++; } }

void nsub(num *r, const num *a, const num *b)
{
    static num t;
    t = *b; t.m = -t.m;
    nadd(r, a, &t);
}
int8_t ncmp(const num *a, const num *b)
{
    static num t;
    nsub(&t, a, b);
    return t.m < 0 ? -1 : t.m > 0;
}
static uint8_t nisint(const num *a) { return a->e >= 0; }
/* a entero de 16 bits (saturado) */
int16_t ntoi(const num *a) __sdcccall(0)
{
    static num t;
    static int32_t v;
    static int8_t e;
    ntrunc(&t, a);
    v = t.m; e = t.e;
    while (e > 0) { if (v > 32767 || v < -32767) break; v *= 10; e--; }
    if (v > 32767) return 32767;
    if (v < -32767) return -32767;
    return (int16_t)v;
}
uint8_t nsqrt(num *r, const num *a) __sdcccall(0)
{
    static num x;
    static num y;
    static num h;
    static uint8_t i;
    static int16_t ex;
    if (a->m < 0) return 1;
    if (!a->m) { nzero(r); return 0; }
    ex = ndig(uabs(a->m)) - 1 + a->e;      /* a = d.ddd * 10^ex */
    x.m = 3; x.e = (ex < 0 ? ex - 1 : ex) / 2;
    h.m = 5; h.e = -1;
    for (i = 0; i < 30; i++) {            /* Newton: x = (x + a/x) / 2 */
        ndiv(&y, a, &x);
        nadd(&y, &y, &x);
        nmul(&y, &y, &h);
        if (y.m == x.m && y.e == x.e) break;
        x = y;
    }
    *r = y;
    return 0;
}
void npow(num *r, const num *a, const num *b) __sdcccall(0)
{
    static num res;
    static num base;
    static int16_t n;
    static uint8_t neg;
    if (!nisint(b) || ntoi(b) > 9999 || ntoi(b) < -9999) { nerr = 1; return; }
    n = ntoi(b);
    neg = n < 0;
    if (neg) n = -n;
    nset(&res, 1);
    base = *a;
    while (n && !nerr) {
        if (n & 1) nmul(&res, &res, &base);
        n >>= 1;
        if (n) nmul(&base, &base, &base);
    }
    if (neg) { nset(&base, 1); ndiv(&res, &base, &res); }
    *r = res;
}

