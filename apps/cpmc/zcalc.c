/* ZCALC 1.1 - hoja de calculo para CP/M 2.2, CP/M 3 y MP/M II (terminal ANSI de 80x24)
   ZCALC [archivo[.ZC]]
   63 columnas (A-BK) x 254 filas. Numeros decimales de 9 cifras: 0,1 y los
   centavos son exactos. Se maneja como las hojas de 1979: el cursor recorre la
   cuadricula, lo que se escribe va a la celda y las ordenes empiezan con '/'.
   Formulas: + - * / ^, comparaciones (= <> < > <= >=), referencias A1, $A$1,
   rangos A1:B5 (o A1...B5) y funciones @SUM @AVG @MIN @MAX @COUNT @LOOKUP
   @ABS @INT @ROUND @SQRT @MOD @IF @AND @OR @NOT @PI @NA @ERROR @ISNA @ISERROR,
   de finanzas (@PMT @PV @FV @NPV @IRR), fechas (@DATE @TODAY @NOW @YEAR @MONTH
   @DAY) y trigonometria (@SIN @COS @TAN @ATAN @LN @LOG @EXP).
   El evaluador, la aritmetica y las funciones estan en zcalc_a.s.
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include <string.h>
#include "cpm.h"

#define VERSION "1.1"            /* tambien en zcalc_a.s y en LEEME.md */

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

/* en zcalc_a.s */
uint8_t utoa_(uint32_t u, char *o) __sdcccall(0);
uint8_t nplain(char *o, const num *x, int8_t dec, uint8_t max) __sdcccall(0);
uint8_t nsci(char *o, const num *x, uint8_t max) __sdcccall(0);
const char *pnum(const char *s, num *x) __sdcccall(0);
/* formatos: 0 el global, 1 general, 2 grafico, 3+k: k decimales (en zcalc_a.s) */
void fmtnum(char *o, const num *x, uint8_t nf, uint8_t w) __sdcccall(0);
/* ================================================================ celdas */
enum { K_LAB = 1, K_REP, K_NUM, K_FRM };
typedef struct cell {
    struct cell *nx;
    uint8_t c, r;                /* columna y fila (desde 1) */
    uint8_t fl;                  /* bits 0-2 clase, 3 calculando, 4-5 tipo de valor, 6 protegida, 7 marca */
    uint8_t f;                   /* formato: bits 0-3 numero, 4-5 alineacion */
    uint8_t n;                   /* bytes de d */
    uint8_t d[1];                /* texto; o el valor (5 bytes), y en las formulas
                                    la generacion (1) y la formula compilada */
} cell;
#define KIND(x) ((x)->fl & 7)
#define VT(x) (((x)->fl >> 4) & 3)
#define SETVT(x, t) ((x)->fl = ((x)->fl & 0xCF) | ((t) << 4))
#define F_ST 0x08
#define F_PROT 0x40
#define F_MARK 0x80
#define NUMP(x) ((num *)(x)->d)
#define GEN(x) (*((x)->d + 5))
#define TOK(x) ((x)->d + 6)
#define NH 128
cell *ht[NH];                    /* tambien lo usa zcalc_a.s */
cell *find(uint8_t c, uint8_t r) __sdcccall(0);   /* en zcalc_a.s */
#define HK(c, r) (((c) * 13 + (r)) & (NH - 1))
static uint8_t hb;
#define FOR_CELLS(x) for (hb = 0; hb < NH; hb++) for (x = ht[hb]; x; x = x->nx)

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
    x->c = c; x->r = r; x->fl = k; x->f = f; x->n = n;
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
enum { TK_END, TK_NUM, TK_REF, TK_RNG, TK_FN, TK_LE, TK_GE, TK_NE, TK_I8 };
/* TK_NUM m(4) e(1); TK_I8 un entero 0-255; TK_REF cf r; TK_RNG cf1 r1 cf2 r2; TK_FN id.
   cf: columna en los bits 0-5 y los $ en el 6 (columna) y el 7 (fila).
   Una referencia borrada tiene c = 0 (#REF) */
enum { F_SUM, F_AVG, F_MIN, F_MAX, F_COUNT, F_LOOKUP, F_ABS, F_INT, F_ROUND, F_SQRT,
       F_MOD, F_IF, F_AND, F_OR, F_NOT, F_PI, F_NA, F_ERROR, F_ISNA, F_ISERR,
       F_PMT, F_PV, F_FV, F_NPV, F_IRR, F_DATE, F_TODAY, F_NOW, F_YEAR, F_MONTH, F_DAY,
       F_SIN, F_COS, F_TAN, F_ATAN, F_LN, F_EXP, F_LOG, NFN };
