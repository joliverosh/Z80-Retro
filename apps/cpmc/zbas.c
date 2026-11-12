/* ZBAS - BASIC estructurado para CP/M 2.2, CP/M 3 y MP/M II
   ZBAS                  el interprete (escribir lineas, RUN, LIST, SAVE...)
   ZBAS programa[.BAS]   lo carga, lo corre y sale
   Numeros decimales de 9 cifras (los de ZCALC: 0,1 + 0,2 = 0,3), textos de
   cualquier largo, nombres largos, sin numeros de linea (o con ellos), IF/ELSEIF/
   ELSE/END IF, FOR, WHILE, DO/LOOP, SELECT CASE, SUB y FUNCTION con variables
   locales y recursion, matrices de hasta 3 dimensiones, archivos, y las funciones
   de ZCALC (finanzas, fechas, trigonometria). Las lineas se guardan compiladas:
   las palabras a un byte, los numeros ya convertidos y cada nombre como el numero
   de su variable, asi no se busca nada al correr.
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include "zbas.h"

/* ---------------------------------------------------------------- memoria */
/* [programa: las lineas][nombres] ... [datos: un heap que se vacia con CLEAR] ... pila */
extern char heap[];
uint8_t *prog, *pend;     /* las lineas: largo(2) numero(2) salto(2) palabras 0 */
uint8_t *names, *nend;    /* los nombres: clase(1) largo(1) letras */
uint16_t nsym;
uint8_t *dbase, *dtop;    /* el heap de datos */
uint8_t *memtop;

/* el heap de datos: bloques con el tamano delante, libres en una lista por direccion */
fb *freel;
uint16_t hfree;
uint8_t *htop;
void heapinit(void)
{
    htop = ovb ? ovb : memtop;
    dbase = (uint8_t *)(((uint16_t)nend + 65) & ~1);   /* un poco de lugar para nombres nuevos */
    freel = (fb *)dbase;
    freel->sz = (uint16_t)(htop - dbase) & ~1;
    freel->nx = 0;
    hfree = freel->sz;
}
void *zalloc1(uint16_t n)
{
    static fb **pp, *b, *r;
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
    static fb *b, **pp, *pv;
    if (!p) return;
    b = (fb *)((char *)p - 2);
    pv = 0;
    for (pp = &freel; *pp && *pp < b; pp = &(*pp)->nx) pv = *pp;
    b->nx = *pp; *pp = b; hfree += b->sz;
    if (b->nx && (char *)b + b->sz == (char *)b->nx) { b->sz += b->nx->sz; b->nx = b->nx->nx; }
    if (pv && (char *)pv + pv->sz == (char *)b) { pv->sz += b->sz; pv->nx = b->nx; }
}
uint8_t inovl;            /* corre la parte cargada (no se la puede sacar) */
extern uint8_t ovcur;
void ovfree(void)         /* devuelve al heap el lugar de la parte cargada */
{
    fb *b;
    if (!ovb || inovl) return;
    b = (fb *)ovb;
    b->sz = memtop - ovb;
    ovb = 0; htop = memtop; ovcur = 0;
    zfree((char *)b + 2);
}
void *zalloc(uint16_t n)
{
    void *p = zalloc1(n);
    if (!p && ovb && !inovl) { ovfree(); p = zalloc1(n); }
    return p;
}

/* ---------------------------------------------------------------- errores */
jmp_buf errjb;
uint16_t errline;         /* la linea donde paso (0 = directo) */
uint8_t running;
uint8_t errn;
/* los mensajes de error, separados por 0 */
void error(uint8_t n)
{
    errn = n;
    longjmp(errjb, 1);
}
void *xalloc(uint16_t n)
{
    void *p = zalloc(n);
    if (!p) error(1);
    return p;
}

/* ---------------------------------------------------------------- valores */
/* un valor: numero o texto (bloque del heap con el largo delante; NULL = "") */
/* las variables: un lugar de 6 bytes por nombre (en el heap de datos) */
/* (matrices: a; SUB, FUNCTION y etiquetas: f.l la linea, f.r la variable del resultado) */
slot *vars;
uint16_t nvars;
/* el nombre i: su clase y sus letras */
uint8_t *symat(uint16_t i)
{
    static uint8_t *p;
    p = names;
    while (i--) p += 2 + p[1];
    return p;
}
void growvars(void)
{
    static slot *nv;
    if (nvars >= nsym) return;
    nv = xalloc(nsym * sizeof(slot) + 1);
    memset(nv, 0, nsym * sizeof(slot));
    if (vars) { memcpy(nv, vars, nvars * sizeof(slot)); zfree(vars); }
    vars = nv;
    nvars = nsym;
}
slot *var(uint16_t i)
{
    if (i >= nvars) growvars();
    return &vars[i];
}
void sfree_(value *v) { if (v->s && v->p) zfree(v->p); v->p = 0; v->l = 0; }
void newstr(value *v, const uint8_t *s, uint16_t n)
{
    v->s = 1; v->l = n; v->p = 0;
    if (n) { v->p = xalloc(n); memcpy(v->p, s, n); }
}

/* ---------------------------------------------------------------- consola */
uint8_t col;              /* columna de la consola (para TAB y las comas) */
uint8_t outf;             /* PRINT #: 0 consola */
void outc(uint8_t c);
void conc(uint8_t c)
{
    putch(c);
    if (c == 13) col = 0; else if (c == 8) { if (col) col--; } else if (c >= 32) col++;
}
void cons(const char *s) { while (*s) { if (*s == '\n') conc(13); conc(*s++); } }
uint8_t brkchk(void)
{
    static int k;
    if ((k = getkey()) == 3 || k == 27) return 1;
    return 0;
}
/* una linea del teclado en lb (con el texto inicial que tenga) */
char lb[256];
uint8_t getline_(uint8_t n0)
{
    static uint8_t n, c;
    n = n0;
    lb[n] = 0;
    cons(lb);
    oflush();
    for (;;) {
        c = waitkey();
        if (c == 13 || c == 10) break;
        if (c == 3) { cons("^C\n"); lb[0] = 0; return 0; }
        if (c == 8 || c == 127) { if (n) { n--; cons("\b \b"); } continue; }
        if (c == 24 || c == 21) { while (n) { n--; cons("\b \b"); } continue; }   /* ^X ^U */
        if (c >= 32 && n < 250) { lb[n++] = c; conc(c); oflush(); }
    }
    lb[n] = 0;
    cons("\n");
    return 1;
}

