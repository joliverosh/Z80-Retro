/* ZCALC 1.2 - hoja de calculo para CP/M 2.2, CP/M 3 y MP/M II (terminal ANSI de 80x24)
   ZCALC [archivo[.ZC|.WKS|.WK1]]
   63 columnas (A-BK) x 254 filas. Numeros decimales de 9 cifras: 0,1 y los
   centavos son exactos. Se maneja como las hojas de 1979: el cursor recorre la
   cuadricula, lo que se escribe va a la celda y las ordenes empiezan con '/'.
   Formulas: + - * / ^, comparaciones (= <> < > <= >=), referencias A1, $A$1,
   rangos A1:B5 (o A1...B5) y funciones @SUM @AVG @MIN @MAX @COUNT @LOOKUP
   @ABS @INT @ROUND @SQRT @MOD @IF @AND @OR @NOT @PI @NA @ERROR @ISNA @ISERROR,
   de finanzas (@PMT @PV @FV @NPV @IRR), fechas (@DATE @TODAY @NOW @YEAR @MONTH
   @DAY), trigonometria (@SIN @COS @TAN @ATAN @LN @LOG @EXP) y textos (@LEFT ...).
   El evaluador, la aritmetica y las funciones estan en zcalc_a.s; las ordenes que se
   usan de vez en cuando, en zcov*.c, que van a ZCALC.OVL (mkzcalc.sh).
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include "zcalc.h"

extern char heap[];

/* ================================================================ memoria */
/* bloques con el tamano (2 bytes) delante; los libres en una lista por direccion */
typedef struct fb { uint16_t sz; struct fb *nx; } fb;
static fb *freel;
uint16_t hfree;

void *zalloc(uint16_t n)
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

void zfree(void *p)
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
/* ================================================================ celdas */
uint8_t hb;
cell *clip;
uint8_t kc, kr;
#define HK(c, r) (((c) * 13 + (r)) & (NH - 1))
cell *ht[NH];                    /* tambien lo usa zcalc_a.s */

static void unlink_(cell *x)
{
    static cell **pp;
    for (pp = &ht[HK(x->c, x->r)]; *pp; pp = &(*pp)->nx)
        if (*pp == x) { *pp = x->nx; return; }
}
/* libera una celda (y el texto que dio su formula) */
void freecell(cell *x)
{
    if (KIND(x) == K_FRM && VT(x) == V_STR && *(char **)x->d) zfree(*(char **)x->d);
    zfree(x);
}
void delcell(uint8_t c, uint8_t r)
{
    static cell *x;
    x = find(c, r);
    if (x) { unlink_(x); freecell(x); }
}
static void link_(cell *x)
{
    static uint8_t h;
    h = HK(x->c, x->r);
    x->nx = ht[h];
    ht[h] = x;
}
/* celda nueva (reemplaza la que haya); 0 si no hay memoria */
cell *newcell(uint8_t c, uint8_t r, uint8_t k, uint8_t n)
{
    static cell *x;
    static uint8_t f;
    x = find(c, r);
    f = x ? x->f : 0;
    if (x) { unlink_(x); freecell(x); }
    x = zalloc(sizeof(cell) - 1 + n);
    if (!x) return 0;
    memset(x, 0, sizeof(cell));
    x->c = c; x->r = r; x->fl = k; x->f = f; x->n = n;
    link_(x);
    return x;
}
void clearall(void)
{
    static cell *x;
    static cell *n;
    for (hb = 0; hb < NH; hb++) {
        for (x = ht[hb]; x; x = n) { n = x->nx; freecell(x); }
        ht[hb] = 0;
    }
}
/* vuelve a poner cada celda en su lista (las de c = 0 se borran) */
void rehash(void)
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
        if (x->c) link_(x); else freecell(x);
    }
}

/* ================================================================ formulas */
/* TK_NUM m(4) e(1); TK_I8 un entero 0-255; TK_REF cf r; TK_RNG cf1 r1 cf2 r2; TK_FN id;
   TK_STR n y n letras.
   cf: columna en los bits 0-5 y los $ en el 6 (columna) y el 7 (fila).
   Una referencia borrada tiene c = 0 (#REF) */
enum { F_SUM, F_AVG, F_MIN, F_MAX, F_COUNT, F_LOOKUP, F_ABS, F_INT, F_ROUND, F_SQRT,
       F_MOD, F_IF, F_AND, F_OR, F_NOT, F_PI, F_NA, F_ERROR, F_ISNA, F_ISERR,
       F_PMT, F_PV, F_FV, F_NPV, F_IRR, F_DATE, F_TODAY, F_NOW, F_YEAR, F_MONTH, F_DAY,
       F_SIN, F_COS, F_TAN, F_ATAN, F_LN, F_EXP, F_LOG,
       F_LEFT, F_RIGHT, F_MID, F_LEN, F_UPPER, F_LOWER, F_PROPER, F_TRIM, F_VALUE, F_STRING,
       F_FIND, F_REPEAT, F_CHAR, F_CODE, F_EXACT, F_ISSTR, F_ISNUM, NFN };