/* los nombres y los argumentos de cada una estan en zcalc_a.s */

static uint8_t isup(char c) { return c >= 'A' && c <= 'Z'; }
static uint8_t isdig(char c) { return c >= '0' && c <= '9'; }

/* en zcalc_a.s: referencias y formulas compiladas (la lista de nombres de
   las funciones tambien esta alli, en el orden de F_SUM...) */
uint8_t pref(const char **ps, uint8_t *c, uint8_t *r, uint8_t *fl) __sdcccall(0);
uint8_t colname(char *o, uint8_t c) __sdcccall(0);
uint8_t refname(char *o, uint8_t c, uint8_t r, uint8_t fl) __sdcccall(0);
uint8_t tok(const char *s, uint8_t *o) __sdcccall(0);
uint8_t dtok(const uint8_t *t, char *o, uint8_t max) __sdcccall(0);

/* las funciones de finanzas, fechas y trigonometria (cfunc) y el formato de
   fecha y hora (datestr) estan en zcalc_a.s */
uint8_t datestr(char *o, const num *x, uint8_t nf) __sdcccall(0);

/* ================================================================ calculo */
/* en zcalc_a.s: la evaluacion de las formulas y el recalculo */
extern const uint8_t *tp;        /* lo que sigue en la formula */
extern uint8_t synerr, chk;      /* chk: solo revisar la sintaxis */
extern uint8_t gen, depth, again, circ;
void expr(val *v) __sdcccall(0);
void recalc(void);

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
        if ((tb[i] == TK_NUM && tb[i + 6] == TK_END) || (tb[i] == TK_I8 && tb[i + 2] == TK_END)) {
            x = newcell(c, r, K_NUM, 5);
            if (!x) return 2;
            if (tb[i] == TK_I8) nset(NUMP(x), tb[i + 1]);
            else memcpy(x->d, tb + i + 1, 5);
            if (tb[0] == '-') NUMP(x)->m = -NUMP(x)->m;
        } else {
            x = newcell(c, r, K_FRM, n + 6);
            if (!x) return 2;
            memset(x->d, 0, 6);
            memcpy(TOK(x), tb, n);
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
    switch (KIND(x)) {
    case K_LAB: case K_REP:
        o[0] = KIND(x) == K_LAB ? '"' : '\\';
        n = x->n < max - 2 ? x->n : max - 2;
        memcpy(o + 1, x->d, n); o[n + 1] = 0;
        break;
    case K_NUM:
        if (!nplain(o, NUMP(x), -1, max - 1)) nsci(o, NUMP(x), 22);
        break;
    default:
        dtok(TOK(x), o, max);
    }
}

/* ----------------------------------------------------- referencias que se mueven */
/* modos: 0 insertar en at, 1 borrar at, 2 mover el rectangulo (mc1,mr1)-(mc2,mr2) */
/* en zcalc_a.s */
extern uint8_t am, arow, aat, mc1, mr1, mc2, mr2;
extern int16_t mdc, mdr;
void adjform(uint8_t *t) __sdcccall(0);
void shiftform(uint8_t *t, int16_t dc, int16_t dr) __sdcccall(0);
static void adjall(void)
{
    static cell *x;
    FOR_CELLS(x) if (KIND(x) == K_FRM) adjform(TOK(x));
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
    k = KIND(x);
    f = x->f;
    n = x->n;
    memcpy(tb, x->d, n);         /* x puede ser la que se reemplaza */
    y = newcell(c, r, k, n);
    if (!y) return 1;
    y->f = f;
    memcpy(y->d, tb, n);
    if (k == K_FRM) shiftform(TOK(y), dc, dr);
    modified = dirty = 1;
    return 0;
}

/* ================================================================ pantalla */
static uint8_t cc = 1, cr = 1;           /* cursor */
static uint8_t fc = 1, fr = 1;           /* primeras columna y fila que se corren */
static uint8_t tcn, trn;                 /* columnas y filas de titulos */
uint8_t gw = 9, gnf = 1;         /* tambien los usa zcalc_a.s */
static uint8_t autoc = 1;
uint8_t cw[NC + 1];
static uint8_t vcol[MAXVC], vx[MAXVC], nvc, vrow[GROWS], nvr;
static uint8_t gtop = GTOP, grows = GROWS;   /* la ventana activa en pantalla */
/* ventanas: la otra (fr, fc, cc, cr, gtop, grows); win = 1 si hay dos */
static uint8_t opn[6], win, nohl;
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
    for (r = 1; r <= trn && nvr < grows; r++) vrow[nvr++] = r;
    for (r = fr; r <= NR && nvr < grows; r++) vrow[nvr++] = r;
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