/* ---------------------------------------------------------------- compilar */
void conss(const char *s) { cons(s); }
uint8_t isal(uint8_t c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_'; }
uint8_t isdg(uint8_t c) { return c >= '0' && c <= '9'; }
uint8_t up(uint8_t c) { return c >= 'a' && c <= 'z' ? c - 32 : c; }
/* ---------------------------------------------------------------- el programa */
uint8_t *findline(uint16_t n, uint8_t exact)   /* la linea n (o la siguiente) */
{
    static uint8_t *p;
    for (p = prog; p < pend; p += LLEN(p)) if (LNUM(p) >= n) break;
    if (exact && (p >= pend || LNUM(p) != n)) return 0;
    return p;
}

/* ---------------------------------------------------------------- correr: el estado */
uint8_t *cl;              /* la linea actual (0 = directo) */
uint8_t *tp;              /* la palabra que sigue */
uint8_t direct[260];      /* la linea directa: encabezado falso y palabras */
uint8_t tron;
/* la pila de control: FOR, GOSUB, WHILE, DO, CALL, SELECT */
ctl cs[NCTL];
uint8_t csp;
/* las locales guardadas (SUB, FUNCTION, LOCAL): el indice y el valor anterior */
saved sv[NSAV];
uint8_t svp;
uint8_t *dnext, *datap;     /* READ: donde buscar la DATA siguiente y lo que sigue */
uint8_t *contline, *conttp;
FCB *files[4];
uint8_t *fbuf[4], fpos[4], fmode[4], feof_[4];
value retv;               /* el valor de FUNCTION */
uint8_t retset;

void clearvars(void)
{
    static uint8_t i;
    for (i = 0; i < 4; i++) if (files[i]) { fclose(files[i]); files[i] = 0; }
    heapinit();
    vars = 0; nvars = 0;
    csp = 0; svp = 0;
    dnext = 0; datap = 0;
    contline = 0;
    resolved = 0;
}
void newprog(void) { pend = prog; names = nend = prog; nsym = 0; clearvars(); }

/* ---------------------------------------------------------------- las expresiones */
void expr(value *v);
uint8_t peek(void) { return *tp; }
void skip(uint8_t c) { if (*tp != c) error(5); tp++; }
uint8_t accept(uint8_t c) { if (*tp == c) { tp++; return 1; } return 0; }
void numexpr(num *n)
{
    value v;
    expr(&v);
    if (v.s) { sfree_(&v); error(6); }
    *n = v.n;
}
int16_t intexpr(void) { num n; numexpr(&n); return ntoi(&n); }
void strexpr(value *v) { expr(v); if (!v->s) error(7); }
void setn(value *v, int16_t i) { v->s = 0; nset(&v->n, i); }
void setb(value *v, uint8_t b) { setn(v, b ? -1 : 0); }
uint8_t truth(const num *n) { return n->m != 0; }

/* un elemento de matriz: el lugar */
slot *arrsize(uint16_t ix, uint16_t *dims, uint8_t nd, uint8_t isstr)
{
    static slot *s;
    static uint32_t n;
    static arrhdr *h;
    static uint8_t i;
    static uint16_t es;
    s = var(ix);
    if (s->u.a.a) error(8);
    n = 1;
    for (i = 0; i < nd; i++) n *= (uint32_t)dims[i] + 1;
    es = isstr ? 4 : 5;
    if (n * es > 60000UL) error(1);
    h = xalloc(sizeof(arrhdr) + n * es);
    memset(h, 0, sizeof(arrhdr) + n * es);
    h->nd = nd;
    for (i = 0; i < nd; i++) h->d[i] = dims[i];
    s->u.a.a = h;
    s->t = isstr ? S_SARR : S_NARR;
    return s;
}
uint8_t *element(uint16_t ix, uint8_t isstr)   /* tp en el ( */
{
    uint16_t sub[3], off, d;
    uint8_t nd, i;
    slot *s;
    arrhdr *h;
    nd = 0;
    skip('(');
    do { if (nd == 3) error(9); sub[nd++] = intexpr(); } while (accept(','));
    skip(')');
    s = var(ix);
    if (!s->u.a.a) { uint16_t dd[3]; for (i = 0; i < nd; i++) dd[i] = 10; arrsize(ix, dd, nd, isstr); }
    h = s->u.a.a;
    if (h->nd != nd) error(10);
    off = 0;
    for (i = 0; i < nd; i++) {
        d = h->d[i] + 1;
        if (sub[i] >= d || (int16_t)sub[i] < 0) error(11);
        off = off * d + sub[i];
    }
    return (uint8_t *)(h + 1) + off * (isstr ? 4 : 5);
}

/* Las expresiones son recursivas: aqui las variables son automaticas (en la pila) */
void callfn(uint16_t ix, value *v);
void func(uint8_t f, value *v);
void primary(value *v)
{
    uint8_t c;
    uint16_t ix;
    uint8_t *p;
    c = *tp++;
    switch (c) {
    case T_NUM: v->s = 0; memcpy(&v->n, tp, 5); tp += 5; return;
    case T_STR: newstr(v, tp + 1, *tp); tp += 1 + *tp; return;
    case '(': expr(v); skip(')'); return;
    case '-': primary(v); if (v->s) error(12); v->n.m = -v->n.m; return;
    case '+': primary(v); return;
    case K_NOT: primary(v); if (v->s) error(12); setn(v, ~ntoi(&v->n)); return;
    case T_ID:
        ix = tp[0] | tp[1] << 8; tp += 2;
        p = symat(ix);
        switch (p[0]) {
        case S_NUM: v->s = 0; v->n = var(ix)->u.n; return;
        case S_STR: { slot *s = var(ix); newstr(v, s->u.s.p, s->u.s.l); return; }
        case S_NARR: { uint8_t *e = element(ix, 0); v->s = 0; memcpy(&v->n, e, 5); return; }
        case S_SARR: { uint8_t *e = element(ix, 1); newstr(v, *(uint8_t **)e, *(uint16_t *)(e + 2)); return; }
        case S_FUNC: case S_SFUNC: callfn(ix, v); return;
        }
        error(13);
    }
    if (c >= F_FIRST && c < F_LAST) { func(c, v); return; }
    tp--;
    error(5);
}
void power(value *v)
{
    value w;
    primary(v);
    while (*tp == '^') {
        tp++;
        primary(&w);
        if (v->s || w.s) error(12);
        nerr = 0;
        npow(&v->n, &v->n, &w.n);
        if (nerr) error(14);
    }
}
void term(value *v)
{
    uint8_t op;
    value w;
    num t;
    power(v);
    while ((op = *tp) == '*' || op == '/' || op == '\\' || op == K_MOD) {
        tp++;
        power(&w);
        if (v->s || w.s) error(12);
        nerr = 0;
        if (op == '*') nmul(&v->n, &v->n, &w.n);
        else {
            if (!w.n.m) error(15);
            if (op == '/') ndiv(&v->n, &v->n, &w.n);
            else {
                ndiv(&t, &v->n, &w.n); ntrunc(&t, &t);
                if (op == '\\') v->n = t;
                else { nmul(&t, &t, &w.n); nsub(&v->n, &v->n, &t); }
            }
        }
        if (nerr) error(14);
    }
}
void sum(value *v)
{
    uint8_t op;
    value w;
    term(v);
    while ((op = *tp) == '+' || op == '-' || op == '&') {
        tp++;
        term(&w);
        if (v->s || w.s) {
            if (op == '-' || !v->s || !w.s) { sfree_(v); sfree_(&w); error(12); }
            {   /* unir los textos */
                uint16_t n = v->l + w.l;
                uint8_t *p = 0;
                if (n > 32000) error(1);
                if (n) { p = xalloc(n); if (v->l) memcpy(p, v->p, v->l); if (w.l) memcpy(p + v->l, w.p, w.l); }
                sfree_(v); sfree_(&w);
                v->s = 1; v->p = p; v->l = n;
            }
            continue;
        }
        if (op == '&') error(12);
        nerr = 0;
        if (op == '+') nadd(&v->n, &v->n, &w.n); else nsub(&v->n, &v->n, &w.n);
        if (nerr) error(14);
    }
}
int8_t scmp(value *a, value *b)
{
    uint16_t i, n;
    n = a->l < b->l ? a->l : b->l;
    for (i = 0; i < n; i++) if (a->p[i] != b->p[i]) return a->p[i] < b->p[i] ? -1 : 1;
    return a->l < b->l ? -1 : a->l > b->l;
}
void relation(value *v)
{
    uint8_t op;
    int8_t c;
    value w;
    sum(v);
    while ((op = *tp) == '=' || op == '<' || op == '>' || op == K_LE || op == K_GE || op == K_NE) {
        tp++;
        sum(&w);
        if (v->s != w.s) { sfree_(v); sfree_(&w); error(12); }
        if (v->s) { c = scmp(v, &w); sfree_(v); sfree_(&w); }
        else c = ncmp(&v->n, &w.n);
        switch (op) {
        case '=': setb(v, !c); break;
        case '<': setb(v, c < 0); break;
        case '>': setb(v, c > 0); break;
        case K_LE: setb(v, c <= 0); break;
        case K_GE: setb(v, c >= 0); break;
        default: setb(v, c != 0);
        }
    }
}
void andexpr(value *v)
{
    int16_t a;
    value w;
    relation(v);
    while (*tp == K_AND) {
        tp++;
        if (v->s) error(12);
        a = ntoi(&v->n);
        relation(&w);
        if (w.s) error(12);
        setn(v, a & ntoi(&w.n));
    }
}
void expr(value *v)
{
    uint8_t op;
    int16_t a;
    value w;
    andexpr(v);
    while ((op = *tp) == K_OR || op == K_XOR) {
        tp++;
        if (v->s) error(12);
        a = ntoi(&v->n);
        andexpr(&w);
        if (w.s) error(12);
        setn(v, op == K_OR ? a | ntoi(&w.n) : a ^ ntoi(&w.n));
    }
}

/* ---------------------------------------------------------------- funciones */
uint8_t clk[4], csec;     /* el reloj de MP/M o CP/M 3: dias(2) hh mm, y ss (BCD) */
uint8_t clock_(void)
{
    if ((bdos(12, 0) & 0xFF) < 0x30) return 0;
    csec = bdos(105, (uint16_t)clk);
    return clk[0] | clk[1];
}
uint8_t b2(uint8_t b) { return (b >> 4) * 10 + (b & 15); }
void substr(value *v, value *s, uint16_t from, uint16_t n)   /* v = s[from, from + n) */
{
    if (from > s->l) from = s->l;
    if (n > s->l - from) n = s->l - from;
    newstr(v, s->p + from, n);
}
/* los argumentos de cada funcion: N numero, S texto, ? cualquiera; en minuscula, opcional.
   Despues de '/', el id de la funcion de znum_a.s (cfunc) si es de esas */
const char *const fsig[] = {
    "N", "N", "N", "N", "N", "N/\x1f", "N/\x20", "N/\x21", "N/\x22", "N/\x23",
    "N/\x25", "N/\x24", "n", "", "Nn", "NNN/\x14", "NNN/\x15", "NNN/\x16", "NNN/\x19", "/\x1a",
    "/\x1b", "N/\x1c", "N/\x1d", "N/\x1e", "S", "SN", "SN", "SNn", "??s", "S",
    "S", "N", "S", "N", "S", "N", "N?", "S", "S", "S",
    "N", "", "", "", "N", "NN", "NN", "NN", "n", "n",
};
void func(uint8_t f, value *v)
{
    value a[3];
    uint8_t n = 0, i, mn = 0, mx = 0;
    const char *sg = fsig[f - F_FIRST];
    num t;
    int16_t k;
    if (*tp == '(') {
        tp++;
        if (*tp != ')') do { if (n == 3) error(16); expr(&a[n++]); } while (accept(','));
        skip(')');
    }
    for (i = 0; sg[i] && sg[i] != '/'; i++) {        /* revisar los argumentos */
        mx++;
        if (sg[i] < 'a') mn++;
        if (i < n && ((sg[i] | 32) == 'n' && a[i].s || (sg[i] | 32) == 's' && !a[i].s)) error(12);
    }
    if (n < mn || n > mx) error(17);
    if (sg[i] == '/') {                              /* las de znum_a.s */
        val r, x[3];
        for (i = 0; i < n; i++) { x[i].t = 0; x[i].n = a[i].n; }
        cfunc(&r, x, n, sg[mx + 1]);
        if (r.t == V_NA) error(18);
        if (r.t) error(19);
        v->s = 0; v->n = r.n;
        return;
    }
    v->s = 0;
    if (n && !a[0].s) t = a[0].n;
    k = n > 1 && !a[1].s ? ntoi(&a[1].n) : 0;
    switch (f) {
    case F_PI: v->n.m = 314159265; v->n.e = -8; return;
    case F_RND: {
        uint32_t r = (uint32_t)rnd() << 16 | rnd();
        while (r >= 1000000000UL) r -= 1000000000UL;
        mk32(&v->n, r, 0, -9);
        if (n && t.e >= 0 && t.m > 1) {               /* RND(n): un entero de 1 a n */
            nmul(&t, &v->n, &t); ntrunc(&t, &t); nset(&v->n, 1); nadd(&v->n, &v->n, &t);
        }
        return;
    }
    case F_FRE: mk32(&v->n, hfree + (ovb ? memtop - ovb : 0), 0, 0); return;
    case F_POS: nset(&v->n, col + 1); return;
    case F_INKEY: { uint8_t c = getkey(); newstr(v, &c, c ? 1 : 0); return; }
    case F_DATES: case F_TIMES: {
        char b[10];
        if (!clock_()) { newstr(v, 0, 0); return; }
        if (f == F_TIMES) {
            b[0] = '0' + (clk[2] >> 4); b[1] = '0' + (clk[2] & 15); b[2] = ':';
            b[3] = '0' + (clk[3] >> 4); b[4] = '0' + (clk[3] & 15); b[5] = ':';
            b[6] = '0' + (csec >> 4); b[7] = '0' + (csec & 15);
            newstr(v, (uint8_t *)b, 8);
        } else {
            uint16_t y; uint8_t mo, d;
            ymd(clk[0] | clk[1] << 8, &y, &mo, &d);
            b[0] = '0' + d / 10; b[1] = '0' + d % 10; b[2] = '/'; b[3] = '0' + mo / 10; b[4] = '0' + mo % 10; b[5] = '/';
            utoa_(y, b + 6);
            newstr(v, (uint8_t *)b, 10);
        }
        return;
    }
    case F_ABS: if (t.m < 0) t.m = -t.m; v->n = t; return;
    case F_INT: case F_FIX:
        ntrunc(&v->n, &t);
        if (f == F_INT && t.m < 0 && ncmp(&v->n, &t)) { nset(&t, 1); nsub(&v->n, &v->n, &t); }
        return;
    case F_SGN: nset(&v->n, t.m > 0 ? 1 : t.m < 0 ? -1 : 0); return;
    case F_SQR: if (nsqrt(&v->n, &t)) error(20); return;
    case F_ROUND: nround(&v->n, &t, (int8_t)k); return;
    case F_MIN: case F_MAX: v->n = (ncmp(&t, &a[1].n) < 0) == (f == F_MIN) ? t : a[1].n; return;
    case F_EOF:
        i = ntoi(&t) - 1;
        if (i > 3 || !files[i]) error(21);
        setb(v, feof_[i]);
        return;
    case F_CHR: { uint8_t c = ntoi(&t); newstr(v, &c, 1); return; }
    case F_SPACE: case F_STRING: {
        uint8_t c = ' ';
        k = ntoi(&t); if (k < 0) k = 0;
        if (f == F_STRING) { if (a[1].s) { c = a[1].l ? a[1].p[0] : ' '; sfree_(&a[1]); } else c = ntoi(&a[1].n); }
        newstr(v, 0, 0);
        if (k) { v->p = xalloc(k); memset(v->p, c, k); v->l = k; }
        return;
    }
    case F_HEX: {
        char b[5]; uint16_t x = ntoi(&t); uint8_t m = 0, d;
        for (d = 0; d < 4; d++) { uint8_t h = x >> 12; if (h || m || d == 3) b[m++] = h < 10 ? '0' + h : 'A' + h - 10; x <<= 4; }
        newstr(v, (uint8_t *)b, m);
        return;
    }
    case F_STR: case F_FORMAT: {
        char b[24];
        uint8_t m;
        if (f == F_FORMAT) { if (k > 9) k = 9; nround(&t, &t, k); }
        else k = -1;
        if (!(m = nplain(b, &t, k, 22))) m = nsci(b, &t, 22);
        newstr(v, (uint8_t *)b, m);
        return;
    }
    }
    /* las de texto: a[0] es un texto (o, en INSTR con 3, a[1]) */
    switch (f) {
    case F_LEN: mk32(&v->n, a[0].l, 0, 0); break;
    case F_ASC: if (!a[0].l) error(22); nset(&v->n, a[0].p[0]); break;
    case F_LEFT: case F_RIGHT:
        if (k < 0) k = 0;
        if (k > a[0].l) k = a[0].l;
        substr(v, &a[0], f == F_LEFT ? 0 : a[0].l - k, k);
        break;
    case F_MID: {
        int16_t c = n == 3 ? ntoi(&a[2].n) : 32000;
        if (c < 0) c = 0;
        substr(v, &a[0], k > 1 ? k - 1 : 0, c);
        break;
    }
    case F_INSTR: {
        uint16_t st = 0, i0, j;
        value *h = &a[0], *nd = &a[1];
        if (n == 3) { st = ntoi(&a[0].n); if (st) st--; h = &a[1]; nd = &a[2]; }
        if (!h->s || !nd->s) error(12);
        nset(&v->n, 0);
        for (i0 = st; i0 + nd->l <= h->l; i0++) {
            for (j = 0; j < nd->l && h->p[i0 + j] == nd->p[j]; j++) ;
            if (j == nd->l) { mk32(&v->n, i0 + 1, 0, 0); break; }
        }
        sfree_(h); sfree_(nd);
        return;
    }
    case F_UCASE: case F_LCASE: {
        uint16_t e;
        *v = a[0];
        for (e = 0; e < v->l; e++) {
            uint8_t c = v->p[e];
            if (f == F_UCASE ? c >= 'a' && c <= 'z' : c >= 'A' && c <= 'Z') v->p[e] = c ^ 32;
        }
        return;
    }
    case F_TRIM: case F_LTRIM: case F_RTRIM: {
        uint16_t a0 = 0, e = a[0].l;
        if (f != F_RTRIM) while (a0 < e && a[0].p[a0] == ' ') a0++;
        if (f != F_LTRIM) while (e > a0 && a[0].p[e - 1] == ' ') e--;
        substr(v, &a[0], a0, e - a0);
        break;
    }
    case F_VAL: {
        char b[40];
        uint8_t m = 0, neg = 0, *q = a[0].p;
        uint16_t r = a[0].l;
        while (r && *q == ' ') { q++; r--; }
        while (r && m < 39) { b[m++] = *q++; r--; }
        b[m] = 0;
        q = (uint8_t *)b;
        if (*q == '-' || *q == '+') { neg = *q == '-'; q++; }
        nset(&v->n, 0);
        if (isdg(*q) || (*q == '.' && isdg(q[1]))) { nerr = 0; pnum((char *)q, &v->n); if (nerr) nset(&v->n, 0); }
        if (neg) v->n.m = -v->n.m;
        break;
    }
    }
    sfree_(&a[0]);
}

/* ---------------------------------------------------------------- recorrer el programa */
uint8_t tsize(const uint8_t *p)
{
    switch (*p) {
    case T_NUM: return 6;
    case T_STR: return 2 + p[1];
    case T_ID: case T_LNUM: return 3;
    case T_RAW: return 1 + strlen((char *)p + 1);
    }
    return 1;
}
uint8_t *nextline(uint8_t *l) { return l == direct ? 0 : (l + LLEN(l) < pend ? l + LLEN(l) : 0); }
/* wl, wp: una sentencia del programa. wnext va a la que sigue y devuelve su primera palabra
   (0 al final). Una sentencia empieza al principio de una linea o despues de ':' */
uint8_t *wl, *wp;
uint8_t wfirst(void)
{
    if (*wp == T_ID && wp[3] == ':' && symat(wp[1] | wp[2] << 8)[0] == S_LABEL) wp += 4;   /* etiqueta */
    return *wp;
}
uint8_t wnext(void)
{
    for (;;) {
        while (*wp != T_END && *wp != ':') wp += tsize(wp);
        if (*wp == ':') { wp++; return wfirst(); }
        wl = nextline(wl);
        if (!wl) return 0;
        wp = LTOK(wl);
        return wfirst();
    }
}
uint8_t blockif(const uint8_t *p)  /* el IF en p termina en THEN: es de bloque */
{
    uint8_t then = 0;
    for (; *p != T_END; p += tsize(p)) {
        if (*p == K_THEN) then = 1;
        else if (then) return *p == T_RAW;
    }
    return then;
}
/* busca desde la sentencia que sigue a (wl, wp) la que cierra el bloque 'open' al mismo
   nivel; para IF tambien se detiene en ELSEIF y ELSE (si stopelse). Deja (wl, wp) en
   esa sentencia y devuelve su palabra */
uint8_t findend(uint8_t open, uint8_t stopelse)
{
    uint8_t k, d = 0;
    for (;;) {
        k = wnext();
        if (!k) {
            switch (open) {
            case K_FOR: error(23);
            case K_WHILE: error(24);
            case K_DO: error(25);
            case K_IF: error(26);
            case K_SELECT: error(27);
            }
            error(28);
        }
        switch (open) {
        case K_FOR: if (k == K_FOR) d++; else if (k == K_NEXT) { if (!d) return k; d--; } break;
        case K_WHILE: if (k == K_WHILE) d++; else if (k == K_WEND) { if (!d) return k; d--; } break;
        case K_DO: if (k == K_DO) d++; else if (k == K_LOOP) { if (!d) return k; d--; } break;
        case K_IF:
            if (k == K_IF && blockif(wp)) d++;
            else if (k == K_END && wp[1] == K_IF) { if (!d) return k; d--; }
            else if (!d && stopelse && (k == K_ELSE || k == K_ELSEIF)) return k;
            break;
        case K_SELECT:
            if (k == K_SELECT) d++;
            else if (k == K_END && wp[1] == K_SELECT) { if (!d) return k; d--; }
            else if (!d && stopelse && k == K_CASE) return k;
            break;
        case K_SUB: case K_FUNCTION:
            if (k == K_END && (wp[1] == K_SUB || wp[1] == K_FUNCTION)) return k;
            break;
        }
    }
}
/* salta la sentencia en tp (hasta ':' o el fin de la linea) */
void skipstmt(void) { while (*tp != T_END && *tp != ':') tp += tsize(tp); }
/* sigue en la sentencia (wl, wp) */
void jumpw(void) { cl = wl; tp = wp; }
/* busca el fin del bloque que abre la sentencia en curso */
uint8_t findendc(uint8_t open, uint8_t stopelse) { wl = cl; wp = tp; return findend(open, stopelse); }

/* ---------------------------------------------------------------- asignar */
void store(slot *s, uint8_t isstr, value *v)   /* v pasa a la variable */
{
    if (isstr != v->s) { sfree_(v); error(12); }
    if (isstr) { if (s->u.s.p) zfree(s->u.s.p); s->u.s.p = v->p; s->u.s.l = v->l; v->p = 0; }
    else s->u.n = v->n;
}
/* el lugar de una variable o un elemento (tp en el nombre); *isstr dice el tipo */
uint8_t *lvalue(uint8_t *isstr, slot **sp)
{
    uint16_t ix;
    uint8_t *p, k, s;
    if (*tp != T_ID) error(29);
    ix = tp[1] | tp[2] << 8; tp += 3;
    p = symat(ix);
    *sp = 0;
    k = p[0];
    if (k > S_SARR) error(30);
    s = k == S_STR || k == S_SARR;      /* (asi: SDCC pasaba mal la constante a element) */
    *isstr = s;
    if (k <= S_STR) { *sp = var(ix); return 0; }
    return element(ix, s);
}
void assignto(uint8_t *e, slot *s, uint8_t isstr, value *v)
{
    if (s) { store(s, isstr, v); return; }
    if (isstr != v->s) { sfree_(v); error(12); }
    if (isstr) { if (*(uint8_t **)e) zfree(*(uint8_t **)e); *(uint8_t **)e = v->p; *(uint16_t *)(e + 2) = v->l; v->p = 0; }
    else memcpy(e, &v->n, 5);
}
void let(void)
{
    uint8_t isstr, *e;
    slot *s;
    value v;
    e = lvalue(&isstr, &s);
    skip('=');
    expr(&v);
    assignto(e, s, isstr, &v);
}

/* ---------------------------------------------------------------- PRINT */
uint8_t fbufp[4];
uint16_t frec[4];
void fflush_(uint8_t h);
void outc(uint8_t c)
{
    if (!outf) { conc(c); return; }
    {
        uint8_t h = outf - 1;
        fbuf[h][fpos[h]++] = c;
        if (fpos[h] == 128) fflush_(h);
    }
}
void outs(const uint8_t *s, uint16_t n) { while (n--) { if (*s == '\n' && !outf) conc(13); outc(*s++); } }
void outnum(const num *n)
{
    char b[24];
    uint8_t k;
    b[0] = ' ';                          /* como siempre en BASIC: el lugar del signo */
    if (!(k = nplain(b + 1, n, -1, 14))) k = nsci(b + 1, n, 14);
    if (b[1] == '-') outs((uint8_t *)b + 1, k); else outs((uint8_t *)b, k + 1);
    outc(' ');                           /* y un espacio despues */
}
uint8_t chan(void)        /* #n, : el archivo */
{
    uint8_t h;
    tp++;
    h = intexpr();
    if (!h || h > 4 || !files[h - 1]) error(21);
    return h;
}
void print(void)
{
    value v;
    uint8_t last = 0;
    if (*tp == '#') { outf = chan(); if (!accept(',')) { if (*tp != T_END && *tp != ':') error(5); } }
    while (*tp != T_END && *tp != ':' && *tp != K_ELSE) {
        last = 0;
        if (*tp == ';') { tp++; last = 1; continue; }
        if (*tp == ',') { tp++; do outc(' '); while (outf ? 0 : col % 14); last = 1; continue; }
        if (*tp == K_TAB || *tp == K_SPC) {
            uint8_t k = *tp++;
            int16_t n;
            skip('('); n = intexpr(); skip(')');
            if (k == K_TAB) { n--; if (!outf) while (col < n) outc(' '); }
            else while (n-- > 0) outc(' ');
            last = 1;
            continue;
        }
        expr(&v);
        if (v.s) { outs(v.p, v.l); sfree_(&v); }
        else outnum(&v.n);
    }
    if (!last) { if (outf) { outc(13); outc(10); } else conc(13), conc(10); }
    outf = 0;
}

/* ---------------------------------------------------------------- archivos */
void fflush_(uint8_t h)
{
    if (fpos[h] < 128) memset(fbuf[h] + fpos[h], 0x1A, 128 - fpos[h]);
    if (rwrite(files[h], frec[h], fbuf[h])) { error(31); }
    if (fpos[h] == 128) { frec[h]++; fpos[h] = 0; }
}
int16_t fgetc_(uint8_t h)
{
    if (feof_[h]) return -1;
    if (fpos[h] == 128) {
        if (rread(files[h], frec[h], fbuf[h])) { feof_[h] = 1; return -1; }
        frec[h]++; fpos[h] = 0;
    }
    if (fbuf[h][fpos[h]] == 0x1A) { feof_[h] = 1; return -1; }
    return fbuf[h][fpos[h]++];
}
void fpeekeof(uint8_t h) { int16_t c = fgetc_(h); if (c >= 0) fpos[h]--; }
void closef(uint8_t h)
{
    if (!files[h]) return;
    if (fmode[h] && fpos[h]) { uint8_t p = fpos[h]; fflush_(h); (void)p; }
    fclose(files[h]);
    zfree(files[h]); zfree(fbuf[h]);
    files[h] = 0;
}
void openf(void)
{
    value v;
    uint8_t mode, h, *e;
    strexpr(&v);
    if (accept(K_FOR)) {
        if (accept(K_INPUT)) mode = 0;
        else if (accept(K_OUTPUT)) mode = 1;
        else if (accept(K_APPEND)) mode = 2;
        else error(32);
    } else mode = 0;
    skip(K_AS);
    accept('#');
    h = intexpr();
    if (!h || h > 4) error(33);
    h--;
    closef(h);
    {
        char nm[16];
        uint8_t k = v.l < 15 ? v.l : 15, i;
        for (i = 0; i < k; i++) nm[i] = up(v.p[i]);
        nm[k] = 0;
        sfree_(&v);
        files[h] = xalloc(sizeof(FCB));
        fbuf[h] = xalloc(128);
        if (!mkfcb(files[h], nm)) { zfree(files[h]); files[h] = 0; error(34); }
        fmode[h] = mode; feof_[h] = 0; frec[h] = 0; fpos[h] = mode ? 0 : 128;
        if (mode == 1) { if (fmake(files[h])) { zfree(files[h]); files[h] = 0; error(35); } }
        else if (fopen(files[h])) {
            if (mode == 2) { if (fmake(files[h])) { zfree(files[h]); files[h] = 0; error(35); } }
            else { zfree(files[h]); files[h] = 0; error(36); }
        } else if (mode == 2) {               /* al final: el ultimo registro, hasta el ^Z */
            uint16_t n = fsize(files[h]);
            if (n) {
                frec[h] = n - 1;
                rread(files[h], frec[h], fbuf[h]);
                for (e = fbuf[h]; e < fbuf[h] + 128 && *e != 0x1A; e++) ;
                fpos[h] = e - fbuf[h];
                if (fpos[h] == 128) { frec[h]++; fpos[h] = 0; }
            }
        }
    }
}
/* un campo de INPUT #: hasta una coma o el fin de la linea (con comillas, tal cual) */
uint8_t field(uint8_t h, char *o, uint8_t max, uint8_t wholeline)
{
    int16_t c;
    uint8_t n = 0, q = 0;
    while ((c = fgetc_(h)) == ' ' && !wholeline) ;
    if (c < 0) return 0;
    if (c == '"' && !wholeline) { q = 1; c = fgetc_(h); }
    while (c >= 0) {
        if (q && c == '"') { q = 0; c = fgetc_(h); continue; }
        if (!q && ((c == ',' && !wholeline) || c == 13 || c == 10)) break;
        if (n < max) o[n++] = c;
        c = fgetc_(h);
    }
    if (c == 13) { c = fgetc_(h); if (c != 10 && c >= 0) fpos[h]--; }
    while (n && o[n - 1] == ' ' && !wholeline) n--;
    o[n] = 0;
    fpeekeof(h);
    return 1;
}

/* ---------------------------------------------------------------- INPUT y READ */
/* pone el texto s en el lugar: numero o texto. 1 si no es un numero */
uint8_t settext(uint8_t *e, slot *s, uint8_t isstr, const char *t, uint8_t n)
{
    value v;
    if (isstr) { newstr(&v, (const uint8_t *)t, n); assignto(e, s, 1, &v); return 0; }
    {
        uint8_t neg = 0;
        const char *q = t;
        while (*q == ' ') q++;
        if (*q == '-' || *q == '+') { neg = *q == '-'; q++; }
        if (!(isdg(*q) || (*q == '.' && isdg(q[1])))) return 1;
        nerr = 0;
        q = pnum(q, &v.n);
        while (*q == ' ') q++;
        if (nerr || *q) return 1;
        if (neg) v.n.m = -v.n.m;
        v.s = 0;
        assignto(e, s, 0, &v);
    }
    return 0;
}
void input(uint8_t whole)
{
    uint8_t isstr, *e, h = 0, k, n, i;
    slot *s;
    char *q;
    uint8_t *tp0;
    if (*tp == '#') { h = chan(); skip(','); }
    if (!h && *tp == T_STR) {                 /* el mensaje */
        outs(tp + 2, tp[1]);
        tp += tsize(tp);
        if (accept(';')) { if (!whole) cons("? "); }   /* ; pregunta, , no */
        else if (!accept(',')) error(5);
    } else if (!h && !whole) cons("? ");
    tp0 = tp;
    if (h) {                                  /* de un archivo */
        do {
            e = lvalue(&isstr, &s);
            if (!field(h - 1, lb, 250, whole)) error(37);
            if (settext(e, s, isstr, lb, strlen(lb))) error(38);
        } while (accept(','));
        return;
    }
    for (;;) {                                /* de la consola: todo en una linea */
        if (!getline_(0)) error(39);
        q = lb;
        tp = tp0;
        k = 0;
        do {
            e = lvalue(&isstr, &s);
            if (whole) { if (settext(e, s, 1, lb, strlen(lb))) k = 1; break; }
            while (*q == ' ') q++;
            for (n = 0; q[n] && q[n] != ','; n++) ;
            if (isstr && *q == '"') { q++; for (n = 0; q[n] && q[n] != '"'; n++) ; }
            { char c = q[n]; q[n] = 0; if (settext(e, s, isstr, q, n)) k = 1; q[n] = c; }
            q += n;
            if (*q == '"') q++;
            if (*q == ',') q++;
            if (k) break;
        } while (accept(','));
        if (!k) break;
        cons("?Redo from start\n");
        if (!h && !whole) cons("? ");
    }
}
void readdata(void)
{
    uint8_t isstr, *e, n;
    slot *s;
    char b[100];
    do {
        e = lvalue(&isstr, &s);
        while (!datap || !*datap) {             /* la DATA siguiente */
            uint8_t *l = dnext ? dnext : prog;
            if (dnext == pend || prog == pend) l = 0;
            for (; l; l = nextline(l)) {
                uint8_t *p = LTOK(l);
                for (; *p != T_END; p += tsize(p)) if (*p == K_DATA) break;
                if (*p == K_DATA) { datap = p + 2; dnext = nextline(l); if (!dnext) dnext = pend; break; }
            }
            if (!l) error(40);
        }
        while (*datap == ' ') datap++;
        n = 0;
        if (*datap == '"') { datap++; while (*datap && *datap != '"' && n < 99) b[n++] = *datap++; if (*datap == '"') datap++; while (*datap && *datap != ',') datap++; }
        else { while (*datap && *datap != ',' && n < 99) b[n++] = *datap++; while (n && b[n - 1] == ' ') n--; }
        b[n] = 0;
        if (*datap == ',') datap++;
        if (settext(e, s, isstr, b, n)) error(38);
    } while (accept(','));
}

/* ---------------------------------------------------------------- correr */
uint8_t jumped, fret;
uint16_t ticks_;
void pushc(uint8_t k)
{
    if (csp == NCTL) error(41);
    cs[csp].k = k; cs[csp].line = cl; cs[csp].tp = tp;
    csp++;
}
void goline(uint8_t *l) { cl = l; tp = LTOK(l); jumped = 1; }
uint8_t *target(void)     /* el destino de GOTO, GOSUB, THEN, RESTORE */
{
    uint8_t *l;
    if (*tp == T_LNUM) {
        l = findline(tp[1] | tp[2] << 8, 1);
        tp += 3;
        if (!l) error(42);
        return l;
    }
    if (*tp == T_ID && symat(tp[1] | tp[2] << 8)[0] == S_LABEL) {
        l = var(tp[1] | tp[2] << 8)->u.f.l;
        tp += 3;
        if (!l) error(43);
        return l;
    }
    error(44);
    return 0;
}
/* guarda la variable i (que pasa a ser local) */
void save(uint16_t i)
{
    slot *s = var(i);
    if (svp == NSAV) error(45);
    sv[svp].i = i; sv[svp].s = *s;
    svp++;
    memset(s, 0, sizeof(slot));
}
void restore(uint8_t to)
{
    slot *s;
    while (svp > to) {
        svp--;
        s = var(sv[svp].i);
        if (symat(sv[svp].i)[0] == S_STR && s->u.s.p) zfree(s->u.s.p);
        *s = sv[svp].s;
    }
}
/* las variables de los parametros en la cabecera de la SUB o FUNCTION l, con args */
void bind(uint8_t *l, value *args, uint8_t n)
{
    uint8_t *p = LTOK(l) + 4, k = 0, isstr;   /* SUB nombre */
    if (*p == '(') {
        p++;
        while (*p == T_ID) {
            uint16_t ix = p[1] | p[2] << 8;
            isstr = symat(ix)[0] == S_STR;
            if (k >= n) error(17);
            save(ix);
            if (args[k].s != isstr) error(12);
            store(var(ix), isstr, &args[k]);
            k++;
            p += 3;
            if (*p == ',') p++;
        }
    }
    if (k != n) error(17);
}
uint8_t getargs(value *a)  /* ( expr, ... ) en tp */
{
    uint8_t n = 0;
    if (*tp == '(') {
        tp++;
        if (*tp != ')') do { if (n == 8) error(16); expr(&a[n++]); } while (accept(','));
        skip(')');
    }
    return n;
}
void runloop(uint8_t level);
void callfn(uint16_t ix, value *v)
{
    value a[8];
    uint8_t n;
    slot *f = var(ix);
    if (!f->u.f.l) error(46);
    n = getargs(a);
    pushc(C_FUNC);
    cs[csp - 1].v = svp;
    bind(f->u.f.l, a, n);
    save(f->u.f.r);
    cs[csp - 1].lim.m = f->u.f.r;
    retset = 0;
    goline(nextline(f->u.f.l));
    jumped = 0;
    runloop(csp);
    jumped = 0;
    *v = retv;
    retv.p = 0;
    retset = 0;                          /* la que llamo todavia no termino */
    if ((symat(ix)[0] == S_SFUNC) != v->s) error(12);
}
void callsub(uint16_t ix)
{
    value a[8];
    uint8_t n;
    slot *f = var(ix);
    if (symat(ix)[0] != S_SUB || !f->u.f.l) error(47);
    n = getargs(a);
    pushc(C_CALL);
    cs[csp - 1].v = svp;
    bind(f->u.f.l, a, n);
    goline(nextline(f->u.f.l));
}
/* fin de una SUB o FUNCTION (END, EXIT o RETURN) */
void endproc(void)
{
    ctl *c;
    while (csp && cs[csp - 1].k != C_CALL && cs[csp - 1].k != C_FUNC) csp--;
    if (!csp) error(48);
    c = &cs[csp - 1];
    if (c->k == C_FUNC && !retset) {          /* el resultado: la variable con su nombre */
        slot *s = var(c->lim.m);
        if (symat(c->lim.m)[0] == S_STR) { newstr(&retv, s->u.s.p, s->u.s.l); }
        else { retv.s = 0; retv.n = s->u.n; }
        retset = 1;
    }
    restore(c->v);
    cl = c->line; tp = c->tp;
    jumped = 1;
    if (c->k == C_FUNC) fret = 1;
    csp--;
}
uint8_t casematch(value *v)       /* la lista de un CASE en tp */
{
    value a, b;
    uint8_t op, m = 0;
    int8_t c;
    do {
        op = '=';
        if (accept(K_IS)) { op = *tp++; }
        expr(&a);
        if (a.s != v->s) error(12);
        c = v->s ? scmp(v, &a) : ncmp(&v->n, &a.n);
        if (accept(K_TO)) {
            expr(&b);
            if (b.s != v->s) error(12);
            if (c >= 0 && (v->s ? scmp(v, &b) : ncmp(&v->n, &b.n)) <= 0) m = 1;
            sfree_(&b);
        } else switch (op) {
            case '=': if (!c) m = 1; break;
            case '<': if (c < 0) m = 1; break;
            case '>': if (c > 0) m = 1; break;
            case K_LE: if (c <= 0) m = 1; break;
            case K_GE: if (c >= 0) m = 1; break;
            case K_NE: if (c) m = 1; break;
        }
        sfree_(&a);
    } while (accept(','));
    return m;
}
void afterw(void) { jumpw(); tp++; skipstmt(); jumped = 1; }   /* sigue despues de la sentencia (wl, wp) */
void doif(void)
{
    value v;
    uint8_t k;
    expr(&v);
    if (v.s) error(12);
    if (accept(K_GOTO)) { if (truth(&v.n)) goline(target()); else { tp += 3; while (*tp != T_END && *tp != K_ELSE) tp += tsize(tp); if (*tp == K_ELSE) tp++; } return; }
    skip(K_THEN);
    if (*tp == T_END || *tp == T_RAW) {      /* de bloque */
        if (truth(&v.n)) return;
        for (;;) {
            k = findendc(K_IF, 1);
            jumpw();
            if (k == K_ELSE) { tp++; return; }
            if (k == K_END) { tp += 2; return; }
            tp++;                                 /* ELSEIF: su condicion */
            expr(&v);
            if (v.s) error(12);
            skip(K_THEN);
            if (truth(&v.n)) return;
        }
    }
    jumped = 1;                                   /* de una linea: sigue en tp */
    if (truth(&v.n)) { if (*tp == T_LNUM) goline(target()); return; }
    while (*tp != T_END && *tp != K_ELSE) tp += tsize(tp);   /* lo que sigue a ELSE */
    if (*tp == K_ELSE) { tp++; if (*tp == T_LNUM) goline(target()); }
}
void dofor(void)
{
    uint8_t isstr, *e;
    slot *s;
    uint16_t ix;
    num lim, step, st;
    uint8_t i;
    if (*tp != T_ID) error(5);
    ix = tp[1] | tp[2] << 8;
    e = lvalue(&isstr, &s);
    if (!s || isstr) error(12);
    skip('=');
    numexpr(&st);
    skip(K_TO);
    numexpr(&lim);
    nset(&step, 1);
    if (accept(K_STEP)) numexpr(&step);
    s->u.n = st;
    for (i = csp; i; i--) if (cs[i - 1].k == C_FOR && cs[i - 1].v == ix) { csp = i - 1; break; }
    if (step.m >= 0 ? ncmp(&st, &lim) > 0 : ncmp(&st, &lim) < 0) {   /* ni una vez */
        findendc(K_FOR, 0);
        afterw();
        return;
    }
    pushc(C_FOR);
    cs[csp - 1].v = ix; cs[csp - 1].lim = lim; cs[csp - 1].step = step;
    (void)e;
}
void donext(void)
{
    ctl *c;
    slot *s;
    for (;;) {
        uint16_t ix = 0xFFFF;
        if (*tp == T_ID) { ix = tp[1] | tp[2] << 8; tp += 3; }
        while (csp && (cs[csp - 1].k != C_FOR || (ix != 0xFFFF && cs[csp - 1].v != ix))) {
            if (cs[csp - 1].k != C_FOR && cs[csp - 1].k != C_WHILE && cs[csp - 1].k != C_DO) error(49);
            csp--;
        }
        if (!csp) error(49);
        c = &cs[csp - 1];
        s = var(c->v);
        nerr = 0;
        nadd(&s->u.n, &s->u.n, &c->step);
        if (c->step.m >= 0 ? ncmp(&s->u.n, &c->lim) <= 0 : ncmp(&s->u.n, &c->lim) >= 0) {
            cl = c->line; tp = c->tp;             /* otra vuelta */
            return;
        }
        csp--;
        if (!accept(',')) return;
    }
}
uint8_t docond(void)      /* WHILE c / UNTIL c despues de DO o LOOP: 1 si sigue */
{
    value v;
    uint8_t u;
    if (*tp != K_WHILE && *tp != K_UNTIL) return 1;
    u = *tp++ == K_UNTIL;
    expr(&v);
    if (v.s) error(12);
    return truth(&v.n) != u;
}
void stmt_(void);
void dosub_or_let(void)
{
    uint16_t ix = tp[1] | tp[2] << 8;
    uint8_t k = symat(ix)[0];
    if (k == S_SUB) { tp += 3; callsub(ix); return; }
    if (tp[3] == '=' || ((k == S_NARR || k == S_SARR) && tp[3] == '(')) {
        if (k == S_NARR || k == S_SARR) {         /* a(...) = : se ve si viene un = */
            uint8_t *p = tp + 3; uint8_t d = 0;
            do { if (*p == '(') d++; else if (*p == ')') d--; p += tsize(p); } while (d && *p != T_END);
            if (*p != '=') { tp += 3; callsub(ix); return; }
        }
        let();
        return;
    }
    {   /* una SUB sin parentesis: la que tiene ese nombre */
        uint8_t *q = symat(ix), *p = names;
        uint16_t i = 0;
        for (; p < nend; p += 2 + p[1], i++)
            if (p[0] == S_SUB && p[1] == q[1] && !memcmp(p + 2, q + 2, q[1])) {
                value a[8]; uint8_t n = 0;
                tp += 3;
                if (*tp != T_END && *tp != ':') do { if (n == 8) error(16); expr(&a[n++]); } while (accept(','));
                {
                    slot *f = var(i);
                    if (!f->u.f.l) error(47);
                    pushc(C_CALL);
                    cs[csp - 1].v = svp;
                    bind(f->u.f.l, a, n);
                    goline(nextline(f->u.f.l));
                }
                return;
            }
    }
    error(5);
}

char fnb[16];
void bfname(value *v, const char *ext)
{
    uint8_t k = v->l < 12 ? v->l : 12, i;
    for (i = 0; i < k; i++) fnb[i] = up(v->p[i]);
    fnb[k] = 0;
    sfree_(v);
    if (!strchr(fnb, '.')) strcat(fnb, ext);
}
/* ---------------------------------------------------------------- una sentencia */
uint16_t linenum(void)    /* un numero de linea (sin hacer cuentas: LIST 10-20) */
{
    num n;
    if (*tp == T_LNUM) { tp += 3; return tp[-2] | tp[-1] << 8; }
    memcpy(&n, tp + 1, 5); tp += 6;
    return ntoi(&n);
}
void stmt_(void)
{
    uint8_t k = *tp;
    value v;
    if (k == T_ID && tp[3] == ':' && symat(tp[1] | tp[2] << 8)[0] == S_LABEL) { tp += 4; k = *tp; }
    if (k == T_END || k == ':') return;
    if (k == T_RAW) { tp += tsize(tp); return; }
    if (k == T_ID) { dosub_or_let(); return; }
    if (k < 0x80) error(5);
    tp++;
    switch (k) {
    case K_LET: let(); break;
    case K_PRINT: print(); break;
    case K_INPUT: input(0); break;
    case K_LINE: skip(K_INPUT); input(1); break;
    case K_IF: doif(); break;
    case K_ELSE: case K_ELSEIF:                   /* se termino la rama: a END IF */
        findendc(K_IF, 0); jumpw(); tp += 2; jumped = 1;
        break;
    case K_END:
        if (*tp == K_IF || *tp == K_SELECT) { tp++; break; }
        if (*tp == K_SUB || *tp == K_FUNCTION) { tp++; endproc(); break; }
        running = 0; contline = 0;
        break;
    case K_STOP:
        contline = cl; conttp = tp;
        running = 0;
        cons("Break"); if (cl != direct) { cons(" in "); { char b[6]; b[utoa_(LNUM(cl), b)] = 0; cons(b); } } cons("\n");
        break;
    case K_FOR: dofor(); break;
    case K_NEXT: donext(); break;
    case K_WHILE: {
        uint8_t *st = tp - 1;
        expr(&v);
        if (v.s) error(12);
        if (truth(&v.n)) { pushc(C_WHILE); cs[csp - 1].tp = st; }
        else { findendc(K_WHILE, 0); afterw(); }
        break;
    }
    case K_WEND:
        if (!csp || cs[csp - 1].k != C_WHILE) error(51);
        csp--;
        cl = cs[csp].line; tp = cs[csp].tp; jumped = 1;
        break;
    case K_DO: {
        uint8_t *st = tp - 1;
        if (!docond()) { findendc(K_DO, 0); afterw(); break; }
        pushc(C_DO); cs[csp - 1].tp = st;
        break;
    }
    case K_LOOP:
        if (!csp || cs[csp - 1].k != C_DO) error(52);
        csp--;
        if (docond()) { cl = cs[csp].line; tp = cs[csp].tp; jumped = 1; }
        break;
    case K_EXIT:
        k = *tp++;
        if (k == K_SUB || k == K_FUNCTION) { endproc(); break; }
        if (k != K_FOR && k != K_DO && k != K_WHILE) error(5);
        {
            uint8_t want = k == K_FOR ? C_FOR : k == K_DO ? C_DO : C_WHILE;
            while (csp && cs[csp - 1].k != want) {
                if (cs[csp - 1].k == C_CALL || cs[csp - 1].k == C_FUNC || cs[csp - 1].k == C_GOSUB) error(53);
                csp--;
            }
            if (!csp) error(53);
            csp--;
            findendc(k, 0);
            afterw();
        }
        break;
    case K_SELECT: {
        uint8_t m;
        skip(K_CASE);
        expr(&v);
        for (;;) {
            k = findendc(K_SELECT, 1);
            jumpw();
            tp++;
            if (k == K_END) { tp++; break; }
            if (accept(K_ELSE)) break;
            m = casematch(&v);
            if (m) break;
        }
        sfree_(&v);
        jumped = 1;
        if (*tp == ':') tp++;
        break;
    }
    case K_CASE:                                  /* se termino la rama: a END SELECT */
        findendc(K_SELECT, 0); jumpw(); tp += 2; jumped = 1;
        break;
    case K_GOTO: goline(target()); break;
    case K_GOSUB: { uint8_t *l = target(); pushc(C_GOSUB); goline(l); break; }
    case K_RETURN:
        if (*tp != T_END && *tp != ':' && *tp != K_ELSE) {   /* RETURN valor: de una FUNCTION */
            uint8_t i;
            for (i = csp; i && cs[i - 1].k != C_FUNC; i--) ;
            if (!i) error(54);
            value r;
            expr(&r);                    /* (la expresion puede llamar a otras FUNCTION) */
            retv = r; retset = 1;
            endproc();
            break;
        }
        while (csp && cs[csp - 1].k != C_GOSUB) {
            if (cs[csp - 1].k == C_CALL || cs[csp - 1].k == C_FUNC) error(54);
            csp--;
        }
        if (!csp) error(54);
        csp--;
        cl = cs[csp].line; tp = cs[csp].tp;
        break;
    case K_ON: {
        int16_t n;
        uint8_t g;
        n = intexpr();
        g = *tp++;
        if (g != K_GOTO && g != K_GOSUB) error(5);
        while (--n > 0) { tp += 3; if (!accept(',')) { n = -1; break; } }
        if (n < 0) { while (*tp != T_END && *tp != ':') tp += tsize(tp); break; }
        {
            uint8_t *l = target();
            while (accept(',')) tp += 3;
            if (g == K_GOSUB) pushc(C_GOSUB);
            goline(l);
        }
        break;
    }
    case K_SUB: case K_FUNCTION:                  /* se llega sin llamarla: se salta */
        findendc(K_SUB, 0); afterw();
        break;
    case K_CALL: {
        uint16_t ix;
        if (*tp != T_ID) error(5);
        ix = tp[1] | tp[2] << 8; tp += 3;
        callsub(ix);
        break;
    }
    case K_LOCAL:
        do {
            if (*tp != T_ID) error(5);
            if (!csp) error(55);
            save(tp[1] | tp[2] << 8);
            tp += 3;
        } while (accept(','));
        break;
    case K_DIM:
        do {
            uint16_t ix, d[3];
            uint8_t nd = 0, kk;
            if (*tp != T_ID) error(5);
            ix = tp[1] | tp[2] << 8; tp += 3;
            kk = symat(ix)[0];
            if (kk != S_NARR && kk != S_SARR) error(5);
            skip('(');
            do { if (nd == 3) error(10); d[nd++] = intexpr(); } while (accept(','));
            skip(')');
            arrsize(ix, d, nd, kk == S_SARR);
        } while (accept(','));
        break;
    case K_ERASE:
        do {
            slot *s;
            if (*tp != T_ID) error(5);
            s = var(tp[1] | tp[2] << 8);
            if (s->u.a.a) {
                if (s->t == S_SARR) {
                    arrhdr *h = s->u.a.a; uint16_t n = 1, i; uint8_t j;
                    for (j = 0; j < h->nd; j++) n *= h->d[j] + 1;
                    for (i = 0; i < n; i++) zfree(*(uint8_t **)((uint8_t *)(h + 1) + i * 4));
                }
                zfree(s->u.a.a); s->u.a.a = 0;
            }
            tp += 3;
        } while (accept(','));
        break;
    case K_DATA: tp += tsize(tp); break;
    case K_READ: readdata(); break;
    case K_RESTORE:
        datap = 0; dnext = 0;
        if (*tp == T_LNUM || *tp == T_ID) dnext = target();
        break;
    case K_CLS: cons(ESC "[2J" ESC "[H"); col = 0; break;
    case K_LOCATE: {
        int16_t r, c;
        char b[12], *o = b;
        r = intexpr(); skip(','); c = intexpr();
        *o++ = 27; *o++ = '['; o += utoa_(r, o); *o++ = ';'; o += utoa_(c, o); *o++ = 'H'; *o = 0;
        cons(b); col = c - 1;
        break;
    }
    case K_COLOR: {
        int16_t f, bg = -1;
        char b[16], *o = b;
        f = intexpr();
        if (accept(',')) bg = intexpr();
        *o++ = 27; *o++ = '['; *o++ = '0'; *o++ = ';';
        o += utoa_(f < 8 ? 30 + f : 82 + f, o);
        if (bg >= 0) { *o++ = ';'; o += utoa_(bg < 8 ? 40 + bg : 92 + bg, o); }
        *o++ = 'm'; *o = 0;
        for (o = b; *o; o++) putch(*o);
        break;
    }
    case K_RANDOMIZE: srnd(*tp != T_END && *tp != ':' ? intexpr() : ticks()); break;
    case K_SLEEP: {
        int16_t n = intexpr();
        oflush();
        if (ismpm()) delay(n * tps());
        else { uint16_t i, j; for (i = 0; i < n; i++) for (j = 0; j < 30000; j++) ; }
        break;
    }
    case K_BEEP: putch(7); break;
    case K_SWAP: {
        uint8_t i1, i2, *e1, *e2, t[5];
        slot *s1, *s2;
        e1 = lvalue(&i1, &s1); skip(','); e2 = lvalue(&i2, &s2);
        if (i1 != i2) error(12);
        if (s1) e1 = (uint8_t *)&s1->u;
        if (s2) e2 = (uint8_t *)&s2->u;
        memcpy(t, e1, i1 ? 4 : 5); memcpy(e1, e2, i1 ? 4 : 5); memcpy(e2, t, i1 ? 4 : 5);
        break;
    }
    case K_OPEN: openf(); break;
    case K_CLOSE:
        if (*tp == T_END || *tp == ':') { uint8_t i; for (i = 0; i < 4; i++) closef(i); break; }
        do { uint8_t h; accept('#'); h = intexpr(); if (h && h <= 4) closef(h - 1); } while (accept(','));
        break;
    case K_KILL: {
        FCB f;
        strexpr(&v); bfname(&v, "");
        if (!mkfcb(&f, fnb) || fdelete(&f)) error(36);
        break;
    }
    case K_TRON: tron = 1; break;
    case K_TROFF: tron = 0; break;
    case K_REM: tp += tsize(tp); break;
    /* las del interprete */
    /* las del interprete (en ZBAS.OVL) */
    case K_RUN:
        if (*tp == T_STR) { strexpr(&v); bfname(&v, ".BAS"); ovl(OV_LOAD); }
        ovl(OV_RUN);
        jumped = 1;
        break;
    case K_LIST: case K_DELETE:          /* [n][-[m]] */
        ovn1 = 0; ovn2 = 65535;
        if (*tp == T_LNUM || *tp == T_NUM) ovn1 = ovn2 = linenum();
        if (accept('-')) { ovn2 = 65535; if (*tp == T_LNUM || *tp == T_NUM) ovn2 = linenum(); }
        ovl(k == K_LIST ? OV_LIST : OV_DELETE);
        break;
    case K_NEW: newprog(); break;
    case K_LOAD: case K_SAVE:
        strexpr(&v); bfname(&v, ".BAS");
        ovl(k == K_LOAD ? OV_LOAD : OV_SAVE);
        break;
    case K_FILES: ovl(OV_FILES); break;
    case K_RENUM:
        ovn1 = 10; ovn2 = 10;
        if (*tp == T_NUM) { ovn1 = intexpr(); if (accept(',')) ovn2 = intexpr(); }
        ovl(OV_RENUM);
        break;
    case K_SYSTEM: cons(SHOW); exit(); break;
    case K_CONT:
        if (!contline) error(56);
        cl = contline; tp = conttp; running = 1; jumped = 1; contline = 0;
        break;
    case K_EDIT: case K_AUTO: break;        /* (las ve el bucle principal) */
    default: error(5);
    }
}
void advance(void)
{
    if (*tp == ':') { tp++; return; }
    if (*tp == K_ELSE) while (*tp != T_END) tp += tsize(tp);   /* de un IF de una linea */
    if (*tp == T_RAW) tp += tsize(tp);
    if (*tp != T_END) error(5);
    cl = nextline(cl);
    if (!cl) { running = 0; return; }
    tp = LTOK(cl);
}
void runloop(uint8_t level)
{
    while (running) {
        if (!(++ticks_ & 63) && brkchk()) error(39);
        if (tron && cl != direct && tp == LTOK(cl)) { char b[8]; b[0] = '['; b[1 + utoa_(LNUM(cl), b + 1)] = 0; cons(b); cons("]"); }
        errline = cl == direct ? 0 : LNUM(cl);
        stmt_();
        if (jumped) jumped = 0; else advance();
        if (fret) { if (csp < level) { fret = 0; return; } fret = 0; }
    }
    if (level) error(57);
}

/* ---------------------------------------------------------------- las partes cargadas */
/* ZBAS.OVL: el registro 0 dice "ZBOVL", la marca de esta version (ovlmark) y de cada
   parte el primer registro, cuantos registros tiene y cuantas direcciones hay que
   corregir; despues de cada parte (enlazada para C000h) va la lista de esas
   direcciones (2 bytes cada una) */
uint8_t ovop, ovret, ovk, autoon, resolved;
uint16_t ovn1, ovn2;
uint8_t *ovb;
uint16_t autonum, autoinc;
char *argf;
FCB ovf;
uint8_t ovdrv, ovcur;
uint16_t ovh[9];                 /* de cada parte: primer registro, registros, direcciones */
extern const uint8_t ovlmark[4];       /* en znum_a.s */
uint8_t ovlopen(uint8_t d)
{
    uint8_t *h = (uint8_t *)lb;
    mkfcb(&ovf, "ZBAS.OVL");
    ovf.dr = d;
    if (fopen(&ovf)) return 1;
    if (rread(&ovf, 0, h) || memcmp(h, "ZBOVL", 5) || memcmp(h + 5, ovlmark, 4)) { fclose(&ovf); return 1; }
    fclose(&ovf);
    ovdrv = d;
    memcpy(ovh, h + 9, sizeof ovh);
    return 0;
}
/* busca ZBAS.OVL: en la unidad de donde se cargo ZBAS (CP/M 3 la deja en 0050h),
   en la actual y en A: */
uint8_t ovlfind(void)
{
    uint8_t d = (bdos(12, 0) & 0xFF) == 0x31 ? *(uint8_t *)0x50 : 0;
    return !((d && d <= 16 && !ovlopen(d)) || !ovlopen(0) || !ovlopen(1));
}
/* carga la parte p arriba del heap si alli hay lugar libre: 0 bien, 1 sin lugar, 2 no se lee */
uint8_t ovlload(uint8_t p)
{
    static fb *b;
    static uint8_t *base, *rl, d;
    static uint16_t i, r0, nir, nrel, nrr;
    r0 = ovh[3 * p - 3]; nir = ovh[3 * p - 2]; nrel = ovh[3 * p - 1];
    for (b = freel; b && b->nx; b = b->nx) ;
    if (!b || (uint8_t *)b + b->sz != htop) return 1;
    nrr = (nrel * 2 + 127) >> 7;
    if ((uint16_t)htop - (uint16_t)b < (nir + nrr) * 128 + 256 + 8) return 1;
    base = (uint8_t *)(((uint16_t)htop - nir * 128) & 0xFF00);
    rl = base - nrr * 128;
    if (rl < (uint8_t *)b + 8) return 1;
    mkfcb(&ovf, "ZBAS.OVL");
    ovf.dr = ovdrv;
    if (fopen(&ovf)) return 2;
    for (i = 0; i < nir; i++) if (rread(&ovf, r0 + i, base + i * 128)) goto bad;
    for (i = 0; i < nrr; i++) if (rread(&ovf, r0 + nir + i, rl + i * 128)) goto bad;
    fclose(&ovf);
    d = ((uint16_t)base >> 8) - 0xC0;
    for (i = 0; i < nrel; i++) base[((uint16_t *)rl)[i]] += d;
    b->sz = base - (uint8_t *)b;
    hfree -= htop - base;
    ovb = base; htop = base; ovcur = p;
    return 0;
bad:
    fclose(&ovf);
    return 2;
}
void ovl(uint8_t op)
{
    static uint8_t r, p;
    p = op <= OV_DELETE ? 1 : op <= OV_EDIT ? 2 : 3;
    if (ovcur != p) {
        ovfree();
        r = ovlload(p);
        if (r == 1 && !running) { clearvars(); r = ovlload(p); }   /* sin las variables */
        if (r == 1 && running) error(1);
        if (r) { cons(r == 1 ? "\nNo room for ZBAS.OVL\n" : "\nCan't read ZBAS.OVL\n"); cons(SHOW); exit(); }
    }
    ovop = op; ovret = 0;
    inovl = 1;
    ((void (*)(void))ovb)();
    inovl = 0;
}

/* ---------------------------------------------------------------- el interprete */
void prompt_ok(void) { cons("Ok\n"); }
void main(void)
{
    static char *a;
    static uint8_t first;
    uint8_t k;
    memtop = (uint8_t *)(((uint16_t)&k - 1536) & ~1);
    prog = pend = names = nend = (uint8_t *)heap;
    nsym = 0;
    heapinit();
    if (ovlfind()) { cons("ZBAS.OVL not found (it goes with ZBAS.COM)\n"); exit(); }
    a = args();
    argf = nextarg(&a);
    first = 1;
    if (setjmp(errjb)) {
        inovl = 0;
        if (outf) outf = 0;
        if (col) cons("\n");
        if (running) {                   /* ^C: CONT sigue desde ahi */
            if (errn == 39 && cl != direct) { contline = cl; conttp = tp; } else contline = 0;
        }
        ovk = running || first;
        running = 0; csp = 0; svp = 0; fret = 0; jumped = 0;
        autoon = 0;
        ovl(OV_ERR);
        if (first && argf && *argf) { cons(SHOW); exit(); }
        first = 0;
        prompt_ok();
    }
    if (first) {
        if (argf && *argf) {             /* ZBAS PROGRAMA: cargarlo, correrlo y salir */
            value v;
            newstr(&v, (uint8_t *)argf, strlen(argf));
            bfname(&v, ".BAS");
            ovl(OV_LOAD);
            ovl(OV_RUN);
            runloop(0);
            for (k = 0; k < 4; k++) closef(k);
            oflush();
            exit();
        }
        first = 0;
        cons("ZBAS " VERSION " - structured BASIC   (C) OLIVEROS 2026\n");
        { char b[8]; b[utoa_(hfree, b)] = 0; cons(b); }
        cons(" bytes free. HELP is in LEEME.md; SYSTEM goes back to CP/M.\n");
        prompt_ok();
    }
    for (;;) {
        ovl(OV_LINE);
        if (ovret == 2) { ovl(OV_EDIT); if (ovret) ovl(OV_NUMLINE); continue; }
        if (!ovret) continue;
        cl = direct; tp = LTOK(direct);
        running = 1; jumped = 0;
        runloop(0);
        if (col) cons("\n");
        prompt_ok();
    }
}