/* los nombres y los argumentos de cada una estan en zcalc_a.s */

uint8_t isup(char c) { return c >= 'A' && c <= 'Z'; }
uint8_t isdig(char c) { return c >= '0' && c <= '9'; }

/* ================================================================ calculo */
/* en zcalc_a.s: la evaluacion de las formulas y el recalculo */
extern const uint8_t *tp;        /* lo que sigue en la formula */
extern uint8_t synerr, chk;      /* chk: solo revisar la sintaxis */
extern uint8_t gen, depth, again, circ;
void expr(val *v) __sdcccall(0);

/* ================================================================ entradas */
uint8_t tb[MAXT];
uint8_t modified, dirty;
/* pone lo escrito en la celda: label 1 = texto, 2 = repetido, 0 = valor.
   1 si la formula tiene un error, 2 si no hay memoria */
uint8_t setcell(uint8_t c, uint8_t r, const char *s, uint8_t label)
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
        for (i = 0, n = 0; s[i] && i < MAXE; i++) {   /* a mayusculas, salvo entre comillas */
            if (s[i] == '"') n ^= 1;
            up[i] = (!n && s[i] >= 'a' && s[i] <= 'z') ? s[i] - 32 : s[i];
        }
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
void celltext(cell *x, char *o, uint8_t max)
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
name_t nms[NNM];
uint8_t nnm;
void adjall(void)
{
    static cell *x;
    static uint8_t i;
    FOR_CELLS(x) if (KIND(x) == K_FRM) adjform(TOK(x));
    for (i = 0; i < nnm; i++) adjform(nms[i].t);
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
uint8_t copycell(cell *x, uint8_t c, uint8_t r)
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
    if (k == K_FRM) { memset(y->d, 0, 6); shiftform(TOK(y), dc, dr); }
    modified = dirty = 1;
    return 0;
}

/* ================================================================ pantalla */
uint8_t cc = 1, cr = 1;           /* cursor */
uint8_t fc = 1, fr = 1;           /* primeras columna y fila que se corren */
uint8_t tcn, trn;                 /* columnas y filas de titulos */
uint8_t gw = 9, gnf = 1;         /* tambien los usa zcalc_a.s */
uint8_t autoc = 1;
uint8_t cw[NC + 1];
static uint8_t vcol[MAXVC], vx[MAXVC], nvc, vrow[GROWS], nvr;
static uint8_t gtop = GTOP, grows = GROWS;   /* la ventana activa en pantalla */
/* ventanas: la otra (fr, fc, cc, cr, gtop, grows); win = 1 si hay dos */
static uint8_t opn[6], win, nohl;
char fname_[16];
char sb[90];

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
uint8_t getk(void)
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
uint8_t ask(const char *s)
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
char eb[MAXE + 1];
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
uint8_t input(const char *prompt, const char *init)
{
    strcpy(eb, init);
    return editline(prompt, 0) == 13;
}
static uint8_t msgon;
void msg(const char *s)
{
    msgon = 1;
    gotoxy(1, 2);
    pf(INV " %s " NORM EOL, s);
    putch(7);
}

/* ================================================================ ordenes */
uint8_t isarg(char *s, uint8_t *c, uint8_t *r)   /* una celda */
{
    uint8_t fl;
    const char *p = s;
    for (; *s; s++) if (*s >= 'a' && *s <= 'z') *s -= 32;
    while (*p == ' ') p++;
    return pref(&p, c, r, &fl) && !*p;
}
uint8_t prange(char *s, uint8_t *c1, uint8_t *r1, uint8_t *c2, uint8_t *r2)
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
void curref(char *o) { refname(o, cc, cr, 0); }
uint8_t usedmax(uint8_t *mc, uint8_t *mr)
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

/* ----------------------------------------------------- archivos */
FCB of;
uint8_t ob[128], obp, odev, oerr;
FCB inf;
uint8_t inp;              /* lo que sigue en ob al leer (128 = leer otro) */
int rdc(void)
{
    if (inp == 128) { if (fread(&inf, ob)) return -1; inp = 0; }
    return ob[inp++];
}
void oc(char c)
{
    if (odev) { bdos(5, (uint8_t)c); return; }
    ob[obp++] = c;
    if (obp == 128) { if (fwrite(&of, ob)) oerr = 1; obp = 0; }
}
void os(const char *s) { while (*s) oc(*s++); }
uint8_t oclose(void)
{
    if (odev) return 0;
    if (obp) { memset(ob + obp, 26, 128 - obp); if (fwrite(&of, ob)) oerr = 1; }
    fclose(&of);
    return oerr;
}
uint8_t ofile(const char *name)
{
    odev = 0; obp = 0; oerr = 0;
    if (!mkfcb(&of, name)) return 1;
    return fmake(&of);
}
void defext(char *s, const char *ext)
{
    static char *p;
    for (p = s; *p; p++) if (*p >= 'a' && *p <= 'z') *p -= 32;
    if (!strchr(s, '.') && strlen(s) < 10) strcat(s, ext);
}
/* lee un CSV con su esquina en el cursor: numeros como valores, lo demas texto.
   0 bien, 1 no esta, 3 sin memoria */



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