/* el texto de la celda, exactamente w caracteres (en zcalc_a.s) */
void cellstr(char *o, uint8_t c, uint8_t r, uint8_t w) __sdcccall(0);
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
    gotoxy(vx[i], gtop + j);
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
    gotoxy(1, gtop - 1);
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
    for (j = 0; j < grows; j++) {
        gotoxy(1, gtop + j);
        if (j >= nvr) { pstr(EOL); continue; }
        pf(INV "%3u " NORM, vrow[j]);
        for (i = 0; i < nvc; i++) {
            cellstr(sb, vcol[i], vrow[j], CW(vcol[i]));
            if (vcol[i] == cc && vrow[j] == cr && !nohl) { pstr(INV); pstr(sb); pstr(NORM); }
            else pstr(sb);
        }
        pstr(EOL);
    }
    dirty = 0;
}
/* cambia la ventana activa por la otra */
static void swappane(void)
{
    static uint8_t t[6];
    t[0] = fr; t[1] = fc; t[2] = cc; t[3] = cr; t[4] = gtop; t[5] = grows;
    fr = opn[0]; fc = opn[1]; cc = opn[2]; cr = opn[3]; gtop = opn[4]; grows = opn[5];
    memcpy(opn, t, 6);
}
/* las dos ventanas (la otra sin cursor) */
static void drawall(void)
{
    if (win) { swappane(); nohl = 1; layout(); drawgrid(); nohl = 0; swappane(); layout(); }
    drawgrid();
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
    else if (nf == 13) o[n++] = '/';
    else if (nf == 14) o[n++] = ':';
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
        if (x->f & 0x40) pstr(" locked");
        pstr(KIND(x) >= K_NUM ? " (V) " : " (L) ");
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
    if (k == 'D') return f & 0x40;      /* el bloqueo se queda */
    if (k == 'G') return (f & 0xF0) | 1;
    if (k == 'I') return (f & 0xF0) | 3;
    if (k == '$') return (f & 0xF0) | 5;
    if (k == '*') return (f & 0xF0) | 2;
    if (k >= '0' && k <= '9') return (f & 0xF0) | (k - '0' + 3);
    if (k == '/') return (f & 0xF0) | 13;   /* fecha dd/mm/aa */
    if (k == ':') return (f & 0xF0) | 14;   /* hora hh:mm */
    if (k == 'L') return (f & 0xCF) | 0x10;
    if (k == 'R') return (f & 0xCF) | 0x20;
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
    k = ask("Format: D(efault) G I $ 0-9 *(graph) /(date) :(time) L R W(idth)");
    if (k == 'W') { if ((w = askw(CW(cc)))) { cw[cc] = w == gw ? 0 : w; modified = 1; } return; }
    x = find(cc, cr);
    f = fmtkey(k, x ? x->f : 0);
    if (f == 0xFF) return;
    if (!x) { if (!(x = newcell(cc, cr, K_LAB, 0))) { msg("Memory full"); return; } }
    x->f = f;
    if (KIND(x) == K_LAB && !x->n && !f) delcell(cc, cr);
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
        if (ins) { x->fl |= F_MARK; if (nc < 1 || nc > NC || nr < 1 || nr > NR) x->c = 0; }
        else x->fl &= ~F_MARK;
    }
    FOR_CELLS(x)
        if (!(x->fl & F_MARK) && x->c >= c1 + mdc && x->c <= c2 + mdc && x->r >= r1 + mdr && x->r <= r2 + mdr) x->c = 0;
    FOR_CELLS(x)
        if ((x->fl & F_MARK) && x->c) { x->c += mdc; x->r += mdr; }
    FOR_CELLS(x) x->fl &= ~F_MARK;
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
            if (!x || KIND(x) == K_REP) continue;
            if (KIND(x) == K_LAB) {
                oc('"');
                for (i = 0; i < x->n; i++) { if (x->d[i] == '"') oc('"'); oc(x->d[i]); }
                oc('"');
            } else if (VT(x)) os(VT(x) == V_ERR ? "#ERROR" : "#NA");
            else { if (!nplain(sb, NUMP(x), -1, 30)) nsci(sb, NUMP(x), 22); os(sb); }
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
        " Arrows (^E ^X ^S ^D) move; PgUp/PgDn (^R ^C) 20 rows; Home goes to A1.\n"
        " Type a number or formula (starting with a digit . + - ( @ =) or a label\n"
        " (\" starts a label that looks like a number). Enter or an arrow stores it;\n"
        " ESC cancels; an arrow after an operator points at cells.\n"
        " > go to a cell  ! recalc  ^L redraw  ^U undo  ^F find  ; other window\n\n"
        " Formulas: + - * / ^  = <> < > <= >=  A1 $A$1 A1:B5\n"
        "  @SUM @AVG @MIN @MAX @COUNT @LOOKUP(x,A1:A9) @ABS @INT @ROUND(x,n) @SQRT\n"
        "  @MOD(a,b) @IF(c,a,b) @AND @OR @NOT @PI @NA @ERROR @ISNA @ISERROR\n"
        "  @SIN @COS @TAN @ATAN @LN @LOG @EXP  @PMT(rate,n,pv) @PV(rate,n,pmt)\n"
        "  @FV(rate,n,pmt) @NPV(rate,list) @IRR(guess,list) @DATE(y,m,d) @TODAY\n"
        "  @NOW @YEAR @MONTH @DAY\n\n"
        " /B blank cell     /C clear sheet       /D delete row or column\n"
        " /E edit cell      /F format (/ date, : time), width   /G global settings\n"
        " /I insert row/col /L lock/unlock cells /M move cells   /O sort rows\n"
        " /P print          /R replicate         /S load, save, CSV, quit\n"
        " /T titles         /W windows           /- repeat a label  /A about\n"
        " Numbers have 9 digits and are decimal (money adds up exactly).  "
