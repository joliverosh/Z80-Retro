/* ZAS - ensamblador Z80 con mnemonicos de Zilog, para CP/M y MP/M II
   ZAS archivo[.Z80] [-L] [-H]
     -L  listado en archivo.PRN       -H  tambien archivo.HEX (Intel)
   Sin extension busca .Z80 y luego .ASM. Sale archivo.COM: los bytes desde
   el primer ORG (100h si no hay) hasta el ultimo.

   Lo que entiende:
   - etiquetas en la columna 1 (con o sin ':') o con ':' en cualquier lugar;
     nombres de hasta 31 caracteres, sin distinguir mayusculas
   - todas las instrucciones del Z80, tambien IX/IY, (IX+d), IXH/IXL/IYH/IYL,
     SLL e IN F,(C) / OUT (C),0
   - ORG, EQU, DEFL o '=', DB/DEFB/DEFM/DM, DW/DEFW, DS/DEFS (con relleno),
     END, IF/ELSE/ENDIF (anidados), INCLUDE (hasta 3 niveles), y se saltan
     TITLE, PAGE, .Z80, NAME, LIST
   - numeros: 123, 0FFH, 1010B, 17O/Q, $FF, 0xFF, %1010, 'A'; $ = direccion
   - operadores: + - * / % (MOD) & | ^ ~ << >> (SHL, SHR), HIGH, LOW, ( ) */
#include <string.h>
#include "cpm.h"
extern char heap[];

#define MAXL 160
#define NAMEL 31

static char src[MAXL + 2], up_[MAXL + 2];
static char *cp;                       /* donde se analiza (en up_) */
static uint8_t pass, err1, nerr, lst, hexo;
static uint16_t pc, spc, lineno, nerrs, nlines;   /* spc: $, el pc al empezar la linea */
static uint16_t start, outaddr, origin;
static uint8_t started, anyout;     /* anyout: ya hubo codigo en esta pasada */
static uint8_t undef;                  /* la expresion uso un simbolo sin definir */

/* ------------------------------------------------------------ errores */
static const char *curname(void);
static void error(const char *m)
{
    if (err1) return;                  /* uno por linea */
    err1 = 1;
    if (pass == 2 || nerr) {
        nerrs++;
        pf("%s %u: %s\n  %s\n", curname(), lineno, m, src);
    }
}

/* ------------------------------------------------------------ simbolos */
/* en el heap: [sig 2][valor 2][marcas 1][largo 1][nombre] */
#define S_DEF  1
#define S_SET  2
static uint16_t hasht[128];
static uint8_t *hp, *htop;
static uint16_t nsym;

static uint8_t hashf(const char *s, uint8_t n)
{
    uint8_t h = 0;
    while (n--) h = (uint8_t)(h * 31 + *s++);
    return h & 127;
}
static uint8_t *sfind(const char *s, uint8_t n)
{
    uint16_t e = hasht[hashf(s, n)];
    while (e) {
        uint8_t *p = (uint8_t *)e;
        if (p[5] == n && !memcmp(p + 6, s, n)) return p;
        e = *(uint16_t *)p;
    }
    return 0;
}
static uint8_t *sadd(const char *s, uint8_t n)
{
    uint8_t h = hashf(s, n), *p = hp;
    if (hp + 6 + n >= htop) { pstr("Symbol table full\n"); exit(); }
    *(uint16_t *)p = hasht[h];
    hasht[h] = (uint16_t)p;
    *(uint16_t *)(p + 2) = 0;
    p[4] = 0; p[5] = n;
    memcpy(p + 6, s, n);
    hp += 6 + n;
    nsym++;
    return p;
}
static void define(const char *s, uint8_t n, uint16_t v, uint8_t set)
{
    uint8_t *p = sfind(s, n);
    if (!p) p = sadd(s, n);
    else if (pass == 1 && (p[4] & S_DEF) && !(p[4] & S_SET) && !set) { nerr = 1; error("Duplicate symbol"); nerr = 0; }
    else if (pass == 2 && (p[4] & S_DEF) && !(p[4] & S_SET) && !set && *(uint16_t *)(p + 2) != v) error("Phase error (value changed between passes)");
    *(uint16_t *)(p + 2) = v;
    p[4] |= S_DEF | (set ? S_SET : 0);
}

/* ------------------------------------------------------------ lectura */
static RD rd[3];
static FCB fcbs[3];
static uint16_t lines_[3];
static uint8_t depth;
static char fnames[3][16];
static const char *curname(void) { return fnames[depth]; }

static uint8_t openin(const char *name, uint8_t d)
{
    FCB *f = &fcbs[d];
    if (!mkfcb(f, name)) return 1;
    if (ropen(&rd[d], f)) return 1;
    fname(&rd[d].f, fnames[d]);
    return 0;
}
/* una linea a src (sin CR/LF); 0 al final del archivo */
static RD *crd;                         /* el que se lee ahora */
/* scanl: copia del bufer de lectura (g_q hasta g_e) a src (g_d) y a up_ (g_u,
   en mayusculas salvo dentro de comillas; AF' no abre comilla). 0: fin de
   linea; 1: se acabo el bufer; 2: ^Z. En asm: en C eran 785 ciclos por byte. */
