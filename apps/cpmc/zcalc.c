/* ZCALC 1.0 - hoja de calculo para CP/M 2.2 y MP/M II (terminal ANSI de 80x24)
   ZCALC [archivo[.ZC]]
   63 columnas (A-BK) x 254 filas. Numeros decimales de 9 cifras: 0,1 y los
   centavos son exactos. Se maneja como las hojas de 1979: el cursor recorre la
   cuadricula, lo que se escribe va a la celda y las ordenes empiezan con '/'.
   Formulas: + - * / ^, comparaciones (= <> < > <= >=), referencias A1, $A$1,
   rangos A1:B5 (o A1...B5) y funciones @SUM @AVG @MIN @MAX @COUNT @LOOKUP
   @ABS @INT @ROUND @SQRT @MOD @IF @AND @OR @NOT @PI @NA @ERROR @ISNA @ISERROR.
   (C) OLIVEROS 2026 */
#include <string.h>
#include "cpm.h"

#define VERSION "1.0"            /* tambien en zcalc_a.s y en LEEME.md */

#define NC 63                    /* columnas */
#define NR 254                   /* filas */
#define GTOP 4                   /* fila de pantalla de la primera fila de la hoja */
#define GROWS 21                 /* filas de la hoja en pantalla */
#define LW 4                     /* ancho de los numeros de fila */
#define MAXE 120                 /* largo de una entrada */
#define MAXT 160                 /* bytes de una formula compilada */
#define MAXVC 26                 /* columnas en pantalla */

#define KUP 0x81
#define KDOWN 0x82
#define KRIGHT 0x83
#define KLEFT 0x84
#define KHOME 0x85
#define KEND 0x86
#define KDEL 0x87
#define KPGUP 0x88
#define KPGDN 0x89
#define ISARROW(k) ((k) >= KUP && (k) <= KLEFT)
#define INV ESC "[7m"
#define NORM ESC "[0m"
#define EOL ESC "[K"

extern char heap[];

/* ================================================================ memoria */
/* bloques con el tamano (2 bytes) delante; los libres en una lista por direccion */
typedef struct fb { uint16_t sz; struct fb *nx; } fb;
static fb *freel;
static uint16_t hfree;

static void *zalloc(uint16_t n)
{
    static fb **pp;
    static fb *b;
    static fb *r;
    n = (n + 3) & ~1;
    if (n < 4) n = 4;
    for (pp = &freel; (b = *pp); pp = &b->nx)
        if (b->sz >= n) {
            if (b->sz - n >= 8) {
                r = (fb *)((char *)b + n);
                r->sz = b->sz - n; r->nx = b->nx;
                *pp = r; b->sz = n;
            } else *pp = b->nx;
            hfree -= b->sz;
            return (char *)b + 2;
        }
    return 0;
}

static void zfree(void *p)
{
    static fb *b;
    static fb **pp;
    static fb *pv;
    b = (fb *)((char *)p - 2);
    pv = 0;
    for (pp = &freel; *pp && *pp < b; pp = &(*pp)->nx) pv = *pp;
    b->nx = *pp; *pp = b; hfree += b->sz;
    if (b->nx && (char *)b + b->sz == (char *)b->nx) { b->sz += b->nx->sz; b->nx = b->nx->nx; }
    if (pv && (char *)pv + pv->sz == (char *)b) { pv->sz += b->sz; pv->nx = b->nx; }
}

/* ================================================================ numeros */
/* valor = m * 10^e con |m| < 10^9; m sin ceros al final (0 tiene e = 0) */
typedef struct { int32_t m; int8_t e; } num;
enum { V_NUM, V_ERR, V_NA };
typedef struct { uint8_t t; num n; } val;

extern uint8_t nerr;             /* desbordamiento o division por cero (en zcalc_a.s) */
uint8_t ndig(uint32_t u) __sdcccall(0);
void mk32(num *x, uint32_t v, uint8_t neg, int16_t e) __sdcccall(0);
void nadd(num *r, const num *a, const num *b) __sdcccall(0);
void nmul(num *r, const num *a, const num *b) __sdcccall(0);
void ndiv(num *r, const num *a, const num *b) __sdcccall(0);
void nround(num *r, const num *a, int8_t d) __sdcccall(0);
void ntrunc(num *r, const num *a) __sdcccall(0);
static uint32_t uabs(int32_t m) { return m < 0 ? -(uint32_t)m : (uint32_t)m; }
static void nzero(num *x) { x->m = 0; x->e = 0; }
static void nset(num *x, int16_t i) { x->m = i; x->e = 0; if (!i) return; while (!(x->m % 10)) { x->m /= 10; x->e++; } }