"Press any key.");
    getk();
    pstr(HIDE CLS);
    dirty = 1;
}

/* /A: acerca de ZCALC */
static void about(void)
{
    pstr(CLS INV
        ESC "[9;20H  ZCALC " VERSION "                             "
        ESC "[10;20H  Spreadsheet for CP/M 2.2, CP/M 3      "
        ESC "[11;20H  and MP/M II on the Z80-Retro          "
        ESC "[13;20H  (C) OLIVEROS 2026                     "
        ESC "[15;20H  ");
    pf("%5u bytes free for cells           " NORM ESC "[18;20HPress any key.", hfree);
    getk();
    pstr(CLS);
    dirty = 1;
}

static uint8_t quit(void)
{
    if (modified && ask("Sheet not saved. Quit anyway? (Y/N)") != 'Y') return 0;
    return 1;
}

/* celda bloqueada: avisa y da 1 */
static uint8_t locked(void)
{
    static cell *x;
    x = find(cc, cr);
    if (x && (x->f & 0x40)) { msg("Locked cell"); return 1; }
    return 0;
}
/* deshacer: lo que habia en una celda antes del ultimo cambio */
static char ub[MAXE + 2], ub2[MAXE + 2];
static uint8_t uc, ur, uf, uhas;
static void usave(void)
{
    static cell *x;
    x = find(cc, cr);
    uc = cc; ur = cr; uf = x ? x->f : 0; uhas = 1;
    celltext(x, ub, MAXE);
}
static void undo(void)
{
    static cell *x;
    static uint8_t f, lab;
    if (!uhas) { msg("Nothing to undo"); return; }
    cc = uc; cr = ur;
    x = find(cc, cr);
    f = x ? x->f : 0;
    celltext(x, ub2, MAXE);              /* para rehacer con otro ^U */
    lab = ub[0] == '"' ? 1 : ub[0] == '\\' ? 2 : 0;
    if (!ub[0]) delcell(cc, cr);
    else if (setcell(cc, cr, ub + (lab != 0), lab)) { msg("Memory full"); return; }
    if (ub[0] && (x = find(cc, cr))) x->f = uf;
    strcpy(ub, ub2); uf = f;
    modified = dirty = 1;
}
/* buscar un texto (sin importar mayusculas) desde el cursor */
static char fb_[32];
static uint8_t hasstr(const char *t, const char *w)
{
    static const char *p, *q;
    for (; *t; t++) {
        for (p = t, q = w; *q && ((*p & 0xDF) == (*q & 0xDF) || *p == *q); p++, q++) ;
        if (!*q) return 1;
    }
    return 0;
}
static void findtxt(void)
{
    static cell *x, *best, *first;
    static uint16_t k, kb, kf, kc;
    if (!input("Find: ", fb_) || !eb[0]) return;
    strncpy(fb_, eb, 31);
    best = first = 0; kb = kf = 0xFFFF;
    kc = (uint16_t)cr << 6 | cc;
    FOR_CELLS(x) {
        celltext(x, sb, 86);
        if (!hasstr(sb, fb_)) continue;
        k = (uint16_t)x->r << 6 | x->c;
        if (k > kc && k < kb) { kb = k; best = x; }
        if (k < kf) { kf = k; first = x; }
    }
    if (!best) best = first;
    if (!best) { msg("Not found"); return; }
    cc = best->c; cr = best->r;
}