static uint8_t command(void)
{
    static uint8_t k;
    static uint8_t k2;
    k = ask("Command: A B C D E F G I K L M N O P R S T V W X - Q ?");
    switch (k) {
    case 'B': if (!locked()) { usave(); delcell(cc, cr); modified = dirty = 1; } break;
    case 'F': case 'G': case 'R': case 'M': ovl(OV_CMD, k); break;
    case 'L': case 'O': case 'K': case 'V': ovl(OV_CMD2, k); break;
    case 'N': ovl(OV_NAME, 1); break;
    case 'X': ovl(OV_CHART, 1); break;
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
            clearall(); memset(cw, 0, sizeof cw); gw = 9; gnf = 1; tcn = trn = 0; fc = fr = cc = cr = 1; nnm = 0;
            modified = 0; dirty = 1; fname_[0] = 0;
        }
        break;
    case 'D': case 'I':
        k2 = ask(k == 'D' ? "Delete: R(ow) C(olumn)" : "Insert: R(ow) C(olumn)");
        if (k2 == 'R') insdel(1, cr, k == 'D');
        else if (k2 == 'C') insdel(0, cc, k == 'D');
        break;
    case 'E': edit(); break;
    case 'P': ovl(OV_SAVE, 3); break;
    case 'S':
        k2 = ask("Storage: L(oad) S(ave) X (CSV) W(KS for 1-2-3) Q(uit)");
        if (k2 == 'L') { if (ovl(OV_LOAD, 1) == 9) { ovl(OV_WKS, 1); ovl(OV_WKSF, 1); } }
        else if (k2 == 'S') ovl(OV_SAVE, 1);
        else if (k2 == 'X') ovl(OV_SAVE, 2);
        else if (k2 == 'W') ovl(OV_WKSW, 1);
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
    case '?': ovl(OV_HELP, 1); break;
    case 'A': ovl(OV_HELP, 2); break;
    }
    return 0;
}

/* ================================================================ partes cargadas */
/* ZCALC.OVL: el registro 0 dice "ZCOVL", la marca de esta version (4 bytes) y,
   por cada parte, el registro donde empieza y cuantos ocupa. Cada parte esta
   enlazada para correr en ovlreg y empieza con un salto a su ovl_entry(op). */
uint8_t ovlreg[OVLSZ];
uint8_t ovlret, ovlop;
void *wkl;                       /* formulas de 1-2-3 por pasar (zcov8 -> zcova) */
static uint8_t ovlcur, ovldrv;
static FCB ovf;
extern const uint8_t ovlmark[4];       /* en zcalc_a.s */
static uint8_t ovlopen(uint8_t d)
{
    mkfcb(&ovf, "ZCALC.OVL");
    ovf.dr = d;
    if (fopen(&ovf)) return 1;
    if (rread(&ovf, 0, ovlreg) || memcmp(ovlreg, "ZCOVL", 5) || memcmp(ovlreg + 5, ovlmark, 4)) { fclose(&ovf); return 1; }
    ovldrv = d;
    return 0;
}
/* busca ZCALC.OVL: en la unidad de donde se cargo ZCALC (CP/M 3 la deja en 0050h),
   en la actual y en A: */
static uint8_t ovlfind(void)
{
    static uint8_t d;
    d = (bdos(12, 0) & 0xFF) == 0x31 ? *(uint8_t *)0x50 : 0;   /* solo CP/M 3 lo dice */
    if ((d && d <= 16 && !ovlopen(d)) || !ovlopen(0) || !ovlopen(1)) { fclose(&ovf); return 0; }
    return 1;
}
uint8_t ovl(uint8_t n, uint8_t op)
{
    static uint8_t i, s, k;
    if (ovlcur != n) {
        ovlcur = 0;
        if (ovlopen(ovldrv)) { msg("ZCALC.OVL not found"); return 0; }
        s = ovlreg[9 + 2 * (n - 1)]; k = ovlreg[10 + 2 * (n - 1)];
        for (i = 0; i < k; i++)
            if (rread(&ovf, s + i, ovlreg + 128 * i)) { fclose(&ovf); msg("Can't read ZCALC.OVL"); return 0; }
        fclose(&ovf);
        ovlcur = n;
    }
    ovlret = 0;
    ovlop = op;                          /* zcovh.s la pasa a ovl_entry */
    ((void (*)(void))ovlreg)();
    return ovlret;
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
    if (ovlfind()) { pstr("ZCALC.OVL not found (it goes with ZCALC.COM)\n"); return; }
    pstr(HIDE CLS);
    f = nextarg(&a);
    if (f && *f) {
        strncpy(eb, f, 15); eb[15] = 0;
        defext(eb, ".ZC");
        k = ovl(OV_LOAD, 2);
        if (k == 9) { k = ovl(OV_WKS, 1); ovl(OV_WKSF, 1); }
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
        case '?': ovl(OV_HELP, 1); break;
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
