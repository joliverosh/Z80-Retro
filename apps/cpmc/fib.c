/* FIB - los numeros de Fibonacci, con todas sus cifras.
   FIB          los primeros 100
   FIB n        F(n) exacto, con cuantas cifras tiene y cuanto tardo (n hasta 30000)
   FIB n m      de F(n) a F(m)
   Los numeros van en BCD empacado (dos cifras por byte) y solo se suman:
   F(k+1) = F(k) + F(k-1), con ADC y DAA (fib_a.s), sin pasar nunca a binario.
   (C) OLIVEROS 2026 */
#include "cpm.h"

#define MAXN 30000U
#define LMAX 3200                    /* F(30000) tiene 6270 cifras: 3135 bytes */
uint8_t addbcd(uint8_t *a, const uint8_t *b, uint16_t n) __sdcccall(0);
static uint8_t x[LMAX], y[LMAX];
static uint8_t *pa, *pb;             /* F(k-1) y F(k), el byte de abajo primero */
static uint16_t lb;                  /* bytes de F(k) */
static uint16_t k;

static void reset(void)              /* F(0) y F(1) */
{
    uint16_t i;
    for (i = 0; i < LMAX; i++) x[i] = y[i] = 0;
    pa = x; pb = y;
    pb[0] = 1; lb = 1;
    k = 1;
}
static void step(void)               /* pa = pa + pb y se cambian los papeles */
{
    uint8_t *t;
    if (addbcd(pa, pb, lb)) pa[lb++] = 1;
    else if (pa[lb]) lb++;           /* (no pasa: F(k-1) nunca es mas largo) */
    t = pa; pa = pb; pb = t;
    k++;
}
static uint16_t digits(void)
{
    return (lb - 1) * 2 + (pb[lb - 1] >= 0x10 ? 2 : 1);
}
static uint8_t col;
static void outd(uint8_t d)
{
    putch('0' + d);
    if (++col == 72) { pstr("\n"); col = 0; }
}
static void show(void)               /* F(k) entero; los largos, en lineas de 72 */
{
    uint16_t i = lb;
    uint8_t v;
    col = 0;
    if (digits() > 60) pstr("\n");
    v = pb[--i];
    if (v >= 0x10) outd(v >> 4);
    outd(v & 15);
    while (i--) {
        v = pb[i];
        outd(v >> 4); outd(v & 15);
        if (!(i & 63) && brk()) { pstr("\n(stopped)"); break; }
    }
    pstr("\n");
}
static uint16_t num(char *w)
{
    uint32_t v = 0;
    if (!w || *w < '0' || *w > '9') return 0xFFFF;
    while (*w >= '0' && *w <= '9') { v = v * 10 + *w++ - '0'; if (v > MAXN) return 0xFFFE; }
    return *w ? 0xFFFF : (uint16_t)v;
}
void main(void)
{
    char *p = args(), *w1 = nextarg(&p), *w2 = nextarg(&p);
    uint16_t n, m, t0, t;
    reset();
    if (!w1 || !*w1) {               /* los primeros 100 */
        pstr("The first 100 Fibonacci numbers:\n\nF(0)  = 0\n");
        for (;;) {
            pf("F(%u)%s= ", k, k < 10 ? "  " : k < 100 ? " " : "");
            show();
            if (k == 100 || brk()) break;
            step();
        }
        pstr("\nFIB n shows F(n) (n up to 30000); FIB n m, from F(n) to F(m).\n");
        return;
    }
    n = num(w1);
    m = w2 && *w2 ? num(w2) : n;
    if (n == 0xFFFF || m == 0xFFFF) { pstr("Usage: FIB [n [m]]   (n and m up to 30000)\n"); return; }
    if (n == 0xFFFE || m == 0xFFFE) { pstr("n can go up to 30000 (F(30000) has 6270 digits).\n"); return; }
    if (m < n) { t = n; n = m; m = t; }
    if (n == 0) { pstr("F(0) = 0\n"); if (!m) return; n = 1; }
    t0 = ticks();
    while (k < n) {
        step();
        if (!(k & 127) && brk()) { pf("(stopped at F(%u))\n", k); return; }
    }
    t = ticks() - t0;
    for (;;) {
        pf("F(%u) = ", k);
        show();
        if (n == m) {
            pf("%u digits", digits());
            if (n > 500) pf(", worked out in %u.%u s", t / tps(), t % tps() * 10 / tps());
            pstr("\n");
            return;
        }
        if (k >= m || brk()) return;
        step();
    }
}