static uint8_t *g_q, *g_e;
static char *g_d, *g_u, *g_lim, g_qt, g_p1, g_p2;
static uint8_t scanl(void) __naked
{
    __asm
        ld      hl,(_g_q)
        ld      de,(_g_d)
sl_loop:
        ld      a,(_g_e)
        cp      l
        jr      nz,sl_1
        ld      a,(_g_e+1)
        cp      h
        jr      z,sl_empty
sl_1:   ld      a,(hl)
        inc     hl
        cp      #0x1A
        jr      z,sl_ctlz
        cp      #0x0A
        jr      z,sl_nl
        cp      #0x0D
        jp      z,sl_loop
        cp      #0x09
        jr      nz,sl_2
        ld      a,#0x20
sl_2:   ld      c,a
        ld      a,(_g_lim)
        cp      e
        jr      nz,sl_3
        ld      a,(_g_lim+1)
        cp      d
        jp      z,sl_loop
sl_3:   ld      a,c
        ld      (de),a
        inc     de
        push    hl
        ld      hl,(_g_u)
        ld      a,(_g_qt)
        or      a
        jr      z,sl_4
        cp      c
        jr      nz,sl_8
        xor     a
        ld      (_g_qt),a
        jr      sl_8
sl_4:   ld      a,c
        cp      #0x27
        jr      nz,sl_5
        ld      a,(_g_p1)
        or      #0x20
        cp      #0x66
        jr      nz,sl_41
        ld      a,(_g_p2)
        or      #0x20
        cp      #0x61
        jr      z,sl_8
sl_41:  ld      a,c
        ld      (_g_qt),a
        jr      sl_8
sl_5:   cp      #0x22
        jr      nz,sl_6
        ld      (_g_qt),a
        jr      sl_8
sl_6:   cp      #0x61
        jr      c,sl_8
        cp      #0x7B
        jr      nc,sl_8
        sub     #0x20
        ld      (hl),a
        jr      sl_9
sl_8:   ld      (hl),c
sl_9:   inc     hl
        ld      (_g_u),hl
        ld      a,(_g_p1)
        ld      (_g_p2),a
        ld      a,c
        ld      (_g_p1),a
        pop     hl
        jp      sl_loop
sl_empty:
        ld      a,#1
        jr      sl_out
sl_ctlz:
        ld      a,#2
        jr      sl_out
sl_nl:  xor     a
sl_out: ld      (_g_q),hl
        ld      (_g_d),de
        ret
    __endasm;
}
/* una linea a src (sin CR/LF, TAB = espacio) y a up_; 0 al final del archivo */
static uint8_t getline_(void)
{
    uint8_t r;
    g_d = src; g_u = up_; g_lim = src + MAXL; g_qt = 0; g_p1 = g_p2 = 0;
    for (;;) {
        g_q = crd->q; g_e = crd->e;
        r = scanl();
        crd->q = g_q;
        if (!r) break;
        if (r == 1) {                    /* otro KB */
            if (rgetc(crd) >= 0) { crd->q--; continue; }
        }
        /* fin del archivo o ^Z */
        if (g_d != src) { crd->eof = 1; crd->q = crd->e; break; }
        if (!depth) return 0;            /* (el principal lo cierra runpass) */
        fclose(&crd->f);
        depth--;
        crd = &rd[depth];
        lineno = lines_[depth];
    }
    *g_d = 0; *g_u = 0;
    lineno++;
    return 1;
}

/* ------------------------------------------------------------ salida */
static FCB ocom, oprn, ohex;
static uint8_t obuf[1024], lbuf[1024], hbuf[256];
static uint16_t on, ln_, hn;
static uint8_t oerr;
static void obyte(uint8_t b)
{
    obuf[on++] = b;
    if (on == 1024) { if (fwriten(&ocom, obuf, 8)) oerr = 1; on = 0; }
}
static void ofin(void)
{
    if (on) {
        uint16_t n = (on + 127) & ~127;
        memset(obuf + on, 0, n - on);
        if (fwriten(&ocom, obuf, n >> 7)) oerr = 1;
    }
    fclose(&ocom);
}
static void lout(FCB *f, uint8_t *b, uint16_t *n, uint16_t sz, char c)
{
    b[(*n)++] = c;
    if (*n == sz) { if (fwriten(f, b, sz >> 7)) oerr = 1; *n = 0; }
}
static void lstr(const char *s) { while (*s) { if (*s == '\n') lout(&oprn, lbuf, &ln_, 1024, '\r'); lout(&oprn, lbuf, &ln_, 1024, *s++); } }
static void lfin(FCB *f, uint8_t *b, uint16_t *n, uint16_t sz)
{
    (void)sz;
    do b[(*n)++] = 0x1A; while (*n & 127);
    if (fwriten(f, b, *n >> 7)) oerr = 1;
    fclose(f);
}
static const char hx[] = "0123456789ABCDEF";
static void hstr(const char *s) { while (*s) lout(&ohex, hbuf, &hn, 256, *s++); }
static void hbyte(uint8_t b, uint8_t *sum) { char t[3]; t[0] = hx[b >> 4]; t[1] = hx[b & 15]; t[2] = 0; hstr(t); *sum += b; }
static uint8_t hrec[16], hrn;
static uint16_t hra;
static void hflush(void)
{
    uint8_t s = 0, i;
    if (!hrn) return;
    hstr(":"); hbyte(hrn, &s); hbyte(hra >> 8, &s); hbyte(hra & 255, &s); hbyte(0, &s);
    for (i = 0; i < hrn; i++) hbyte(hrec[i], &s);
    hbyte((uint8_t)-s, &s); hstr("\r\n");
    hrn = 0;
}

/* listado: los bytes de la linea */
static uint8_t lb[4], lbn, lmore;
static uint16_t lpc;

static void emit(uint8_t b)
{
    if (pass == 2) {
        if (!started) { started = 1; start = outaddr = origin; }
        if (pc < outaddr) error("ORG goes back over code already written");
        else {
            while (outaddr < pc) { obyte(0); outaddr++; }
            obyte(b); outaddr++;
            if (hexo) {
                if (hrn == 16 || (hrn && hra + hrn != pc)) hflush();
                if (!hrn) hra = pc;
                hrec[hrn++] = b;
            }
        }
        if (lbn < 4) lb[lbn++] = b; else lmore = 1;
    }
    pc++;
    anyout = 1;
}
static void emitw(uint16_t w) { emit(w & 255); emit(w >> 8); }