static void nsub(num *r, const num *a, const num *b)
{
    static num t;
    t = *b; t.m = -t.m;
    nadd(r, a, &t);
}
static int8_t ncmp(const num *a, const num *b)
{
    static num t;
    nsub(&t, a, b);
    return t.m < 0 ? -1 : t.m > 0;
}
static uint8_t nisint(const num *a) { return a->e >= 0; }
/* a entero de 16 bits (saturado) */
static int16_t ntoi(const num *a)
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
static uint8_t nsqrt(num *r, const num *a)
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
static void npow(num *r, const num *a, const num *b)
{
    static num res;
    static num base;
    static int16_t n;
    static uint8_t neg;
    if (!nisint(b) || ntoi(b) > 99 || ntoi(b) < -99) { nerr = 1; return; }
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

/* cifras de u en o (sin 0 al final); devuelve cuantas */
static uint8_t utoa_(uint32_t u, char *o)
{
    static char t[10];
    static uint8_t n;
    static uint8_t i;
    n = 0;
    do { t[n++] = '0' + u % 10; u /= 10; } while (u);
    for (i = 0; i < n; i++) o[i] = t[n - 1 - i];
    return n;
}

/* x en decimal comun en o; dec >= 0: exactamente dec decimales (x ya redondeado).
   Devuelve el largo, o 0 si pasa de max */
static uint8_t nplain(char *o, const num *x, int8_t dec, uint8_t max)
{
    static char d[10];
    static uint8_t nd;
    static uint8_t n;
    static uint8_t i;
    static uint8_t neg;
    static int16_t e;
    static int16_t ip;
    static int16_t fp;
    static int16_t len;
    n = 0;
    neg = x->m < 0;
    e = x->e;
    nd = utoa_(uabs(x->m), d);
    if (e >= 0) { ip = nd + e; fp = 0; }
    else if (nd > -e) { ip = nd + e; fp = -e; }
    else { ip = 1; fp = -e; }
    if (dec >= 0 && fp < dec) fp = dec;
    len = neg + ip + (fp ? 1 + fp : 0);
    if (len > max) return 0;
    if (neg && x->m) o[n++] = '-';
    if (e >= 0) {
        for (i = 0; i < nd; i++) o[n++] = d[i];
        for (i = 0; i < e; i++) o[n++] = '0';
    } else if (nd > -e) {
        for (i = 0; i < ip; i++) o[n++] = d[i];
    } else o[n++] = '0';
    if (fp) {
        o[n++] = '.';
        i = 0;
        if (e < 0) {
            if (nd > -e) { for (i = ip; i < nd; i++) o[n++] = d[i]; i = nd - ip; }
            else { int16_t z; for (z = 0; z < -e - nd; z++) o[n++] = '0'; for (z = 0; z < nd; z++) o[n++] = d[z]; i = -e; }
        }
        for (; i < fp; i++) o[n++] = '0';
    }
    o[n] = 0;
    return n;
}
/* x como d.dddE+nn en a lo mas max caracteres; 0 si no cabe */
static uint8_t nsci(char *o, const num *x, uint8_t max)
{
    static char d[10];
    static num y;
    static uint8_t nd;
    static uint8_t n;
    static uint8_t md;
    static uint8_t el;
    static uint8_t neg;
    static uint8_t i;
    static int16_t ex;
    neg = x->m < 0;
    nd = ndig(uabs(x->m));
    ex = nd - 1 + x->e;
    el = (ex <= -10 || ex >= 10) ? 4 : 3;
    if (max < neg + 1 + el) return 0;
    md = max - neg - el;         /* cifras de la mantisa (con el punto) */
    if (md >= 3) md--; else md = 1;
    nround(&y, x, md - 1 - ex);
    nd = utoa_(uabs(y.m), d);
    ex = nd - 1 + y.e;
    n = 0;
    if (neg) o[n++] = '-';
    o[n++] = d[0];
    if (nd > 1) { o[n++] = '.'; for (i = 1; i < nd; i++) o[n++] = d[i]; }
    o[n++] = 'E';
    o[n++] = ex < 0 ? '-' : '+';
    if (ex < 0) ex = -ex;
    if (ex >= 10) o[n++] = '0' + ex / 10;
    o[n++] = '0' + ex % 10;
    o[n] = 0;
    return n;
}
/* formatos: 0 el global, 1 general, 2 grafico, 3+k: k decimales */
static void fmtnum(char *o, const num *x, uint8_t nf, uint8_t w)
{
    static num y;
    static int16_t ip;
    static uint8_t nd;
    if (nf >= 3) {
        nround(&y, x, nf - 3);
        if (nplain(o, &y, nf - 3, w)) return;
    } else {
        if (nplain(o, x, -1, w)) return;
        nd = ndig(uabs(x->m));
        ip = x->e >= 0 ? nd + x->e : (nd > -x->e ? nd + x->e : 1);
        if ((x->m < 0) + ip + 1 < w) {
            nround(&y, x, w - (x->m < 0) - ip - 1);
            if (y.m && nplain(o, &y, -1, w)) return;
        } else if ((x->m < 0) + ip <= w) {
            nround(&y, x, 0);
            if (y.m && nplain(o, &y, -1, w)) return;
        }
        if (nsci(o, x, w)) return;
    }
    memset(o, '>', w);
    o[w] = 0;
}
/* numero escrito: cifras, punto y exponente */
static const char *pnum(const char *s, num *x)
{
    static uint32_t u;
    static int16_t e;
    static int16_t ex;
    static uint8_t nd;
    static uint8_t dot;
    static uint8_t ns;
    u = 0;
    e = 0;
    ex = 0;
    nd = 0;
    dot = 0;
    ns = 0;
    for (;; s++) {
        if (*s == '.' && !dot && s[1] != '.') { dot = 1; continue; }
        if (*s < '0' || *s > '9') break;
        if (nd < 9) { u = u * 10 + (*s - '0'); if (u) nd++; if (dot) e--; }
        else if (!dot) e++;
    }
    if (*s == 'E' && ((s[1] >= '0' && s[1] <= '9') || ((s[1] == '+' || s[1] == '-') && s[2] >= '0' && s[2] <= '9'))) {
        s++;
        if (*s == '-') { ns = 1; s++; } else if (*s == '+') s++;
        while (*s >= '0' && *s <= '9') { if (ex < 200) ex = ex * 10 + (*s - '0'); s++; }
        e += ns ? -ex : ex;
    }
    nerr = 0;
    mk32(x, u, 0, e);
    return s;
}

/* ================================================================ celdas */
enum { K_LAB = 1, K_REP, K_NUM, K_FRM };
typedef struct cell {
    struct cell *nx;
    uint8_t c, r;                /* columna y fila (desde 1) */
    uint8_t k;                   /* clase */
    uint8_t f;                   /* formato: bits 0-3 numero, 4-5 alineacion */
    uint8_t g, st;               /* generacion del calculo y "calculando" */
    val v;
    uint8_t n;                   /* bytes de d */
    uint8_t d[1];                /* texto o formula compilada */
} cell;
#define NH 128
static cell *ht[NH];
#define HK(c, r) (((c) * 13 + (r)) & (NH - 1))
static uint8_t hb;
#define FOR_CELLS(x) for (hb = 0; hb < NH; hb++) for (x = ht[hb]; x; x = x->nx)

static cell *find(uint8_t c, uint8_t r)
{
    static cell *x;
    for (x = ht[HK(c, r)]; x; x = x->nx)
        if (x->c == c && x->r == r) return x;
    return 0;
}
static void unlink_(cell *x)
{
    static cell **pp;
    for (pp = &ht[HK(x->c, x->r)]; *pp; pp = &(*pp)->nx)
        if (*pp == x) { *pp = x->nx; return; }
}
static void delcell(uint8_t c, uint8_t r)
{
    static cell *x;
    x = find(c, r);
    if (x) { unlink_(x); zfree(x); }
}
static void link_(cell *x)
{
    static uint8_t h;
    h = HK(x->c, x->r);
    x->nx = ht[h];
    ht[h] = x;
}
/* celda nueva (reemplaza la que haya); 0 si no hay memoria */
static cell *newcell(uint8_t c, uint8_t r, uint8_t k, uint8_t n)
{
    static cell *x;
    static uint8_t f;
    x = find(c, r);
    f = x ? x->f : 0;
    if (x) { unlink_(x); zfree(x); }
    x = zalloc(sizeof(cell) - 1 + n);
    if (!x) return 0;
    memset(x, 0, sizeof(cell));
    x->c = c; x->r = r; x->k = k; x->f = f; x->n = n;
    link_(x);
    return x;
}
static void clearall(void)
{
    static cell *x;
    static cell *n;
    for (hb = 0; hb < NH; hb++) {
        for (x = ht[hb]; x; x = n) { n = x->nx; zfree(x); }
        ht[hb] = 0;
    }
}
/* vuelve a poner cada celda en su lista (las de c = 0 se borran) */
static void rehash(void)
{
    static cell *all;
    static cell *x;
    static cell *n;
    all = 0;
    for (hb = 0; hb < NH; hb++) {
        for (x = ht[hb]; x; x = n) { n = x->nx; x->nx = all; all = x; }
        ht[hb] = 0;
    }
    for (x = all; x; x = n) {
        n = x->nx;
        if (x->c) link_(x); else zfree(x);
    }
}

/* ================================================================ formulas */
enum { TK_END, TK_NUM, TK_REF, TK_RNG, TK_FN, TK_LE, TK_GE, TK_NE };
/* TK_NUM m(4) e(1); TK_REF c r fl; TK_RNG c1 r1 c2 r2 fl; TK_FN id.
   fl: bit 0 columna fija ($), 1 fila fija; en rangos 2 y 3 los del final.
   Una referencia borrada tiene c = 0 (#REF) */
enum { F_SUM, F_AVG, F_MIN, F_MAX, F_COUNT, F_LOOKUP, F_ABS, F_INT, F_ROUND, F_SQRT,
       F_MOD, F_IF, F_AND, F_OR, F_NOT, F_PI, F_NA, F_ERROR, F_ISNA, F_ISERR, NFN };
static const char *const fnn[NFN] = { "SUM", "AVG", "MIN", "MAX", "COUNT", "LOOKUP",
    "ABS", "INT", "ROUND", "SQRT", "MOD", "IF", "AND", "OR", "NOT", "PI", "NA", "ERROR",
    "ISNA", "ISERROR" };
/* argumentos: minimo y maximo (9 = los que sean) */
static const uint8_t fmin[NFN] = { 1, 1, 1, 1, 1, 2, 1, 1, 2, 1, 2, 3, 1, 1, 1, 0, 0, 0, 1, 1 };
static const uint8_t fmax[NFN] = { 9, 9, 9, 9, 9, 2, 1, 1, 2, 1, 2, 3, 9, 9, 1, 0, 0, 0, 1, 1 };

static uint8_t isup(char c) { return c >= 'A' && c <= 'Z'; }
static uint8_t isdig(char c) { return c >= '0' && c <= '9'; }

/* referencia A1, $A$1 ...; avanza *ps */
static uint8_t pref(const char **ps, uint8_t *c, uint8_t *r, uint8_t *fl)
{
    static const char *s;
    static uint16_t cc;
    static uint16_t rr;
    s = *ps;
    rr = 0;
    *fl = 0;
    if (*s == '$') { *fl |= 1; s++; }
    if (!isup(*s)) return 0;
    cc = *s++ - 'A' + 1;
    if (isup(*s)) cc = cc * 26 + (*s++ - 'A' + 1);
    if (cc > NC) return 0;
    if (*s == '$') { *fl |= 2; s++; }
    if (!isdig(*s)) return 0;
    while (isdig(*s)) { rr = rr * 10 + (*s++ - '0'); if (rr > NR) return 0; }
    if (!rr || isup(*s)) return 0;
    *c = cc; *r = rr; *ps = s;
    return 1;
}
static uint8_t colname(char *o, uint8_t c)
{
    if (c <= 26) { o[0] = 'A' + c - 1; o[1] = 0; return 1; }
    o[0] = 'A' + (c - 1) / 26 - 1; o[1] = 'A' + (c - 1) % 26; o[2] = 0;
    return 2;
}
static uint8_t refname(char *o, uint8_t c, uint8_t r, uint8_t fl)
{
    static uint8_t n;
    n = 0;
    if (!c) { strcpy(o, "#REF"); return 4; }
    if (fl & 1) o[n++] = '$';
    n += colname(o + n, c);
    if (fl & 2) o[n++] = '$';
    n += utoa_(r, o + n);
    o[n] = 0;
    return n;
}

/* compila s (en mayusculas) en o; devuelve el largo o 0 si hay un error */
static uint8_t tok(const char *s, uint8_t *o)
{
    static uint8_t n;
    static uint8_t c;
    static uint8_t r;
    static uint8_t fl;
    static uint8_t c2;
    static uint8_t r2;
    static uint8_t f2;
    static uint8_t i;
    static num x;
    static char nm[8];
    n = 0;
    if (*s == '=') s++;
    while (*s) {
        if (n > MAXT - 8) return 0;
        if (*s == ' ') { s++; continue; }
        if (isdig(*s) || (*s == '.' && isdig(s[1]))) {
            s = pnum(s, &x);
            if (nerr) return 0;
            o[n++] = TK_NUM;
            memcpy(o + n, &x.m, 4); o[n + 4] = x.e; n += 5;
            continue;
        }
        if (*s == '$' || isup(*s)) {
            if (pref(&s, &c, &r, &fl)) {
                if (*s == ':' || *s == '.') {
                    while (*s == ':' || *s == '.') s++;
                    if (!pref(&s, &c2, &r2, &f2)) return 0;
                    if (c2 < c) { i = c; c = c2; c2 = i; fl = (fl & 2) | (f2 & 1); f2 = (f2 & 2) | (fl & 1); }
                    if (r2 < r) { i = r; r = r2; r2 = i; i = fl; fl = (fl & 1) | (f2 & 2); f2 = (f2 & 1) | (i & 2); }
                    o[n++] = TK_RNG; o[n++] = c; o[n++] = r; o[n++] = c2; o[n++] = r2;
                    o[n++] = fl | (f2 << 2);
                } else {
                    o[n++] = TK_REF; o[n++] = c; o[n++] = r; o[n++] = fl;
                }
                continue;
            }
            if (*s == '$') return 0;
        }
        if (*s == '@' || isup(*s)) {
            if (*s == '@') s++;
            for (i = 0; isup(*s); s++) if (i < 7) nm[i++] = *s; else return 0;
            nm[i] = 0;
            for (i = 0; i < NFN && strcmp(nm, fnn[i]); i++) ;
            if (i == NFN) {
                if (!strcmp(nm, "AVERAGE")) i = F_AVG;
                else return 0;
            }
            o[n++] = TK_FN; o[n++] = i;
            continue;
        }
        if (*s == '<' && s[1] == '=') { o[n++] = TK_LE; s += 2; continue; }
        if (*s == '>' && s[1] == '=') { o[n++] = TK_GE; s += 2; continue; }
        if (*s == '<' && s[1] == '>') { o[n++] = TK_NE; s += 2; continue; }
        if (strchr("+-*/^(),=<>", *s)) { o[n++] = *s++; continue; }
        return 0;
    }
    o[n++] = TK_END;
    return n;
}

/* la formula compilada como texto */
static uint8_t dtok(const uint8_t *t, char *o, uint8_t max)
{
    static uint8_t n;
    static char b[24];
    static num x;
    n = 0;
    while (*t && n < max - 24) {
        switch (*t) {
        case TK_NUM:
            memcpy(&x.m, t + 1, 4); x.e = t[5]; t += 6;
            if (!nplain(b, &x, -1, 22)) nsci(b, &x, 22);
            strcpy(o + n, b); n += strlen(b);
            break;
        case TK_REF:
            n += refname(o + n, t[1], t[2], t[3]); t += 4;
            break;
        case TK_RNG:
            n += refname(o + n, t[1], t[2], t[5] & 3);
            o[n++] = ':';
            if (!t[1]) n -= 1, o[n] = 0;
            else n += refname(o + n, t[3], t[4], t[5] >> 2);
            t += 6;
            break;
        case TK_FN:
            o[n++] = '@'; strcpy(o + n, fnn[t[1]]); n += strlen(fnn[t[1]]); t += 2;
            break;
        case TK_LE: o[n++] = '<'; o[n++] = '='; t++; break;
        case TK_GE: o[n++] = '>'; o[n++] = '='; t++; break;
        case TK_NE: o[n++] = '<'; o[n++] = '>'; t++; break;
        default: o[n++] = *t++;
        }
    }
    o[n] = 0;
    return n;
}

/* ================================================================ calculo */
static const uint8_t *tp;        /* el que sigue en la formula */
static uint8_t synerr, chk;      /* chk: solo revisar la sintaxis */
static uint8_t gen = 1, depth, again, circ;
static void expr(val *v);

static void setv(val *v, int16_t i) { v->t = V_NUM; nset(&v->n, i); }
static void evalcell(cell *x)
{
    const uint8_t *sv;
    val v;
    if (x->k != K_FRM || x->g == gen) return;
    if (x->st) { x->v.t = V_ERR; circ = 1; return; }
    if (depth >= 12) { again = 1; return; }
    sv = tp; x->st = 1; depth++;
    tp = x->d;
    synerr = 0;
    expr(&v);
    if (synerr) v.t = V_ERR;
    x->v = v;
    depth--; x->st = 0; x->g = gen; tp = sv;
}
/* valor de una celda (vacia o con texto: 0; en rangos se saltan) */
static uint8_t cellv(val *v, cell *x)
{
    if (!x || x->k < K_NUM) return 0;
    if (x->k == K_FRM) evalcell(x);
    *v = x->v;
    return 1;
}
static void refval(val *v, uint8_t c, uint8_t r)
{
    setv(v, 0);
    if (!c) { v->t = V_ERR; return; }
    if (chk) return;
    cellv(v, find(c, r));
}
/* error o NA de dos valores: 1 si hay */
static uint8_t bad2(val *a, const val *b)
{
    if (a->t == V_NUM && b->t == V_NUM) return 0;
    a->t = (a->t == V_ERR || b->t == V_ERR) ? V_ERR : V_NA;
    return 1;
}
static void bin(val *a, val *b, uint8_t op)
{
    static int8_t c;
    if (bad2(a, b)) return;
    nerr = 0;
    switch (op) {
    case '+': nadd(&a->n, &a->n, &b->n); break;
    case '-': nsub(&a->n, &a->n, &b->n); break;
    case '*': nmul(&a->n, &a->n, &b->n); break;
    case '/': ndiv(&a->n, &a->n, &b->n); break;
    case '^': npow(&a->n, &a->n, &b->n); break;
    default:
        c = ncmp(&a->n, &b->n);
        switch (op) {
        case '=': c = c == 0; break;
        case TK_NE: c = c != 0; break;
        case '<': c = c < 0; break;
        case '>': c = c > 0; break;
        case TK_LE: c = c <= 0; break;
        case TK_GE: c = c >= 0; break;
        }
        setv(a, c);
    }
    if (nerr) a->t = V_ERR;
}

/* funciones con listas de valores y rangos */
static num acc;
static uint16_t cnt;
static uint8_t aet;
static void feed(val *v, uint8_t id)
{
    if (id == F_COUNT) { cnt++; return; }   /* cuenta tambien ERROR y NA */
    if (v->t != V_NUM) { if (v->t == V_ERR || aet != V_ERR) aet = v->t; return; }
    if (!cnt++) { acc = v->n; return; }
    switch (id) {
    case F_MIN: if (ncmp(&v->n, &acc) < 0) acc = v->n; break;
    case F_MAX: if (ncmp(&v->n, &acc) > 0) acc = v->n; break;
    case F_SUM: case F_AVG: nadd(&acc, &acc, &v->n); break;
    case F_AND: if (!v->n.m) acc = v->n; break;
    case F_OR: if (v->n.m) acc = v->n; break;
    }
}
static void aggr(val *v, uint8_t id)
{
    val a;
    uint8_t c, r, c1, r1, c2, r2;
    nzero(&acc); cnt = 0; aet = V_NUM;
    for (;;) {
        if (*tp == TK_RNG) {
            c1 = tp[1]; r1 = tp[2]; c2 = tp[3]; r2 = tp[4]; tp += 6;
            if (!c1) aet = V_ERR;
            else if (!chk)
                for (r = r1; r >= r1 && r <= r2; r++)
                    for (c = c1; c <= c2; c++)
                        if (cellv(&a, find(c, r))) feed(&a, id);
        } else {
            expr(&a);
            feed(&a, id);
        }
        if (*tp != ',') break;
        tp++;
    }
    v->t = aet;
    if (aet) return;
    v->n = acc;
    nerr = 0;
    switch (id) {
    case F_COUNT: nset(&v->n, cnt); break;
    case F_AVG:
        if (!cnt) { v->t = V_ERR; break; }
        nset(&a.n, cnt); ndiv(&v->n, &v->n, &a.n); break;
    case F_AND: case F_OR: setv(v, cnt && v->n.m != 0); break;
    default: if (!cnt) nzero(&v->n);
    }
    if (nerr) v->t = V_ERR;
}
/* @LOOKUP(x, rango): la ultima celda del rango con valor <= x; da la de al lado */
static void lookup(val *v)
{
    val x, a;
    uint8_t c1, r1, c2, r2, vert, fc = 0, fr = 0, c, r;
    expr(&x);
    if (*tp != ',') { synerr = 1; return; }
    tp++;
    if (*tp != TK_RNG) { synerr = 1; return; }
    c1 = tp[1]; r1 = tp[2]; c2 = tp[3]; r2 = tp[4]; tp += 6;
    v->t = V_NA;
    if (chk) { setv(v, 0); return; }
    if (!c1 || x.t) { v->t = x.t ? x.t : V_ERR; return; }
    vert = c1 == c2;
    for (c = c1, r = r1; c <= c2 && r <= r2; ) {
        if (cellv(&a, find(c, r)) && !a.t) {
            if (ncmp(&a.n, &x.n) > 0) break;
            fc = c; fr = r;
        }
        if (vert) { if (r == NR) break; r++; } else { if (c == NC) break; c++; }
    }
    if (!fc) return;
    if (vert) fc++; else fr++;
    if (fc > NC || fr > NR) return;
    setv(v, 0);
    cellv(v, find(fc, fr));
}
static void func(val *v, uint8_t id)
{
    val a[3];
    uint8_t n = 0;
    setv(v, 0);
    if (!fmax[id]) {
        if (*tp == '(' && tp[1] == ')') tp += 2;
        if (id == F_PI) { v->n.m = 314159265; v->n.e = -8; }
        else v->t = id == F_NA ? V_NA : V_ERR;
        return;
    }
    if (*tp != '(') { synerr = 1; return; }
    tp++;
    if (id <= F_COUNT || id == F_AND || id == F_OR) aggr(v, id);
    else if (id == F_LOOKUP) lookup(v);
    else {
        for (;;) {
            if (n == 3) { synerr = 1; return; }
            expr(&a[n++]);
            if (*tp != ',') break;
            tp++;
        }
        if (n < fmin[id] || n > fmax[id]) { synerr = 1; return; }
        if (id == F_ISNA || id == F_ISERR) setv(v, a[0].t == (id == F_ISNA ? V_NA : V_ERR));
        else if (id == F_IF) {
            if (a[0].t) *v = a[0];
            else if (a[0].n.m) *v = a[1];
            else *v = a[2];
        } else if (a[0].t || (n > 1 && a[1].t)) {
            *v = a[0];
            if (n > 1) bad2(v, &a[1]);
        } else {
            nerr = 0;
            v->n = a[0].n;
            switch (id) {
            case F_ABS: if (v->n.m < 0) v->n.m = -v->n.m; break;
            case F_INT: ntrunc(&v->n, &a[0].n); break;
            case F_ROUND: nround(&v->n, &a[0].n, (int8_t)(ntoi(&a[1].n) > 9 ? 9 : ntoi(&a[1].n) < -9 ? -9 : ntoi(&a[1].n))); break;
            case F_SQRT: if (nsqrt(&v->n, &a[0].n)) v->t = V_ERR; break;
            case F_MOD:
                if (!a[1].n.m) { v->t = V_ERR; break; }
                ndiv(&v->n, &a[0].n, &a[1].n); ntrunc(&v->n, &v->n);
                nmul(&v->n, &v->n, &a[1].n); nsub(&v->n, &a[0].n, &v->n); break;
            case F_NOT: setv(v, !a[0].n.m); break;
            }
            if (nerr) v->t = V_ERR;
        }
    }
    if (*tp != ')') { synerr = 1; return; }
    tp++;
}
static void prim(val *v)
{
    uint8_t t = *tp;
    setv(v, 0);
    switch (t) {
    case TK_NUM: memcpy(&v->n.m, tp + 1, 4); v->n.e = tp[5]; tp += 6; return;
    case TK_REF: refval(v, tp[1], tp[2]); tp += 4; return;
    case TK_FN: tp += 2; func(v, tp[-1]); return;
    case '(':
        tp++; expr(v);
        if (*tp != ')') synerr = 1; else tp++;
        return;
    }
    synerr = 1;
    if (t) tp++;
}
static void una(val *v);
static void pw(val *v)
{
    val b;
    prim(v);
    if (*tp == '^') { tp++; una(&b); bin(v, &b, '^'); }
}
static void una(val *v)
{
    if (*tp == '-') { tp++; una(v); if (!v->t) v->n.m = -v->n.m; return; }
    if (*tp == '+') { tp++; una(v); return; }
    pw(v);
}
static void term(val *v)
{
    val b;
    uint8_t op;
    una(v);
    while ((op = *tp) == '*' || op == '/') { tp++; una(&b); bin(v, &b, op); }
}
static void sum_(val *v)
{
    val b;
    uint8_t op;
    term(v);
    while ((op = *tp) == '+' || op == '-') { tp++; term(&b); bin(v, &b, op); }
}
static void expr(val *v)
{
    val b;
    uint8_t op;
    if (depth > 60) { synerr = 1; return; }
    sum_(v);
    op = *tp;
    if (op == '=' || op == '<' || op == '>' || op == TK_LE || op == TK_GE || op == TK_NE) {
        tp++; sum_(&b); bin(v, &b, op);
    }
}

static void recalc(void)
{
    static cell *x;
    static uint8_t pass;
    pass = 0;
    circ = 0;
    do {
        again = 0;
        if (!++gen) { FOR_CELLS(x) x->g = 0; gen = 1; }
        depth = 0;
        FOR_CELLS(x) evalcell(x);
    } while (again && ++pass < 30);
}

/* ================================================================ entradas */
static uint8_t tb[MAXT];
static uint8_t modified, dirty;
/* pone lo escrito en la celda: label 1 = texto, 2 = repetido, 0 = valor.
   1 si la formula tiene un error, 2 si no hay memoria */
static uint8_t setcell(uint8_t c, uint8_t r, const char *s, uint8_t label)
{
    static char up[MAXE + 1];
    static uint8_t n;
    static uint8_t i;
    static val v;
    static cell *x;
    if (label) {
        n = strlen(s);
        x = newcell(c, r, label == 2 ? K_REP : K_LAB, n);
        if (!x) return 2;
        memcpy(x->d, s, n);
    } else {
        for (i = 0; s[i] && i < MAXE; i++) up[i] = (s[i] >= 'a' && s[i] <= 'z') ? s[i] - 32 : s[i];
        up[i] = 0;
        if (!(n = tok(up, tb))) return 1;
        tp = tb; chk = 1; synerr = 0; depth = 0;
        expr(&v);
        chk = 0;
        if (synerr || *tp) return 1;
        i = (tb[0] == '-' || tb[0] == '+');
        if (tb[i] == TK_NUM && tb[i + 6] == TK_END) {
            x = newcell(c, r, K_NUM, 0);
            if (!x) return 2;
            x->v.t = V_NUM;
            memcpy(&x->v.n.m, tb + i + 1, 4); x->v.n.e = tb[i + 5];
            if (tb[0] == '-') x->v.n.m = -x->v.n.m;
        } else {
            x = newcell(c, r, K_FRM, n);
            if (!x) return 2;
            memcpy(x->d, tb, n);
            x->v.t = V_NUM;
        }
    }
    modified = dirty = 1;
    return 0;
}
/* lo que hay en la celda como se escribiria */
static void celltext(cell *x, char *o, uint8_t max)
{
    static uint8_t n;
    *o = 0;
    if (!x) return;
    switch (x->k) {
    case K_LAB: case K_REP:
        o[0] = x->k == K_LAB ? '"' : '\\';
        n = x->n < max - 2 ? x->n : max - 2;
        memcpy(o + 1, x->d, n); o[n + 1] = 0;
        break;
    case K_NUM:
        if (!nplain(o, &x->v.n, -1, max - 1)) nsci(o, &x->v.n, 22);
        break;
    default:
        dtok(x->d, o, max);
    }
}

/* ----------------------------------------------------- referencias que se mueven */
/* modos: 0 insertar en at, 1 borrar at, 2 mover el rectangulo (mc1,mr1)-(mc2,mr2) */
static uint8_t am, arow, aat, mc1, mr1, mc2, mr2;
static int8_t mdc, mdr;
/* v: coordenada; lim: maximo; end: 0 referencia, 1 inicio de rango, 2 fin */
static uint8_t adj1(uint8_t v, uint8_t lim, uint8_t end)
{
    if (!am) {
        if (v >= aat) { if (v == lim) return end == 2 ? lim : 0; v++; }
        return v;
    }
    if (v == aat) return end == 0 ? 0 : end == 1 ? (aat < lim ? aat : 0) : aat - 1;
    return v > aat ? v - 1 : v;
}
/* ajusta (c, r); 0 si la referencia queda borrada */
static uint8_t adjref(uint8_t *c, uint8_t *r, uint8_t end)
{
    static int16_t nc;
    static int16_t nr;
    if (am == 2) {
        if (*c < mc1 || *c > mc2 || *r < mr1 || *r > mr2) return 1;
        nc = *c + mdc; nr = *r + mdr;
        if (nc < 1 || nc > NC || nr < 1 || nr > NR) return 0;
        *c = nc; *r = nr;
        return 1;
    }
    if (arow) { *r = adj1(*r, NR, end); return *r != 0; }
    *c = adj1(*c, NC, end);
    return *c != 0;
}
static void adjform(uint8_t *t)
{
    while (*t) {
        switch (*t) {
        case TK_NUM: t += 6; break;
        case TK_REF:
            if (t[1] && !adjref(t + 1, t + 2, 0)) t[1] = 0;
            t += 4; break;
        case TK_RNG:
            if (t[1] && (!adjref(t + 1, t + 2, 1) || !adjref(t + 3, t + 4, 2) || t[3] < t[1] || t[4] < t[2])) t[1] = 0;
            t += 6; break;
        case TK_FN: t += 2; break;
        default: t++;
        }
    }
}
static void adjall(void)
{
    static cell *x;
    FOR_CELLS(x) if (x->k == K_FRM) adjform(x->d);
}
/* insertar (del = 0) o borrar una fila o columna */
static void insdel(uint8_t row, uint8_t at, uint8_t del)
{
    static cell *x;
    static uint8_t *p;
    static uint8_t lim;
    lim = row ? NR : NC;
    am = del; arow = row; aat = at;
    FOR_CELLS(x) {
        p = row ? &x->r : &x->c;
        if (del) { if (*p == at) x->c = 0; else if (*p > at) (*p)--; }
        else if (*p >= at) { if (*p == lim) x->c = 0; else (*p)++; }
    }
    rehash();
    adjall();
    modified = dirty = 1;
}
/* copia de x en (c, r), con las referencias relativas corridas */
static uint8_t shiftref(uint8_t *c, uint8_t *r, uint8_t fl, int16_t dc, int16_t dr)
{
    static int16_t nc;
    static int16_t nr;
    nc = *c;
    nr = *r;
    if (!(fl & 1)) nc += dc;
    if (!(fl & 2)) nr += dr;
    if (nc < 1 || nc > NC || nr < 1 || nr > NR) return 0;
    *c = nc; *r = nr;
    return 1;
}
static uint8_t copycell(cell *x, uint8_t c, uint8_t r)
{
    static cell *y;
    static uint8_t *t;
    static uint8_t i;
    static int16_t dc;
    static int16_t dr;
    static uint8_t k;
    static uint8_t f;
    static uint8_t n;
    dc = (int16_t)c - x->c;
    dr = (int16_t)r - x->r;
    k = x->k;
    f = x->f;
    n = x->n;
    memcpy(tb, x->d, n);         /* x puede ser la que se reemplaza */
    y = newcell(c, r, k, n);
    if (!y) return 1;
    y->f = f;
    memcpy(y->d, tb, n);
    if (k == K_NUM) y->v = x->v;
    if (k == K_FRM)
        for (t = y->d; *t; ) {
            switch (*t) {
            case TK_NUM: t += 6; break;
            case TK_REF: if (t[1] && !shiftref(t + 1, t + 2, t[3], dc, dr)) t[1] = 0; t += 4; break;
            case TK_RNG:
                if (t[1] && (!shiftref(t + 1, t + 2, t[5], dc, dr) || !shiftref(t + 3, t + 4, t[5] >> 2, dc, dr))) t[1] = 0;
                if (t[1] && t[3] < t[1]) { i = t[1]; t[1] = t[3]; t[3] = i; }
                if (t[1] && t[4] < t[2]) { i = t[2]; t[2] = t[4]; t[4] = i; }
                t += 6; break;
            case TK_FN: t += 2; break;
            default: t++;
            }
        }
    modified = dirty = 1;
    return 0;
}

/* ================================================================ pantalla */
static uint8_t cc = 1, cr = 1;           /* cursor */
static uint8_t fc = 1, fr = 1;           /* primeras columna y fila que se corren */
static uint8_t tcn, trn;                 /* columnas y filas de titulos */
static uint8_t gw = 9, gnf = 1, autoc = 1;
static uint8_t cw[NC + 1];
static uint8_t vcol[MAXVC], vx[MAXVC], nvc, vrow[GROWS], nvr;
static char fname_[16];
static char sb[90];
#define CW(c) (cw[c] ? cw[c] : gw)

static void layout(void)
{
    static uint8_t x;
    static uint8_t c;
    static uint8_t r;
    x = LW + 1;
    nvc = 0;
    for (c = 1; c <= tcn && nvc < MAXVC && x + CW(c) <= 81; c++) { vcol[nvc] = c; vx[nvc++] = x; x += CW(c); }
    for (c = fc; c <= NC && nvc < MAXVC && x + CW(c) <= 81; c++) { vcol[nvc] = c; vx[nvc++] = x; x += CW(c); }
    nvr = 0;
    for (r = 1; r <= trn && nvr < GROWS; r++) vrow[nvr++] = r;
    for (r = fr; r <= NR && nvr < GROWS; r++) vrow[nvr++] = r;
}
/* deja el cursor a la vista; 1 si la vista cambio */
static uint8_t scrollto(void)
{
    static uint8_t ch;
    ch = 0;
    if (fr <= trn) { fr = trn + 1; ch = 1; }
    if (fc <= tcn) { fc = tcn + 1; ch = 1; }
    if (cr > trn && cr < fr) { fr = cr; ch = 1; }
    if (cc > tcn && cc < fc) { fc = cc; ch = 1; }
    layout();
    while (cr > trn && vrow[nvr - 1] < cr) { fr++; ch = 1; layout(); }
    while (cc > tcn && nvc && vcol[nvc - 1] < cc && fc < NC) { fc++; ch = 1; layout(); }
    return ch;
}

/* el texto de la celda, exactamente w caracteres */
static void cellstr(char *o, uint8_t c, uint8_t r, uint8_t w)
{
    static char t[44];
    static uint8_t n;
    static uint8_t al;
    static uint8_t nf;
    static uint8_t i;
    static uint8_t pc;
    static uint16_t off;
    static cell *x;
    memset(o, ' ', w); o[w] = 0;
    x = find(c, r);
    if (!x) {                    /* un texto largo de la izquierda sigue aqui */
        for (off = 0, pc = c - 1; pc >= 1 && off < MAXE; pc--) {
            off += CW(pc);
            if (!(x = find(pc, r))) continue;
            if (x->k == K_LAB && ((x->f >> 4) & 3) != 2 && x->n > off) {
                n = x->n - off < w ? x->n - off : w;
                memcpy(o, x->d + off, n);
            }
            break;
        }
        return;
    }
    al = (x->f >> 4) & 3;
    nf = x->f & 15;
    if (!nf) nf = gnf;
    if (x->k == K_LAB) {
        n = x->n < w ? x->n : w;
        memcpy(o + (al == 2 ? w - n : 0), x->d, n);
        return;
    }
    if (x->k == K_REP) {
        for (i = 0; i < w && x->n; i++) o[i] = x->d[i % x->n];
        return;
    }
    if (x->v.t == V_ERR) strcpy(t, "ERROR");
    else if (x->v.t == V_NA) strcpy(t, "NA");
    else if (nf == 2) {
        int16_t k = ntoi(&x->v.n);
        if (k < 0) k = 0;
        if (k > w) k = w;
        memset(o, '*', k);
        return;
    } else fmtnum(t, &x->v.n, nf, w > 1 ? w - 1 : 1);
    n = strlen(t);
    if (n > w) n = w;
    memcpy(o + (al == 1 ? 0 : w - n), t, n);
}
static uint8_t vpos(uint8_t c, uint8_t r, uint8_t *i, uint8_t *j)
{
    for (*i = 0; *i < nvc && vcol[*i] != c; (*i)++) ;
    for (*j = 0; *j < nvr && vrow[*j] != r; (*j)++) ;
    return *i < nvc && *j < nvr;
}
static void drawcell(uint8_t c, uint8_t r, uint8_t hi)
{
    static uint8_t i;
    static uint8_t j;
    if (!vpos(c, r, &i, &j)) return;
    gotoxy(vx[i], GTOP + j);
    cellstr(sb, c, r, CW(c));
    if (hi) pstr(INV);
    pstr(sb);
    if (hi) pstr(NORM);
}
static void drawhdr(void)
{
    static uint8_t i;
    static uint8_t w;
    static uint8_t l;
    static char b[4];
    gotoxy(1, 3);
    pstr(INV "    ");
    for (i = 0; i < nvc; i++) {
        w = CW(vcol[i]);
        l = colname(b, vcol[i]);
        memset(sb, ' ', w); sb[w] = 0;
        memcpy(sb + (w - l) / 2, b, l);
        pstr(sb);
    }
    pstr(NORM EOL);
}
static void drawgrid(void)
{
    static uint8_t i;
    static uint8_t j;
    layout();
    drawhdr();
    for (j = 0; j < GROWS; j++) {
        gotoxy(1, GTOP + j);
        if (j >= nvr) { pstr(EOL); continue; }
        pf(INV "%3u " NORM, vrow[j]);
        for (i = 0; i < nvc; i++) {
            cellstr(sb, vcol[i], vrow[j], CW(vcol[i]));
            if (vcol[i] == cc && vrow[j] == cr) { pstr(INV); pstr(sb); pstr(NORM); }
            else pstr(sb);
        }
        pstr(EOL);
    }
    dirty = 0;
}
static const char *fmtname(uint8_t f, char *o)
{
    static uint8_t nf;
    static uint8_t al;
    static uint8_t n;
    nf = f & 15;
    al = (f >> 4) & 3;
    n = 0;
    if (nf == 1) o[n++] = 'G';
    else if (nf == 2) o[n++] = '*';
    else if (nf == 3) o[n++] = 'I';
    else if (nf == 5) o[n++] = '$';
    else if (nf) o[n++] = '0' + nf - 3;
    if (al) o[n++] = al == 1 ? 'L' : 'R';
    o[n] = 0;
    return o;
}
static void drawstat(void)
{
    static char b[8];
    static cell *x;
    static uint8_t n;
    x = find(cc, cr);
    gotoxy(1, 1);
    n = refname(sb, cc, cr, 0);
    pstr(sb);
    if (x) {
        fmtname(x->f, b);
        if (*b) pf(" /F%s", b);
        pstr(x->k == K_FRM ? " (V) " : x->k == K_NUM ? " (V) " : " (L) ");
        celltext(x, sb, 58);
        pstr(sb);
    }
    pstr(EOL);
    gotoxy(64, 1);
    pf("%c %5u free", (!autoc && dirty) ? '!' : ' ', hfree);
}
static void line2(const char *s)
{
    gotoxy(1, 2);
    pstr(s);
    pstr(EOL);
}

/* ================================================================ teclado */
static uint8_t pk;               /* una tecla devuelta */
static uint8_t rawk(void)
{
    static int k;
    if (pk) { k = pk; pk = 0; return k; }
    oflush();
    while (!(k = getkey())) delay(1);
    return k;
}
static uint8_t soon(void)
{
    static uint8_t n;
    static uint8_t k;
    k = 0;
    for (n = 0; n < 60 && !(k = getkey()); n++) ;
    return k;
}
static uint8_t getk(void)
{
    static uint8_t k;
    static uint8_t k2;
    k = rawk();
    switch (k) {
    case 5: return KUP;          /* ^E ^X ^S ^D como en WordStar */
    case 24: return KDOWN;
    case 19: return KLEFT;
    case 4: return KRIGHT;
    case 18: return KPGUP;       /* ^R ^C */
    case 3: return KPGDN;
    case 127: return 8;
    case 27: break;
    default: return k;
    }
    k2 = soon();
    if (k2 != '[' && k2 != 'O') { pk = k2; return 27; }
    k = soon();
    switch (k) {
    case 'A': return KUP;
    case 'B': return KDOWN;
    case 'C': return KRIGHT;
    case 'D': return KLEFT;
    case 'H': return KHOME;
    case 'F': return KEND;
    }
    if (k >= '1' && k <= '6' && soon() == '~')
        switch (k) {
        case '1': return KHOME;
        case '3': return KDEL;
        case '4': return KEND;
        case '5': return KPGUP;
        case '6': return KPGDN;
        }
    return 0;
}
static uint8_t ask(const char *s)
{
    static uint8_t k;
    line2(s);
    k = getk();
    if (k >= 'a' && k <= 'z') k -= 32;
    return k;
}

/* linea de edicion en la fila 2 (texto en eb) */
#define EL_MOVE 1                /* las flechas terminan */
#define EL_POINT 2               /* las flechas senalan celdas para la formula */
static char eb[MAXE + 1];
static void step(uint8_t k, uint8_t *c, uint8_t *r)
{
    if (k == KUP && *r > 1) (*r)--;
    else if (k == KDOWN && *r < NR) (*r)++;
    else if (k == KLEFT && *c > 1) (*c)--;
    else if (k == KRIGHT && *c < NC) (*c)++;
}
static uint8_t editline(const char *prompt, uint8_t fl)
{
    static uint8_t n;
    static uint8_t p;
    static uint8_t k;
    static uint8_t pt;
    static uint8_t pc;
    static uint8_t pr;
    static uint8_t ps;
    static uint8_t x0;
    static uint8_t s0;
    n = strlen(eb);
    p = n;
    pt = 0;
    pc = 0;
    pr = 0;
    ps = 0;
    x0 = strlen(prompt) + 1;
    pstr(SHOW);
    for (;;) {
        s0 = p > 70 - x0 ? p - (70 - x0) : 0;
        gotoxy(1, 2);
        pstr(prompt);
        pstr(eb + s0);
        pstr(EOL);
        gotoxy(x0 + p - s0, 2);
        k = getk();
        if (pt && !ISARROW(k)) { pt = 0; drawcell(pc, pr, pc == cc && pr == cr); }
        if (ISARROW(k)) {
            if ((fl & EL_POINT) && (pt || (p == n && n && strchr("+-*/^(,=<>:", eb[n - 1])))) {
                if (!pt) { pt = 1; pc = cc; pr = cr; ps = n; }
                else drawcell(pc, pr, pc == cc && pr == cr);
                step(k, &pc, &pr);
                n = ps + refname(eb + ps, pc, pr, 0);
                p = n;
                drawcell(pc, pr, 1);
                continue;
            }
            if (fl & EL_MOVE) { pstr(HIDE); return k; }
            if (k == KLEFT && p) p--;
            else if (k == KRIGHT && p < n) p++;
            continue;
        }
        switch (k) {
        case 13: case 27: pstr(HIDE); return k;
        case 8: if (p) { memmove(eb + p - 1, eb + p, n - p + 1); p--; n--; } break;
        case KDEL: if (p < n) { memmove(eb + p, eb + p + 1, n - p); n--; } break;
        case KHOME: case 1: p = 0; break;
        case KEND: p = n; break;
        case 25: n = p = 0; eb[0] = 0; break;          /* ^Y: borra la linea */
        default:
            if (k >= 32 && k < 127 && n < MAXE) {
                memmove(eb + p + 1, eb + p, n - p + 1);
                eb[p++] = k; n++;
            }
        }
    }
}
static uint8_t input(const char *prompt, const char *init)
{
    strcpy(eb, init);
    return editline(prompt, 0) == 13;
}
static uint8_t msgon;
static void msg(const char *s)
{
    msgon = 1;
    gotoxy(1, 2);
    pf(INV " %s " NORM EOL, s);
    putch(7);
}

/* ================================================================ ordenes */
static uint8_t isarg(char *s, uint8_t *c, uint8_t *r)   /* una celda */
{
    uint8_t fl;
    const char *p = s;
    for (; *s; s++) if (*s >= 'a' && *s <= 'z') *s -= 32;
    while (*p == ' ') p++;
    return pref(&p, c, r, &fl) && !*p;
}
static uint8_t prange(char *s, uint8_t *c1, uint8_t *r1, uint8_t *c2, uint8_t *r2)
{
    static uint8_t fl;
    static uint8_t t;
    static const char *p;
    p = s;
    for (; *s; s++) if (*s >= 'a' && *s <= 'z') *s -= 32;
    while (*p == ' ') p++;
    if (!pref(&p, c1, r1, &fl)) return 0;
    *c2 = *c1; *r2 = *r1;
    if (*p == ':' || *p == '.') {
        while (*p == ':' || *p == '.') p++;
        if (!pref(&p, c2, r2, &fl)) return 0;
    }
    if (*p) return 0;
    if (*c2 < *c1) { t = *c1; *c1 = *c2; *c2 = t; }
    if (*r2 < *r1) { t = *r1; *r1 = *r2; *r2 = t; }
    return 1;
}
static void curref(char *o) { refname(o, cc, cr, 0); }
static uint8_t usedmax(uint8_t *mc, uint8_t *mr)
{
    static cell *x;
    *mc = *mr = 0;
    FOR_CELLS(x) { if (x->c > *mc) *mc = x->c; if (x->r > *mr) *mr = x->r; }
    return *mc != 0;
}

static void goto_(void)
{
    static uint8_t c;
    static uint8_t r;
    if (!input("Go to: ", "")) return;
    if (isarg(eb, &c, &r)) { cc = c; cr = r; } else msg("Bad cell");
}
static uint8_t fmtkey(uint8_t k, uint8_t f)
{
    if (k == 'D') return 0;
    if (k == 'G') return (f & 0xF0) | 1;
    if (k == 'I') return (f & 0xF0) | 3;
    if (k == '$') return (f & 0xF0) | 5;
    if (k == '*') return (f & 0xF0) | 2;
    if (k >= '0' && k <= '9') return (f & 0xF0) | (k - '0' + 3);
    if (k == 'L') return (f & 0x0F) | 0x10;
    if (k == 'R') return (f & 0x0F) | 0x20;
    return 0xFF;
}
static uint8_t askw(uint8_t def)
{
    static uint8_t w;
    static char *p;
    w = 0;
    utoa_(def, sb); sb[ndig(def)] = 0;
    if (!input("Column width (3-40): ", sb)) return 0;
    for (p = eb; *p >= '0' && *p <= '9'; p++) w = w * 10 + *p - '0';
    if (*p || w < 3 || w > 40) { msg("Width 3-40"); return 0; }
    return w;
}
static void cmd_format(void)
{
    static uint8_t k;
    static uint8_t f;
    static uint8_t w;
    static cell *x;
    k = ask("Format: D(efault) G I(nteger) $ 0-9 (decimals) *(graph) L(eft) R(ight) W(idth)");
    if (k == 'W') { if ((w = askw(CW(cc)))) { cw[cc] = w == gw ? 0 : w; modified = 1; } return; }
    x = find(cc, cr);
    f = fmtkey(k, x ? x->f : 0);
    if (f == 0xFF) return;
    if (!x) { if (!(x = newcell(cc, cr, K_LAB, 0))) { msg("Memory full"); return; } }
    x->f = f;
    if (x->k == K_LAB && !x->n && !f) delcell(cc, cr);
    modified = 1;
}
static void cmd_global(void)
{
    static uint8_t k;
    static uint8_t w;
    static uint8_t i;
    k = ask("Global: C(olumn width) F(ormat) R(ecalc)");
    if (k == 'C') {
        if ((w = askw(gw))) { gw = w; for (i = 1; i <= NC; i++) cw[i] = 0; modified = 1; }
    } else if (k == 'F') {
        k = ask("Global format: G I $ 0-9 *");
        if ((i = fmtkey(k, 0)) != 0xFF && (i & 15)) { gnf = i & 15; modified = 1; }
    } else if (k == 'R') {
        k = ask("Recalc: A(utomatic) M(anual)");
        if (k == 'A') { autoc = 1; recalc(); } else if (k == 'M') autoc = 0;
    }
}
static void cmd_repl(void)
{
    static uint8_t c1;
    static uint8_t r1;
    static uint8_t c2;
    static uint8_t r2;
    static uint8_t t1;
    static uint8_t u1;
    static uint8_t t2;
    static uint8_t u2;
    static uint8_t c;
    static uint8_t r;
    static uint8_t i;
    static uint8_t j;
    static uint8_t err;
    err = 0;
    curref(sb);
    if (!input("Replicate from: ", sb) || !prange(eb, &c1, &r1, &c2, &r2)) return;
    if (!input("To: ", "") || !prange(eb, &t1, &u1, &t2, &u2)) return;
    /* destinos: un bloque en cada (c, r) de la lista */
    for (r = u1; r <= u2 && r >= u1; r++)
        for (c = t1; c <= t2; c++) {
            if (!((c1 == c2 && r1 == r2) || (c == t1 && r == u1) ||
                  (c1 == c2 && u1 == u2) || (r1 == r2 && t1 == t2))) continue;
            for (j = 0; j <= r2 - r1 && r + j <= NR; j++)
                for (i = 0; i <= c2 - c1 && c + i <= NC; i++) {
                    cell *x = find(c1 + i, r1 + j);
                    if (x) { if (copycell(x, c + i, r + j)) err = 1; }
                    else delcell(c + i, r + j);
                }
        }
    if (err) msg("Memory full");
}
static void cmd_move(void)
{
    static uint8_t c1;
    static uint8_t r1;
    static uint8_t c2;
    static uint8_t r2;
    static uint8_t tc;
    static uint8_t tr;
    static uint8_t c;
    static uint8_t r;
    static cell *x;
    curref(sb);
    if (!input("Move from: ", sb) || !prange(eb, &c1, &r1, &c2, &r2)) return;
    if (!input("To: ", "") || !isarg(eb, &tc, &tr)) return;
    am = 2; mc1 = c1; mr1 = r1; mc2 = c2; mr2 = r2; mdc = tc - c1; mdr = tr - r1;
    if (!mdc && !mdr) return;
    adjall();
    /* las del destino que no se mueven se pierden; las movidas cambian de lugar */
    FOR_CELLS(x) {
        uint8_t ins = x->c >= c1 && x->c <= c2 && x->r >= r1 && x->r <= r2;
        int16_t nc = x->c + mdc, nr = x->r + mdr;
        if (ins) { x->st = 1; if (nc < 1 || nc > NC || nr < 1 || nr > NR) x->c = 0; }
        else x->st = 0;
    }
    FOR_CELLS(x)
        if (!x->st && x->c >= c1 + mdc && x->c <= c2 + mdc && x->r >= r1 + mdr && x->r <= r2 + mdr) x->c = 0;
    FOR_CELLS(x)
        if (x->st && x->c) { x->c += mdc; x->r += mdr; }
    FOR_CELLS(x) x->st = 0;
    (void)c; (void)r;
    rehash();
    modified = dirty = 1;
}

/* ----------------------------------------------------- archivos */
static FCB of;
static uint8_t ob[128], obp, odev, oerr;
static FCB inf;
static uint8_t inp;              /* lo que sigue en ob al leer (128 = leer otro) */
static int rdc(void)
{
    if (inp == 128) { if (fread(&inf, ob)) return -1; inp = 0; }
    return ob[inp++];
}
static void oc(char c)
{
    if (odev) { bdos(5, (uint8_t)c); return; }
    ob[obp++] = c;
    if (obp == 128) { if (fwrite(&of, ob)) oerr = 1; obp = 0; }
}
static void os(const char *s) { while (*s) oc(*s++); }
static uint8_t oclose(void)
{
    if (odev) return 0;
    if (obp) { memset(ob + obp, 26, 128 - obp); if (fwrite(&of, ob)) oerr = 1; }
    fclose(&of);
    return oerr;
}
static uint8_t ofile(const char *name)
{
    odev = 0; obp = 0; oerr = 0;
    if (!mkfcb(&of, name)) return 1;
    return fmake(&of);
}
static void defext(char *s, const char *ext)
{
    static char *p;
    for (p = s; *p; p++) if (*p >= 'a' && *p <= 'z') *p -= 32;
    if (!strchr(s, '.') && strlen(s) < 10) strcat(s, ext);
}
static void save(void)
{
    static cell *x;
    static uint8_t i;
    static char b[8];
    if (!input("Save as: ", fname_) || !eb[0]) return;
    defext(eb, ".ZC");
    if (ofile(eb)) { msg("Can't create file"); return; }
    strncpy(fname_, eb, 15);
    os("ZCALC 1\r\n");
    utoa_(gw, b); b[ndig(gw)] = 0;
    os("G "); os(b); oc(' '); oc('0' + gnf / 10); oc('0' + gnf % 10); oc(' '); oc(autoc ? 'A' : 'M'); os("\r\n");
    for (i = 1; i <= NC; i++)
        if (cw[i]) { os("W "); colname(b, i); os(b); oc(' '); utoa_(cw[i], b); b[ndig(cw[i])] = 0; os(b); os("\r\n"); }
    FOR_CELLS(x) {
        refname(b, x->c, x->r, 0); os(b);
        oc('|'); oc("0123456789ABCDEF"[x->f >> 4]); oc("0123456789ABCDEF"[x->f & 15]); oc('|');
        celltext(x, sb, 86); os(sb); os("\r\n");
    }
    if (oclose()) msg("Disk full");
    else modified = 0;
}
static uint8_t hexv(char c) { return c <= '9' ? c - '0' : c - 'A' + 10; }
static uint8_t loadfile(const char *name)
{
    static char l[130];
    static uint8_t n;
    static uint8_t c;
    static uint8_t r;
    static uint8_t fl;
    static uint8_t bad;
    static int ch;
    static const char *p;
    static cell *x;
    bad = 0;
    if (!mkfcb(&inf, name) || fopen(&inf)) return 1;
    inp = 128;
    clearall();
    gw = 9; gnf = 1; autoc = 1;
    memset(cw, 0, sizeof cw);
    for (;;) {
        n = 0;
        while ((ch = rdc()) >= 0 && ch != 26 && ch != '\n') if (ch != '\r' && n < 129) l[n++] = ch;
        l[n] = 0;
        if (n) {
            if (l[0] == 'G' && l[1] == ' ') {
                for (p = l + 2, n = 0; isdig(*p); p++) n = n * 10 + *p - '0';
                if (n >= 3 && n <= 40) gw = n;
                if (p[0] == ' ' && isdig(p[1])) { gnf = (p[1] - '0') * 10 + p[2] - '0'; if (!gnf || gnf > 12) gnf = 1; }
                autoc = p[4] != 'M';
            } else if (l[0] == 'W' && l[1] == ' ') {
                p = l + 2; c = *p++ - 'A' + 1;
                if (isup(*p)) c = c * 26 + (*p++ - 'A' + 1);
                for (n = 0, p++; isdig(*p); p++) n = n * 10 + *p - '0';
                if (c <= NC && n >= 3 && n <= 40) cw[c] = n;
            } else if (l[0] != 'Z') {
                p = l;
                if (pref(&p, &c, &r, &fl) && p[0] == '|' && p[3] == '|') {
                    fl = hexv(p[1]) << 4 | hexv(p[2]);
                    p += 4;
                    if (*p == '"') n = setcell(c, r, p + 1, 1);
                    else if (*p == '\\') n = setcell(c, r, p + 1, 2);
                    else n = setcell(c, r, p, 0);
                    if (n == 2) { bad = 2; break; }
                    if (n) bad = 1;
                    else if ((x = find(c, r))) x->f = fl;
                    if (!*p && !n) { if ((x = find(c, r))) { x->k = K_LAB; x->n = 0; } }
                } else bad = 1;
            }
        }
        if (ch < 0 || ch == 26) break;
    }
    fclose(&inf);
    strncpy(fname_, name, 15);
    recalc();
    modified = 0;
    dirty = 1;
    return bad ? bad + 1 : 0;
}
/* un campo de CSV es numero si es solo [signo] cifras [. cifras] [E [signo] cifras] */
static uint8_t isnumtxt(const char *s)
{
    uint8_t d = 0;
    if (*s == '-' || *s == '+') s++;
    while (isdig(*s)) { s++; d++; }
    if (*s == '.') { s++; while (isdig(*s)) { s++; d++; } }
    if (!d) return 0;
    if (*s == 'E' || *s == 'e') {
        s++;
        if (*s == '-' || *s == '+') s++;
        if (!isdig(*s)) return 0;
        while (isdig(*s)) s++;
    }
    return !*s;
}
/* lee un CSV con su esquina en el cursor: numeros como valores, lo demas texto.
   0 bien, 1 no esta, 3 sin memoria */
static uint8_t loadcsv(const char *name)
{
    static char l[130];
    static uint8_t n, row, col, inq, qend, e, c, r;
    static int ch;
    if (!mkfcb(&inf, name) || fopen(&inf)) return 1;
    inp = 128;
    n = row = col = inq = qend = e = 0;
    for (;;) {
        ch = rdc();
        if (ch == 26) ch = -1;
        if (inq) {
            if (ch == '"') {
                if (qend) { if (n < 129) l[n++] = '"'; qend = 0; } else qend = 1;
                continue;
            }
            if (!qend && ch >= 0) { if (n < 129) l[n++] = ch; continue; }
            inq = qend = 0;
        }
        if (ch == '"' && !n) { inq = 1; continue; }
        if (ch == '\r') continue;
        if (ch == ',' || ch == '\n' || ch < 0) {
            l[n] = 0;
            c = cc + col; r = cr + row;
            if (n && c >= cc && c <= NC && r >= cr && r <= NR) {
                if (isnumtxt(l)) e = setcell(c, r, l, 0);
                else e = setcell(c, r, l, 1);
                if (e == 2) break;
                e = 0;
            }
            n = 0;
            if (ch == ',') col++;
            else { col = 0; row++; }
            if (ch < 0) break;
            continue;
        }
        if (n < 129) l[n++] = ch;
    }
    fclose(&inf);
    dirty = 1;
    return e == 2 ? 3 : 0;
}
static void load(void)
{
    static uint8_t e, iscsv;
    if (!input("Load (.ZC, or .CSV at the cursor): ", fname_) || !eb[0]) return;
    defext(eb, ".ZC");
    iscsv = strstr(eb, ".CSV") != 0;
    if (!iscsv && modified && ask("Sheet not saved. Load anyway? (Y/N)") != 'Y') return;
    e = iscsv ? loadcsv(eb) : loadfile(eb);
    if (e == 1) msg("File not found");
    else if (e == 2) msg("Some lines could not be read");
    else if (e == 3) msg("Memory full");
}
static void csv(void)
{
    static uint8_t mc;
    static uint8_t mr;
    static uint8_t c;
    static uint8_t r;
    static uint8_t i;
    static cell *x;
    static char name[16];
    if (!usedmax(&mc, &mr)) return;
    strcpy(name, fname_);
    if (strchr(name, '.')) *strchr(name, '.') = 0;
    if (*name) strcat(name, ".CSV");
    if (!input("CSV file: ", name) || !eb[0]) return;
    defext(eb, ".CSV");
    if (ofile(eb)) { msg("Can't create file"); return; }
    for (r = 1; r <= mr; r++) {
        for (c = 1; c <= mc; c++) {
            if (c > 1) oc(',');
            x = find(c, r);
            if (!x || x->k == K_REP) continue;
            if (x->k == K_LAB) {
                oc('"');
                for (i = 0; i < x->n; i++) { if (x->d[i] == '"') oc('"'); oc(x->d[i]); }
                oc('"');
            } else if (x->v.t) os(x->v.t == V_ERR ? "#ERROR" : "#NA");
            else { if (!nplain(sb, &x->v.n, -1, 30)) nsci(sb, &x->v.n, 22); os(sb); }
        }
        os("\r\n");
    }
    if (oclose()) msg("Disk full");
}
static void print(void)
{
    static uint8_t mc;
    static uint8_t mr;
    static uint8_t c1;
    static uint8_t r1;
    static uint8_t c2;
    static uint8_t r2;
    static uint8_t c;
    static uint8_t r;
    static uint8_t n;
    if (!usedmax(&mc, &mr)) return;
    if (!input("Print to file (Enter = printer): ", "")) return;
    if (eb[0]) {
        defext(eb, ".PRN");
        if (ofile(eb)) { msg("Can't create file"); return; }
    } else odev = 1;
    strcpy(sb, "A1:");
    refname(sb + 3, mc, mr, 0);
    if (!input("Range: ", sb) || !prange(eb, &c1, &r1, &c2, &r2)) { if (!odev) { oclose(); } return; }
    for (r = r1; r <= r2 && r >= r1; r++) {
        for (c = c1, n = 0; c <= c2; c++) {
            cellstr(sb, c, r, CW(c));
            os(sb);
        }
        os("\r\n");
        (void)n;
    }
    if (odev) oc(12);
    if (oclose()) msg("Disk full");
}

static void help(void)
{
    pstr(CLS SHOW
        "ZCALC " VERSION "                                                   (C) OLIVEROS 2026\n\n"
        " Arrows (or ^E ^X ^S ^D) move; PgUp/PgDn (^R ^C) 20 rows; Home goes to A1.\n"
        " Type a number or formula (starting with a digit . + - ( @ =) or a label\n"
        " (anything else; \" starts a label that looks like a number). Enter or an\n"
        " arrow stores it; ESC cancels. In a formula, an arrow after an operator\n"
        " points at cells. > goes to a cell, ! recalculates, ^L redraws.\n\n"
        " Formulas: + - * / ^  = <> < > <= >=  A1 $A$1 A1:B5\n"
        "   @SUM @AVG @MIN @MAX @COUNT (lists and ranges)  @LOOKUP(x,A1:A9)\n"
        "   @ABS @INT @ROUND(x,n) @SQRT @MOD(a,b) @IF(c,a,b) @AND @OR @NOT\n"
        "   @PI @NA @ERROR @ISNA @ISERROR\n\n"
        " /B blank cell     /C clear sheet       /D delete row or column\n"
        " /E edit cell      /F format, width     /G global width, format, recalc\n"
        " /I insert row/col /M move cells        /P print (printer or file)\n"
        " /R replicate      /S load (.ZC, .CSV), save, CSV, quit   /T titles\n"
        " /- repeat a label (/-= draws a line)   /A about   /Q quit\n\n"
        " Numbers have 9 digits and are decimal (money adds up exactly).\n\n"
        " Press any key.");
    getk();
    pstr(HIDE CLS);
    dirty = 1;
}

/* /A: acerca de ZCALC */
static void about(void)
{
    pstr(CLS);
    gotoxy(20, 8);  pstr(INV "                                        " NORM);
    gotoxy(20, 9);  pstr(INV "  ZCALC " VERSION "                             " NORM);
    gotoxy(20, 10); pstr(INV "  Spreadsheet for CP/M 2.2, CP/M 3      " NORM);
    gotoxy(20, 11); pstr(INV "  and MP/M II on the Z80-Retro          " NORM);
    gotoxy(20, 12); pstr(INV "                                        " NORM);
    gotoxy(20, 13); pstr(INV "  (C) OLIVEROS 2026                     " NORM);
    gotoxy(20, 14); pstr(INV "                                        " NORM);
    gotoxy(20, 15); pf(INV "  %5u bytes free for cells           " NORM, hfree);
    gotoxy(20, 16); pstr(INV "                                        " NORM);
    gotoxy(20, 18); pstr("Press any key.");
    getk();
    pstr(CLS);
    dirty = 1;
}

static uint8_t quit(void)
{
    if (modified && ask("Sheet not saved. Quit anyway? (Y/N)") != 'Y') return 0;
    return 1;
}

static void entry(uint8_t k)
{
    static uint8_t isval;
    static uint8_t t;
    static uint8_t e;
    isval = strchr("0123456789.+-(@=$", k) != 0;
    if (k == '"') eb[0] = 0;
    else { eb[0] = k; eb[1] = 0; }
    for (;;) {
        t = editline(isval ? "Value: " : "Label: ", EL_MOVE | (isval ? EL_POINT : 0));
        if (t == 27) return;
        e = setcell(cc, cr, eb, !isval);
        if (!e) break;
        msg(e == 2 ? "Memory full" : "Error in formula");
        if (e == 2) return;
    }
    if (ISARROW(t)) step(t, &cc, &cr);
}
static void edit(void)
{
    static cell *x;
    static uint8_t t;
    static uint8_t e;
    static uint8_t lab;
    x = find(cc, cr);
    celltext(x, eb, MAXE);
    for (;;) {
        t = editline("Edit: ", EL_POINT);
        if (t == 27) return;
        lab = eb[0] == '"' ? 1 : eb[0] == '\\' ? 2 : 0;
        if (!eb[0] && x) { delcell(cc, cr); modified = dirty = 1; return; }
        e = setcell(cc, cr, eb + (lab != 0), lab);
        if (!e) return;
        msg(e == 2 ? "Memory full" : "Error in formula");
        if (e == 2) return;
    }
}

static uint8_t command(void)
{
    static uint8_t k;
    static uint8_t k2;
    k = ask("Command: A B C D E F G I M P R S T - Q ?");
    switch (k) {
    case 'B': delcell(cc, cr); modified = dirty = 1; break;
    case 'C':
        if (ask("Clear the whole sheet? (Y/N)") == 'Y') {
            clearall(); memset(cw, 0, sizeof cw); gw = 9; gnf = 1; tcn = trn = 0; fc = fr = cc = cr = 1;
            modified = 0; dirty = 1; fname_[0] = 0;
        }
        break;
    case 'D': case 'I':
        k2 = ask(k == 'D' ? "Delete: R(ow) C(olumn)" : "Insert: R(ow) C(olumn)");
        if (k2 == 'R') insdel(1, cr, k == 'D');
        else if (k2 == 'C') insdel(0, cc, k == 'D');
        break;
    case 'E': edit(); break;
    case 'F': cmd_format(); dirty = 1; break;
    case 'G': cmd_global(); dirty = 1; break;
    case 'M': cmd_move(); break;
    case 'P': print(); break;
    case 'R': cmd_repl(); break;
    case 'S':
        k2 = ask("Storage: L(oad) S(ave) X (CSV) Q(uit)");
        if (k2 == 'L') load();
        else if (k2 == 'S') save();
        else if (k2 == 'X') csv();
        else if (k2 == 'Q') return quit();
        break;
    case 'T':
        k2 = ask("Titles: H(orizontal) V(ertical) B(oth) N(one)");
        if (k2 == 'H' || k2 == 'B') trn = cr - 1 < GROWS - 2 ? cr - 1 : 0;
        if (k2 == 'V' || k2 == 'B') tcn = cc - 1 < 4 ? cc - 1 : 0;
        if (k2 == 'N') tcn = trn = 0;
        fr = trn + 1; fc = tcn + 1;
        dirty = 1;
        break;
    case '-':
        if (input("Repeat: ", "") && eb[0]) {
            if (setcell(cc, cr, eb, 2)) msg("Memory full");
        }
        break;
    case 'Q': return quit();
    case '?': help(); break;
    case 'A': about(); break;
    }
    return 0;
}

void main(void)
{
    uint8_t k, oc_, or_;
    char *a = args(), *f;
    uint16_t top = (uint16_t)&k - 1536;
    freel = (fb *)heap;
    freel->sz = (top - (uint16_t)heap) & ~1;
    freel->nx = 0;
    hfree = freel->sz;
    pstr(HIDE CLS);
    f = nextarg(&a);
    if (f && *f) {
        strncpy(eb, f, 15); eb[15] = 0;
        defext(eb, ".ZC");
        k = loadfile(eb);
        if (k == 1) strncpy(fname_, eb, 15);
        if (k > 1) msg("Some lines could not be read");
    }
    dirty = 1;
    for (;;) {
        if (scrollto() || dirty) {
            if (autoc && dirty) recalc();
            drawgrid();
        }
        drawstat();
        oflush();
        k = getk();
        oc_ = cc; or_ = cr;
        msgon = 0;
        switch (k) {
        case KUP: case KDOWN: case KLEFT: case KRIGHT:
            step(k, &cc, &cr);
            break;
        case KPGUP: cr = cr > 20 ? cr - 20 : 1; break;
        case KPGDN: cr = cr < NR - 20 ? cr + 20 : NR; break;
        case KHOME: cc = cr = 1; break;
        case '>': goto_(); break;
        case '!': recalc(); dirty = 1; break;
        case 12: pstr(CLS); dirty = 1; break;
        case KDEL: delcell(cc, cr); modified = dirty = 1; break;
        case '/':
            if (command()) { pstr(SHOW CLS); return; }
            break;
        case '?': help(); break;
        default:
            if (k >= 32 && k < 127) entry(k);
        }
        if (!msgon) line2("");
        if (!dirty && (cc != oc_ || cr != or_)) {
            if (!scrollto()) { drawcell(oc_, or_, 0); drawcell(cc, cr, 1); }
            else dirty = 1;
        }
    }
}