static void entry(uint8_t k)
{
    static uint8_t isval;
    static uint8_t t;
    static uint8_t e;
    isval = strchr("0123456789.+-(@=$", k) != 0;
    if (k == '"') eb[0] = 0;
    else { eb[0] = k; eb[1] = 0; }
    if (locked()) return;
    for (;;) {
        t = editline(isval ? "Value: " : "Label: ", EL_MOVE | (isval ? EL_POINT : 0));
        if (t == 27) return;
        usave();
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
    if (locked()) return;
    x = find(cc, cr);
    celltext(x, eb, MAXE);
    for (;;) {
        t = editline("Edit: ", EL_POINT);
        if (t == 27) return;
        usave();
        lab = eb[0] == '"' ? 1 : eb[0] == '\\' ? 2 : 0;
        if (!eb[0] && x) { delcell(cc, cr); modified = dirty = 1; return; }
        e = setcell(cc, cr, eb + (lab != 0), lab);
        if (!e) return;
        msg(e == 2 ? "Memory full" : "Error in formula");
        if (e == 2) return;
    }
}

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
/* compara las claves de las filas a y b: <0, 0, >0 */
static int8_t skey(uint8_t a, uint8_t b)
{
    static cell *x, *y;
    static uint8_t ka, kb;
    static val va, vb;
    x = find(skc, a); y = find(skc, b);
    ka = !x ? 3 : KIND(x) >= K_NUM ? (VT(x) ? 1 : 0) : 2;   /* numero, error, texto, vacia */
    kb = !y ? 3 : KIND(y) >= K_NUM ? (VT(y) ? 1 : 0) : 2;
    if (ka != kb) return ka < kb ? -1 : 1;
    if (ka == 0) return ncmp(NUMP(x), NUMP(y));
    if (ka == 2) {
        celltext(x, sb, 40); celltext(y, eb, 40);
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

static uint8_t command(void)
{
    static uint8_t k;
    static uint8_t k2;
    k = ask("Command: A B C D E F G I L M O P R S T W - Q ?");
    switch (k) {
    case 'B': if (!locked()) { usave(); delcell(cc, cr); modified = dirty = 1; } break;
    case 'L': cmd_lock(); break;
    case 'O': cmd_sort(); break;
    case 'W':
        k2 = ask("Window: H(orizontal split) 1(one window)");
        if (k2 == 'H' && !win) {
            for (k = 0; k < nvr && vrow[k] != cr; k++) ;
            if (k < 2 || k + 3 > grows) { msg("Move the cursor to the middle of the screen"); break; }
            opn[0] = fr; opn[1] = fc; opn[2] = cc; opn[3] = cr; opn[4] = gtop + k + 1; opn[5] = grows - k - 1;
            grows = k; win = 1; dirty = 1;
        } else if (k2 == '1' && win) {
            if (gtop != GTOP) swappane();
            grows = GROWS; win = 0; dirty = 1;
        }
        break;
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
        if (k2 == 'H' || k2 == 'B') trn = cr - 1 < grows - 2 ? cr - 1 : 0;
        if (k2 == 'V' || k2 == 'B') tcn = cc - 1 < 4 ? cc - 1 : 0;
        if (k2 == 'N') tcn = trn = 0;
        fr = trn + 1; fc = tcn + 1;
        dirty = 1;
        break;
    case '-':
        if (!locked() && input("Repeat: ", "") && eb[0]) {
            usave();
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
            drawall();
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
        case KDEL: if (!locked()) { usave(); delcell(cc, cr); modified = dirty = 1; } break;
        case 21: undo(); break;                     /* ^U */
        case 6: findtxt(); break;                   /* ^F */
        case ';': if (win) { swappane(); dirty = 1; } break;
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