/* ------------------------------------------------------------ expresiones */
static void skipsp(void) { while (*cp == ' ') cp++; }
static uint8_t isid(char c) { return (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '.' || c == '?' || c == '@' || c == '$'; }
static uint8_t isid0(char c) { return (c >= 'A' && c <= 'Z') || c == '_' || c == '.' || c == '?' || c == '@'; }
static uint8_t word(const char *w)    /* la palabra w (completa) en cp */
{
    uint8_t n;
    if (*cp != *w) return 0;
    n = strlen(w);
    if (memcmp(cp, w, n) || isid(cp[n])) return 0;
    cp += n;
    return 1;
}
static int16_t expr(void);
static uint16_t number(void)
{
    char *s = cp, *e;
    uint16_t v = 0;
    uint8_t base = 10, d;
    if (*s == '$' || *s == '%') { base = *s == '$' ? 16 : 2; s++; e = s; while (isid(*e)) e++; }
    else if (s[0] == '0' && s[1] == 'X') { base = 16; s += 2; e = s; while (isid(*e)) e++; }
    else {
        e = s; while (isid(*e)) e++;
        d = e[-1];
        if (d == 'H') { base = 16; e--; }
        else if (d == 'O' || d == 'Q') { base = 8; e--; }
        else if (d == 'B' && e - s > 1) {
            char *t; uint8_t bin = 1;
            for (t = s; t < e - 1; t++) if (*t != '0' && *t != '1') bin = 0;
            if (bin) { base = 2; e--; }
        }
        else if (d == 'D') e--;
    }
    if (s == e) { error("Bad number"); }
    for (; s < e; s++) {
        d = *s >= 'A' ? *s - 'A' + 10 : *s - '0';
        if (d >= base) { error("Bad number"); break; }
        v = v * base + d;
    }
    while (isid(*cp)) cp++;
    return v;
}
static int16_t primary(void)
{
    skipsp();
    if (*cp == '(') {
        int16_t v; cp++; v = expr(); skipsp();
        if (*cp == ')') cp++; else error("Missing )");
        return v;
    }
    if (*cp == '\'' || *cp == '"') {
        char q = *cp; uint16_t v = 0;
        /* el caracter tal como esta en src (sin pasar a mayusculas) */
        char *o = src + (cp - up_) + 1;
        cp++;
        while (*cp && !(*cp == q && cp[1] != q)) {
            if (*cp == q) { cp++; o++; }
            v = (v << 8) | (uint8_t)*o;
            cp++; o++;
        }
        if (*cp == q) cp++; else error("Missing quote");
        return v;
    }
    if (*cp == '$' && !((cp[1] >= '0' && cp[1] <= '9') || (cp[1] >= 'A' && cp[1] <= 'F'))) { cp++; return spc; }
    if ((*cp >= '0' && *cp <= '9') || *cp == '$' || *cp == '%') return number();
    if (isid0(*cp)) {
        char *s = cp; uint8_t *p;
        while (isid(*cp)) cp++;
        if (cp - s > NAMEL) error("Name too long");
        p = sfind(s, cp - s > NAMEL ? NAMEL : cp - s);
        if (!p || !(p[4] & S_DEF)) {
            undef = 1;
            if (pass == 2) error("Undefined symbol");
            return 0;
        }
        return *(int16_t *)(p + 2);
    }
    error("Bad expression");
    return 0;
}
static int16_t unary(void)
{
    skipsp();
    if (*cp == '-') { cp++; return -unary(); }
    if (*cp == '+') { cp++; return unary(); }
    if (*cp == '~') { cp++; return ~unary(); }
    if (word("NOT")) return ~unary();
    if (word("HIGH")) return (uint16_t)unary() >> 8;
    if (word("LOW")) return unary() & 255;
    return primary();
}
static int16_t mul(void)
{
    int16_t v = unary(), w;
    char o;
    for (;;) {
        skipsp();
        if (*cp == '*') { cp++; v *= unary(); continue; }
        if (*cp == '/') { cp++; o = '/'; }
        else if (*cp == '%') { cp++; o = '%'; }
        else if (word("MOD")) o = '%';
        else return v;
        w = unary();
        if (!w) { if (!undef) error("Division by zero"); v = 0; }
        else v = o == '/' ? (uint16_t)v / (uint16_t)w : (uint16_t)v % (uint16_t)w;
    }
}
static int16_t add(void)
{
    int16_t v = mul();
    for (;;) {
        skipsp();
        if (*cp == '+') { cp++; v += mul(); }
        else if (*cp == '-') { cp++; v -= mul(); }
        else return v;
    }
}
static int16_t shift(void)
{
    int16_t v = add();
    for (;;) {
        skipsp();
        if (cp[0] == '<' && cp[1] == '<') { cp += 2; v = (uint16_t)v << add(); }
        else if (cp[0] == '>' && cp[1] == '>') { cp += 2; v = (uint16_t)v >> add(); }
        else if (word("SHL")) v = (uint16_t)v << add();
        else if (word("SHR")) v = (uint16_t)v >> add();
        else return v;
    }
}
static int16_t andx(void)
{
    int16_t v = shift();
    for (;;) { skipsp(); if (*cp == '&') { cp++; v &= shift(); } else if (word("AND")) v &= shift(); else return v; }
}
static int16_t xorx(void)
{
    int16_t v = andx();
    for (;;) { skipsp(); if (*cp == '^') { cp++; v ^= andx(); } else if (word("XOR")) v ^= andx(); else return v; }
}
static int16_t orx(void)
{
    int16_t v = xorx();
    for (;;) { skipsp(); if (*cp == '|') { cp++; v |= xorx(); } else if (word("OR")) v |= xorx(); else return v; }
}
/* comparaciones (sin signo): verdadero = 0FFFFh */
static int16_t expr(void)
{
    uint16_t v = orx(), w;
    uint8_t op;
    skipsp();
    if (cp[0] == '=' && cp[1] == '=') { cp += 2; op = 1; }
    else if (cp[0] == '=') { cp++; op = 1; }
    else if ((cp[0] == '<' && cp[1] == '>') || (cp[0] == '!' && cp[1] == '=')) { cp += 2; op = 2; }
    else if (cp[0] == '<' && cp[1] == '=') { cp += 2; op = 5; }
    else if (cp[0] == '>' && cp[1] == '=') { cp += 2; op = 6; }
    else if (cp[0] == '<') { cp++; op = 3; }
    else if (cp[0] == '>') { cp++; op = 4; }
    else if (word("EQ")) op = 1; else if (word("NE")) op = 2; else if (word("LT")) op = 3;
    else if (word("GT")) op = 4; else if (word("LE")) op = 5; else if (word("GE")) op = 6;
    else return v;
    w = orx();
    switch (op) {
    case 1: v = v == w; break;
    case 2: v = v != w; break;
    case 3: v = v < w; break;
    case 4: v = v > w; break;
    case 5: v = v <= w; break;
    default: v = v >= w; break;
    }
    return v ? 0xFFFF : 0;
}

/* ------------------------------------------------------------ operandos */
enum { O_NONE, O_R8, O_R16, O_AF, O_AFP, O_IBC, O_IDE, O_ISP, O_IC, O_INN, O_IMM, O_I, O_R };
typedef struct { uint8_t t, r, px; int16_t v; } OP;

static char *opend(char *s)            /* fin del operando: coma fuera de () y comillas */
{
    uint8_t lev = 0;
    char *s0 = s;
    while (*s) {
        if (*s == '\'' && s - s0 >= 2 && s[-1] == 'F' && s[-2] == 'A') { s++; continue; }   /* AF' */
        if (*s == '\'' || *s == '"') {
            char q = *s++;
            while (*s && !(*s == q && s[1] != q)) { if (*s == q) s++; s++; }
            if (*s) s++;
            continue;
        }
        if (*s == '(') lev++;
        else if (*s == ')') { if (lev) lev--; }
        else if (*s == ',' && !lev) break;
        else if (*s == ';') break;
        s++;
    }
    return s;
}
static uint8_t is(char *s, uint8_t n, const char *w) { return strlen(w) == n && !memcmp(s, w, n); }

/* nombres de registro (ya en mayusculas): 1 si lo es */
static uint8_t regname(char *s, uint8_t n, OP *o)
{
    char a = s[0], b = s[1], c = s[2];
    if (n == 1) {
        switch (a) {
        case 'B': o->r = 0; break; case 'C': o->r = 1; break; case 'D': o->r = 2; break;
        case 'E': o->r = 3; break; case 'H': o->r = 4; break; case 'L': o->r = 5; break;
        case 'A': o->r = 7; break;
        case 'I': o->t = O_I; return 1;
        case 'R': o->t = O_R; return 1;
        default: return 0;
        }
        o->t = O_R8; return 1;
    }
    if (n == 2) {
        o->t = O_R16;
        if (a == 'B' && b == 'C') { o->r = 0; return 1; }
        if (a == 'D' && b == 'E') { o->r = 1; return 1; }
        if (a == 'H' && b == 'L') { o->r = 2; return 1; }
        if (a == 'S' && b == 'P') { o->r = 3; return 1; }
        if (a == 'I' && (b == 'X' || b == 'Y')) { o->r = 2; o->px = b == 'X' ? 0xDD : 0xFD; return 1; }
        if (a == 'A' && b == 'F') { o->t = O_AF; return 1; }
        o->t = O_R8;
        if ((a == 'H' || a == 'L') && (b == 'X' || b == 'Y')) { o->r = a == 'H' ? 4 : 5; o->px = b == 'X' ? 0xDD : 0xFD; return 1; }
        if ((a == 'X' || a == 'Y') && (b == 'H' || b == 'L')) { o->r = b == 'H' ? 4 : 5; o->px = a == 'X' ? 0xDD : 0xFD; return 1; }
        o->t = O_NONE;
        return 0;
    }
    if (n == 3) {
        if (a == 'A' && b == 'F' && c == '\'') { o->t = O_AFP; return 1; }
        if (a == 'I' && (b == 'X' || b == 'Y') && (c == 'H' || c == 'L')) {
            o->t = O_R8; o->r = c == 'H' ? 4 : 5; o->px = b == 'X' ? 0xDD : 0xFD; return 1;
        }
    }
    return 0;
}

static void operand(char *s, char *e0, OP *o)
{
    uint8_t n;
    char save = *e0, *e, c2;
    *e0 = 0;
    o->t = O_NONE; o->r = 0; o->px = 0; o->v = 0;
    while (*s == ' ') s++;
    e = e0;
    while (e > s && e[-1] == ' ') e--;
    c2 = *e; *e = 0;
    n = e - s;
    if (!n) goto fin;
    if (regname(s, n, o)) ;
    else {
        /* (algo): memoria solo si el ( del principio cierra al final */
        uint8_t whole = 0;
        if (*s == '(' && e[-1] == ')') {
            uint8_t lev = 0; char *t;
            whole = 1;
            for (t = s; t < e; t++) {
                if (*t == '\'' || *t == '"') { char q = *t++; while (t < e && *t != q) t++; continue; }
                if (*t == '(') lev++;
                else if (*t == ')') { lev--; if (!lev && t != e - 1) { whole = 0; break; } }
            }
        }
        if (whole) {
            char *u = s + 1, *v = e - 1, c3;
            uint8_t m;
            while (*u == ' ') u++;
            while (v > u && v[-1] == ' ') v--;
            m = v - u;
            c3 = *v; *v = 0;
            if (is(u, m, "HL")) { o->t = O_R8; o->r = 6; }
            else if (is(u, m, "BC")) o->t = O_IBC;
            else if (is(u, m, "DE")) o->t = O_IDE;
            else if (is(u, m, "SP")) o->t = O_ISP;
            else if (is(u, m, "C")) o->t = O_IC;
            else if (m >= 2 && u[0] == 'I' && (u[1] == 'X' || u[1] == 'Y') && (m == 2 || u[2] == '+' || u[2] == '-' || u[2] == ' ')) {
                o->t = O_R8; o->r = 6; o->px = u[1] == 'X' ? 0xDD : 0xFD;
                if (m > 2) {
                    cp = u + 2; o->v = expr(); skipsp();
                    if (*cp) error("Bad index expression");
                    if (!undef && (o->v < -128 || o->v > 127)) error("Index offset out of range");
                }
            } else {
                cp = u; o->v = expr(); skipsp();
                if (*cp) error("Bad expression");
                o->t = O_INN;
            }
            *v = c3;
        } else {
            cp = s; o->v = expr(); skipsp();
            if (*cp) error("Bad expression");
            o->t = O_IMM;
        }
    }
fin:
    *e = c2;
    *e0 = save;
}

/* ------------------------------------------------------------ instrucciones */
static OP a1, a2;
static uint8_t nops;

static void pfx(void)
{
    uint8_t p = a1.px ? a1.px : a2.px;
    if (a1.px && a2.px && a1.px != a2.px) error("Mixed IX and IY");
    if (p) emit(p);
}
static uint8_t isidx(OP *o) { return o->t == O_R8 && o->r == 6 && o->px; }
static void disp(void)
{
    if (isidx(&a1)) emit((uint8_t)a1.v);
    else if (isidx(&a2)) emit((uint8_t)a2.v);
}
static uint8_t isA(OP *o) { return o->t == O_R8 && o->r == 7; }
static uint8_t isHL(OP *o) { return o->t == O_R16 && o->r == 2; }
static void byteval(int16_t v)
{
    if (!undef && (v < -128 || v > 255)) error("Value out of range (byte)");
    emit((uint8_t)v);
}
static void bad(void) { error("Bad operands"); }
static void need(uint8_t n) { if (nops != n) error(n ? "Wrong number of operands" : "No operands expected"); }

/* r8 con r8: prohibido H/L con IXH.. o con (IX+d) mezclado mal */
static uint8_t r8ok(OP *x, OP *y)
{
    if (isidx(x) && y->t == O_R8 && y->px) return 0;
    if (isidx(y) && x->t == O_R8 && x->px) return 0;
    if (x->px && !isidx(x) && y->t == O_R8 && !y->px && (y->r == 4 || y->r == 5 || y->r == 6)) return 0;
    if (y->px && !isidx(y) && x->t == O_R8 && !x->px && (x->r == 4 || x->r == 5 || x->r == 6)) return 0;
    return 1;
}

static const char *const conds[] = { "NZ", "Z", "NC", "C", "PO", "PE", "P", "M" };
static uint8_t cond(char *s)
{
    uint8_t i;
    while (*s == ' ') s++;
    for (i = 0; i < 8; i++) {
        uint8_t n = strlen(conds[i]);
        char *t = s + n;
        while (*t == ' ') t++;
        if (!memcmp(s, conds[i], n) && (*t == ',' || *t == 0 || *t == ';')) return i;
    }
    return 0xFF;
}

static void alu(uint8_t k)            /* ADD ADC SUB SBC AND XOR OR CP: k = 0-7 */
{
    OP *o = &a1;
    if (nops == 2) {
        if (!isA(&a1)) { bad(); return; }
        o = &a2;
    } else if (nops != 1) { bad(); return; }
    if (o->t == O_R8) {
        if (o->px) emit(o->px);
        emit(0x80 + k * 8 + o->r);
        if (isidx(o)) emit((uint8_t)o->v);
    } else if (o->t == O_IMM) { emit(0xC6 + k * 8); byteval(o->v); }
    else bad();
}

static void rot(uint8_t base)          /* CB: RLC..SRL, BIT/RES/SET con el bit en base */
{
    OP *o = nops == 2 ? &a2 : &a1;
    if (o->t != O_R8 || (o->px && !isidx(o))) { bad(); return; }
    if (isidx(o)) { emit(o->px); emit(0xCB); emit((uint8_t)o->v); emit(base + o->r); }
    else { emit(0xCB); emit(base + o->r); }
}

static void jr(uint8_t op)
{
    int16_t d = a1.v - (int16_t)(pc + 2);
    if (nops == 2) d = a2.v - (int16_t)(pc + 2);
    emit(op);
    if (pass == 2 && (d < -128 || d > 127)) error("Relative jump out of range");
    emit((uint8_t)d);
}

/* mnemonicos: el orden fija el numero (mn) */
static const char *const mnem[] = {
    "NOP","RLCA","RRCA","RLA","RRA","DAA","CPL","SCF","CCF","HALT","DI","EI","EXX",
    "NEG","RRD","RLD","RETI","RETN",
    "LDI","CPI","INI","OUTI","LDD","CPD","IND","OUTD","LDIR","CPIR","INIR","OTIR","LDDR","CPDR","INDR","OTDR",
    "ADD","ADC","SUB","SBC","AND","XOR","OR","CP",
    "RLC","RRC","RL","RR","SLA","SRA","SLL","SRL","BIT","RES","SET",
    "INC","DEC","LD","PUSH","POP","EX","JP","JR","DJNZ","CALL","RET","RST","IN","OUT","IM",
    "SL1", 0 };
static const uint8_t single[] = { 0x00,0x07,0x0F,0x17,0x1F,0x27,0x2F,0x37,0x3F,0x76,0xF3,0xFB,0xD9 };
static const uint8_t edsingle[] = { 0x44,0x67,0x6F,0x4D,0x45,
    0xA0,0xA1,0xA2,0xA3,0xA8,0xA9,0xAA,0xAB,0xB0,0xB1,0xB2,0xB3,0xB8,0xB9,0xBA,0xBB };
enum { M_ADD = 34, M_RLC = 42, M_BIT = 50, M_INC = 53, M_DEC, M_LD, M_PUSH, M_POP, M_EX, M_JP, M_JR, M_DJNZ, M_CALL, M_RET, M_RST, M_IN, M_OUT, M_IM, M_SL1 };

static void instr(uint8_t mn, char *ops)
{
    char *e;
    uint8_t c = 0xFF;
    nops = 0; a1.t = a2.t = O_NONE; a1.px = a2.px = 0;
    while (*ops == ' ') ops++;
    if (mn == M_IN && ops[0] == 'F' && (ops[1] == ',' || ops[1] == ' ')) {   /* IN F,(C) = IN (C) */
        char *t = ops + 1; while (*t == ' ') t++;
        if (*t == ',') ops = t + 1;
    }
        if ((mn == M_JP || mn == M_JR || mn == M_CALL || mn == M_RET) && *ops && *ops != ';') {
        c = cond(ops);
        if (c != 0xFF) { ops = opend(ops); if (*ops == ',') ops++; else *ops = 0; }
    }
    if (*ops && *ops != ';') {
        e = opend(ops); operand(ops, e, &a1); nops = 1;
        if (*e == ',') { char *f = opend(e + 1); operand(e + 1, f, &a2); nops = 2; e = f; }
        if (*e == ',') error("Too many operands");
    }
    if (mn < 13) { need(0); emit(single[mn]); return; }
    if (mn < 34) { need(0); emit(0xED); emit(edsingle[mn - 13]); return; }
    if (mn < M_RLC) {
        uint8_t k = mn - M_ADD;
        /* 16 bits */
        if (nops == 2 && a1.t == O_R16 && a1.r == 2 && (k == 0 || k == 1 || k == 3)) {
            if (a2.t != O_R16) { bad(); return; }
            if (a2.r == 2 && a2.px != a1.px) { bad(); return; }
            if (k == 0) { if (a1.px) emit(a1.px); emit(0x09 + a2.r * 16); }
            else { if (a1.px) { bad(); return; } emit(0xED); emit((k == 1 ? 0x4A : 0x42) + a2.r * 16); }
            return;
        }
        alu(k);
        return;
    }
    if (mn < M_BIT || mn == M_SL1) { need(1); rot(((mn == M_SL1 ? 48 : mn) - M_RLC) * 8); return; }
    if (mn < M_INC) {
        int16_t b;
        need(2);
        if (a1.t != O_IMM) { bad(); return; }
        b = a1.v;
        if (b < 0 || b > 7) { error("Bit number must be 0-7"); b = 0; }
        rot((mn == M_BIT ? 0x40 : mn == M_BIT + 1 ? 0x80 : 0xC0) + b * 8);
        return;
    }
    switch (mn) {
    case M_INC: case M_DEC:
        need(1);
        if (a1.t == O_R8) { if (a1.px) emit(a1.px); emit((mn == M_INC ? 0x04 : 0x05) + a1.r * 8); if (isidx(&a1)) emit((uint8_t)a1.v); }
        else if (a1.t == O_R16) { if (a1.px) emit(a1.px); emit((mn == M_INC ? 0x03 : 0x0B) + a1.r * 16); }
        else bad();
        return;
    case M_PUSH: case M_POP:
        need(1);
        if (a1.t == O_R16 && a1.r != 3) { if (a1.px) emit(a1.px); emit((mn == M_PUSH ? 0xC5 : 0xC1) + a1.r * 16); }
        else if (a1.t == O_AF) emit(mn == M_PUSH ? 0xF5 : 0xF1);
        else bad();
        return;
    case M_EX:
        need(2);
        if (a1.t == O_R16 && a1.r == 1 && !a1.px && isHL(&a2) && !a2.px) emit(0xEB);
        else if (a1.t == O_AF && a2.t == O_AFP) emit(0x08);
        else if (a1.t == O_ISP && isHL(&a2)) { if (a2.px) emit(a2.px); emit(0xE3); }
        else bad();
        return;
    case M_JP:
        if (c != 0xFF) { need(1); if (a1.t != O_IMM) { bad(); return; } emit(0xC2 + c * 8); emitw(a1.v); return; }
        need(1);
        if (a1.t == O_R8 && a1.r == 6 && !a1.v) { if (a1.px) emit(a1.px); emit(0xE9); }
        else if (a1.t == O_R16 && a1.r == 2) { if (a1.px) emit(a1.px); emit(0xE9); }  /* JP HL / JP IX */
        else if (a1.t == O_IMM) { emit(0xC3); emitw(a1.v); }
        else bad();
        return;
    case M_JR:
        if (c != 0xFF) { if (c > 3) { error("JR only takes NZ, Z, NC or C"); c = 0; } need(1); jr(0x20 + c * 8); return; }
        need(1); jr(0x18); return;
    case M_DJNZ: need(1); jr(0x10); return;
    case M_CALL:
        need(1);
        if (a1.t != O_IMM) { bad(); return; }
        emit(c != 0xFF ? 0xC4 + c * 8 : 0xCD); emitw(a1.v);
        return;
    case M_RET:
        if (c != 0xFF) { need(0); emit(0xC0 + c * 8); } else { need(0); emit(0xC9); }
        return;
    case M_RST:
        need(1);
        if (a1.t != O_IMM) { bad(); return; }
        if (a1.v & ~0x38) {
            if (a1.v > 0 && a1.v < 8) a1.v *= 8;
            else { error("RST takes 0, 8, 10H ... 38H"); a1.v = 0; }
        }
        emit(0xC7 + a1.v);
        return;
    case M_IM:
        need(1);
        if (a1.t != O_IMM || a1.v < 0 || a1.v > 2) { bad(); return; }
        emit(0xED); emit(a1.v == 0 ? 0x46 : a1.v == 1 ? 0x56 : 0x5E);
        return;
    case M_IN:
        if (nops == 1 && a1.t == O_IC) { emit(0xED); emit(0x70); return; }
        need(2);
        if (isA(&a1) && a2.t == O_INN) { emit(0xDB); byteval(a2.v); }
        else if (a2.t == O_IC && a1.t == O_R8 && !a1.px && a1.r != 6) { emit(0xED); emit(0x40 + a1.r * 8); }
        else bad();
        return;
    case M_OUT:
        need(2);
        if (a1.t == O_INN && isA(&a2)) { emit(0xD3); byteval(a1.v); }
        else if (a1.t == O_IC && a2.t == O_R8 && !a2.px && a2.r != 6) { emit(0xED); emit(0x41 + a2.r * 8); }
        else if (a1.t == O_IC && a2.t == O_IMM && a2.v == 0) { emit(0xED); emit(0x71); }
        else bad();
        return;
    case M_LD:
        need(2);
        if (a1.t == O_R8 && a2.t == O_R8) {
            if (a1.r == 6 && a2.r == 6) { bad(); return; }
            if (!r8ok(&a1, &a2)) { bad(); return; }
            pfx(); emit(0x40 + a1.r * 8 + a2.r); disp(); return;
        }
        if (a1.t == O_R8 && a2.t == O_IMM) {
            if (a1.px) emit(a1.px);
            emit(0x06 + a1.r * 8);
            if (isidx(&a1)) emit((uint8_t)a1.v);
            byteval(a2.v); return;
        }
        if (isA(&a1)) {
            if (a2.t == O_IBC) { emit(0x0A); return; }
            if (a2.t == O_IDE) { emit(0x1A); return; }
            if (a2.t == O_INN) { emit(0x3A); emitw(a2.v); return; }
            if (a2.t == O_I) { emit(0xED); emit(0x57); return; }
            if (a2.t == O_R) { emit(0xED); emit(0x5F); return; }
        }
        if (isA(&a2)) {
            if (a1.t == O_IBC) { emit(0x02); return; }
            if (a1.t == O_IDE) { emit(0x12); return; }
            if (a1.t == O_INN) { emit(0x32); emitw(a1.v); return; }
            if (a1.t == O_I) { emit(0xED); emit(0x47); return; }
            if (a1.t == O_R) { emit(0xED); emit(0x4F); return; }
        }
        if (a1.t == O_R16) {
            if (a2.t == O_IMM) { if (a1.px) emit(a1.px); emit(0x01 + a1.r * 16); emitw(a2.v); return; }
            if (a2.t == O_INN) {
                if (a1.r == 2) { if (a1.px) emit(a1.px); emit(0x2A); }
                else { emit(0xED); emit(0x4B + a1.r * 16); }
                emitw(a2.v); return;
            }
            if (a1.r == 3 && isHL(&a2)) { if (a2.px) emit(a2.px); emit(0xF9); return; }
        }
        if (a1.t == O_INN && a2.t == O_R16) {
            if (a2.r == 2) { if (a2.px) emit(a2.px); emit(0x22); }
            else { emit(0xED); emit(0x43 + a2.r * 16); }
            emitw(a1.v); return;
        }
        bad();
        return;
    }
}

/* ------------------------------------------------------------ lineas */
#define NIF 8
static uint8_t ifs[NIF], nif, skip_;  /* ifs: 1 = rama activa; skip_: hay algun nivel falso */
static uint8_t ended;
static char *incname;

static void dodata(uint8_t w, char *s)
{
    while (*s && *s != ';') {
        char *e = opend(s), *t = s;
        while (*t == ' ') t++;
        if ((*t == '\'' || *t == '"') && !w) {
            /* cadena: si sigue algo despues de la comilla (como 'A'+80H) es expresion */
            char q = *t, *u = t + 1;
            while (*u && !(*u == q && u[1] != q)) { if (*u == q) u++; u++; }
            if (*u == q) u++;
            while (*u == ' ') u++;
            if (u == e && u - t != 3) {
                char *o = src + (t - up_) + 1;
                for (u = t + 1; *u && !(*u == q && u[1] != q); u++, o++) {
                    if (*u == q) { u++; o++; }
                    emit((uint8_t)*o);
                }
                s = *e == ',' ? e + 1 : e;
                continue;
            }
        }
        {
            char c = *e; int16_t v;
            *e = 0; cp = t; v = expr(); skipsp();
            if (*cp) error("Bad expression");
            *e = c;
            if (w) emitw(v); else byteval(v);
        }
        s = *e == ',' ? e + 1 : e;
    }
}

/* directivas: el orden fija el numero */
static const char *const dirs[] = { "ORG","EQU","DEFL","=","SET","DB","DEFB","DEFM","DM","BYTE","TEXT",
    "DW","DEFW","WORD","DS","DEFS","BLOCK","END","IF","ELSE","ENDIF","ENDC","INCLUDE",
    "TITLE","PAGE",".Z80","NAME","LIST","NLIST","EJECT","ASEG", 0 };
enum { D_ORG, D_EQU, D_DEFL, D_EQS, D_SET, D_DB, D_DW = 11, D_DS = 14, D_END = 17, D_IF, D_ELSE, D_ENDIF, D_ENDC, D_INC, D_IGN };
/* tabla hash de palabras clave: id + 1 (0 = vacio); id 0-69 instruccion, 100+ directiva */
static uint8_t kwh[256];
static const char *kwname(uint8_t id) { return id >= 100 ? dirs[id - 100] : mnem[id]; }
static uint8_t kwhash(const char *s, uint8_t n)
{
    uint8_t h = n * 7;
    while (n--) h = (uint8_t)((h << 1) + (h >> 7)) ^ *s++;
    return h;
}
static void kwput(uint8_t id)
{
    const char *w = kwname(id);
    uint8_t h = kwhash(w, strlen(w));
    while (kwh[h]) h++;
    kwh[h] = id + 1;
}
static void kwinit(void)
{
    uint8_t i;
    for (i = 0; mnem[i]; i++) kwput(i);
    for (i = 0; dirs[i]; i++) kwput(100 + i);
}
static uint8_t kw(char *s, uint8_t n)
{
    uint8_t h, id;
    const char *w;
    if (!n || n > 7) return 0xFF;
    h = kwhash(s, n);
    while ((id = kwh[h])) {
        id--;
        w = kwname(id);
        if (w[0] == *s && !memcmp(w, s, n) && !w[n]) return id;
        h++;
    }
    return 0xFF;
}
static uint8_t wlen(char *s) { char *w = s; while (isid(*w)) w++; return w - s; }
/* la palabra en s (sin ':' despues) es una instruccion o directiva */
static uint8_t iskw(char *s)
{
    uint8_t n = wlen(s);
    if (s[n] == ':') return 0;
    return kw(s, n) != 0xFF;
}

static void doline(void)
{
    char *s, *lab = 0, *w;
    uint8_t ll = 0, i, mn;
    s = up_;
    err1 = 0; undef = 0; spc = lpc = pc;
    if (*s == ';' || *s == '*' ) return;
    /* etiqueta */
    if (*s != ' ' && *s && !(*s != ':' && iskw(s))) {
        lab = s;
        while (isid(*s)) s++;
        ll = s - lab;
        if (*s == ':') s++;
        if (*s == ':') s++;
    } else {
        while (*s == ' ') s++;
        w = s;
        while (isid(*w)) w++;
        if (*w == ':' && w > s) { lab = s; ll = w - s; s = w + 1; }
    }
    while (*s == ' ') s++;
    w = s;
    if (*w == '=') w++; else while (isid(*w)) w++;
    mn = kw(s, w - s);
    /* condicionales: se miran aunque se este saltando */
    if (mn == 100 + D_IF) {
        if (nif == NIF) { error("IF nested too deep"); return; }
        if (skip_) { ifs[nif++] = 0; return; }
        cp = w; ifs[nif++] = expr() != 0;
        if (undef) error("IF needs a value known in pass 1");
        skip_ = !ifs[nif - 1];
        return;
    }
    if (mn == 100 + D_ELSE || mn == 100 + D_ENDIF || mn == 100 + D_ENDC) {
        if (!nif) { error("ELSE/ENDIF without IF"); return; }
        if (mn == 100 + D_ELSE) ifs[nif - 1] = !ifs[nif - 1] && (nif == 1 || ifs[nif - 2]);
        else nif--;
        skip_ = 0;
        for (i = 0; i < nif; i++) if (!ifs[i]) skip_ = 1;
        return;
    }
    if (skip_) return;
    if (lab && ll > NAMEL) { error("Name too long"); ll = NAMEL; }
    /* EQU / DEFL / = / SET */
    if (mn == 52 && lab && ll && *w == ' ' && !strchr(w, ',')) mn = 100 + D_SET;   /* NOMBRE SET valor */
    if (mn == 100 + D_EQU || mn == 100 + D_DEFL || mn == 100 + D_EQS || (mn == 100 + D_SET && lab)) {
        uint8_t set = mn != 100 + D_EQU;
        int16_t v;
        if (!lab) { error("EQU needs a name"); return; }
        cp = w; v = expr(); skipsp();
        if (*cp && *cp != ';') error("Bad expression");
        if (!undef || pass == 2) define(lab, ll, v, set);
        else if (!sfind(lab, ll)) sadd(lab, ll);   /* se resuelve en la pasada 2 */
        lpc = v;
        return;
    }
    if (lab) define(lab, ll, pc, 0);
    lpc = pc;
    if (s == w || *s == ';') return;
    {
        char *a = w;
        while (*a == ' ') a++;
        if (mn == 0xFF) { error("Unknown instruction"); return; }
        if (mn < 100) { instr(mn, a); return; }
        mn -= 100;
        if (mn == D_ORG) {
            cp = a; pc = expr();
            if (undef) error("ORG needs a known value");
            if (!anyout) origin = pc;           /* el .COM empieza en el primer ORG */
            lpc = pc; return;
        }
        if (mn >= D_DB && mn < D_DW) { dodata(0, a); return; }
        if (mn >= D_DW && mn < D_DS) { dodata(1, a); return; }
        if (mn >= D_DS && mn < D_END) {
            uint16_t k; uint8_t f = 0;
            cp = a; k = expr();
            if (undef) { error("DS needs a known value"); return; }
            skipsp();
            if (*cp == ',') { cp++; f = expr(); }
            if (f) while (k--) emit(f);       /* con relleno: bytes; si no, solo se avanza */
            else pc += k;
            return;
        }
        if (mn == D_END) { ended = 1; return; }
        if (mn == D_INC) {
            char *f = src + (a - up_), *g;
            if (*f == '"' || *f == '\'' || *f == '<') f++;
            for (g = f; *g && *g != ' ' && *g != '"' && *g != '\'' && *g != '>' && *g != ';'; g++) ;
            *g = 0;
            incname = f;
            return;
        }
        if (mn == D_SET) { error("SET needs a name (or use SET b,r)"); return; }
        /* TITLE, PAGE... se saltan */
    }
}

static void listline(void)
{
    char t[24];
    uint8_t i;
    if (pass != 2 || !lst) return;
    t[0] = hx[lpc >> 12]; t[1] = hx[(lpc >> 8) & 15]; t[2] = hx[(lpc >> 4) & 15]; t[3] = hx[lpc & 15]; t[4] = ' ';
    for (i = 0; i < 4; i++) {
        if (i < lbn) { t[5 + i * 2] = hx[lb[i] >> 4]; t[6 + i * 2] = hx[lb[i] & 15]; }
        else t[5 + i * 2] = t[6 + i * 2] = ' ';
    }
    t[13] = lmore ? '+' : ' ';
    t[14] = ' '; t[15] = 0;
    if (err1) t[14] = '*';
    lstr(t);
    lstr(src);
    lstr("\n");
}

static uint8_t runpass(char *name)
{
    pc = 0x100; lineno = 0; depth = 0; nif = 0; skip_ = 0; ended = 0; nlines = 0;
    anyout = 0; if (pass == 1) origin = 0x100;
    if (openin(name, 0)) return 1;
    crd = &rd[0];
    while (!ended && getline_()) {
        nlines++;
        lbn = 0; lmore = 0;
        incname = 0;
        doline();
        listline();
        if (incname) {
            if (depth == 2) { error("INCLUDE nested too deep"); continue; }
            lines_[depth] = lineno;
            if (openin(incname, depth + 1)) { error("INCLUDE: file not found"); continue; }
            depth++;
            crd = &rd[depth];
            lineno = 0;
        }
        if (!(nlines & 15) && brk()) { pstr("Stopped\n"); exit(); }
    }
    while (depth) { fclose(&rd[depth].f); depth--; }
    fclose(&rd[0].f);
    if (nif && pass == 2) { pf("%s: IF without ENDIF\n", fnames[0]); nerrs++; }
    return 0;
}

/* nombre con otra extension (sin cambiar la unidad) */
static void withext(char *out, const char *in, const char *ext)
{
    char *d = out;
    while (*in && *in != '.') *d++ = *in++;
    *d++ = '.';
    strcpy(d, ext);
}

void main(void)
{
    char *p = args(), *a, *name = 0;
    static char in[20], tmp[20];
    uint16_t top = *(uint16_t *)6 - 512;
    while ((a = nextarg(&p))) {
        if (a[0] == '-' && (a[1] == 'L' || a[1] == 'l')) lst = 1;
        else if (a[0] == '-' && (a[1] == 'H' || a[1] == 'h')) hexo = 1;
        else name = a;
    }
    if (!name) {
        pstr("ZAS - Z80 assembler (Zilog mnemonics)\n"
             "Usage: ZAS file[.Z80] [-L] [-H]\n"
             "  makes file.COM; -L listing in file.PRN, -H also file.HEX\n");
        return;
    }
    hp = (uint8_t *)heap; htop = (uint8_t *)top;
    kwinit();
    if (strlen(name) > 14) { pstr("Bad file name\n"); return; }
    strcpy(in, name);
    if (!strchr(in, '.')) {
        FCB f;
        withext(tmp, in, "Z80");
        if (mkfcb(&f, tmp) && !fopen(&f)) { fclose(&f); strcpy(in, tmp); }
        else withext(in, name, "ASM");
    }
    pf("ZAS 1.0  %s\n", in);
    pass = 1;
    if (runpass(in)) { pf("%s: not found\n", in); return; }
    pass = 2; started = 0;
    withext(tmp, in, "COM");
    if (!mkfcb(&ocom, tmp) || fmake(&ocom)) { pf("%s: cannot create\n", tmp); return; }
    if (lst) { withext(tmp, in, "PRN"); if (!mkfcb(&oprn, tmp) || fmake(&oprn)) { pf("%s: cannot create\n", tmp); lst = 0; } }
    if (hexo) { withext(tmp, in, "HEX"); if (!mkfcb(&ohex, tmp) || fmake(&ohex)) { pf("%s: cannot create\n", tmp); hexo = 0; } }
    runpass(in);
    ofin();
    if (lst) {
        char t[8]; uint16_t v; uint8_t i;
        lstr("\nErrors: ");
        for (v = nerrs, i = 6, t[6] = 0; i--; ) { t[i] = '0' + v % 10; v /= 10; if (!v) { lstr(t + i); break; } }
        lstr("\n");
        lfin(&oprn, lbuf, &ln_, 1024);
    }
    if (hexo) { hflush(); hstr(":00000001FF\r\n"); lfin(&ohex, hbuf, &hn, 256); }
    if (oerr) pstr("Write error (disk full?)\n");
    withext(tmp, in, "COM");
    if (started)
        pf("%u lines, %u symbols, %s: %04Xh-%04Xh (%u bytes), %u error(s)\n",
           nlines, nsym, tmp, start, outaddr - 1, outaddr - start, nerrs);
    else pf("%u lines, %u symbols, no code, %u error(s)\n", nlines, nsym, nerrs);
    if (nerrs) fdelete(&ocom);
}
