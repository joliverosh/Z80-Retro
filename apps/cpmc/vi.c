/* VI - un editor como vi para CP/M 2.2 y MP/M II (terminal ANSI de 80 columnas)
   VI [archivo]
   El texto va en memoria (un bufer con hueco, unos 21 KB en MP/M). Filas 1-22:
   el texto; fila 23: mensajes y las ordenes de ':' '/' '?'.
   Normal: h j k l (y flechas) w b e 0 ^ $ G gg H M L f F t T ; , % ^F ^B ^D ^U
           x X r ~ J dd D C s S cc yy Y p P i a I A o O u . n N /texto ?texto ^G ^L ZZ
           d c y con cualquier movimiento (dw, c$, y3j, dG...), y cuentas (3dd, 5x)
   Ex:     :w [arch]  :q  :q!  :wq  :x  :e arch  :e!  :r arch  :N (linea)  :$
           :[rango]d  :[rango]s/viejo/nuevo/[g]  (rango: N  N,M  .  $  %)
   (C) OLIVEROS 2026 */
#include <string.h>
#include "cpm.h"

#define ROWS 22                  /* filas de texto */
#define CMDROW 23
#define KUP 0x81
#define KDOWN 0x82
#define KRIGHT 0x83
#define KLEFT 0x84
#define KHOME 0x85
#define KEND 0x86
#define KDEL 0x87
#define KPGUP 0x88
#define KPGDN 0x89
#define CTRL(c) ((c) & 31)

extern char heap[];

/* ---------------------------------------------------------------- texto */
static char *buf;
static uint16_t bsz, gs, ge;     /* el hueco: [gs, ge) */
static uint8_t modified;
#define LEN() (bsz - (ge - gs))
static char ch(uint16_t i) { return i < gs ? buf[i] : buf[i + (ge - gs)]; }
static void moveto(uint16_t p)
{
    if (p < gs) {
        uint16_t n = gs - p;
        memmove(buf + ge - n, buf + p, n);
        gs = p; ge -= n;
    } else if (p > gs) {
        uint16_t n = p - gs;
        memmove(buf + gs, buf + ge, n);
        gs += n; ge += n;
    }
}

/* deshacer: dos registros; deshacer escribe en el otro lo contrario, asi que
   u otra vez rehace. Cada entrada: tipo, pos, n, [texto], tamano total */
#define ULOG 1200
static uint8_t ulog[2][ULOG];
static uint16_t ulen[2];
static uint8_t ucur, uok[2], undoing;
static void ustart(void) { ulen[ucur] = 0; uok[ucur] = 1; }
static void ulogop(uint8_t t, uint16_t p, uint16_t n, const char *d)
{
    uint8_t *l = ulog[ucur];
    uint16_t sz = 7 + (t ? n : 0), u = ulen[ucur];
    if (!uok[ucur]) return;
    if (u + sz > ULOG) { uok[ucur] = 0; return; }
    l += u;
    l[0] = t; l[1] = p; l[2] = p >> 8; l[3] = n; l[4] = n >> 8;
    if (t) {                     /* el texto puede estar partido por el hueco */
        uint16_t i;
        for (i = 0; i < n; i++) l[5 + i] = d ? d[i] : ch(p + i);
    }
    l[sz - 2] = sz; l[sz - 1] = sz >> 8;
    ulen[ucur] = u + sz;
}
static uint16_t room(void) { return ge - gs; }
static uint8_t ins(uint16_t p, const char *s, uint16_t n)
{
    if (n > room()) return 0;
    moveto(p);
    memcpy(buf + gs, s, n);
    gs += n;
    ulogop(0, p, n, 0);
    modified = 1;
    return 1;
}
static uint8_t insc(uint16_t p, char c) { return ins(p, &c, 1); }
static void del(uint16_t p, uint16_t n)
{
    if (!n) return;
    ulogop(1, p, n, 0);
    moveto(p);
    ge += n;
    modified = 1;
}

/* ---------------------------------------------------------------- lineas */
static uint16_t lstart(uint16_t p) { while (p && ch(p - 1) != '\n') p--; return p; }
static uint16_t lend(uint16_t p) { uint16_t n = LEN(); while (p < n && ch(p) != '\n') p++; return p; }
static uint16_t nextl(uint16_t p) { uint16_t e = lend(p); return e < LEN() ? e + 1 : e; }
static uint16_t prevl(uint16_t p) { p = lstart(p); return p ? lstart(p - 1) : 0; }
static uint16_t lastl(void) { return lstart(LEN() - 1); }
static uint8_t isblank(char c) { return c == ' ' || c == '\t'; }
static uint16_t firstnb(uint16_t p)
{
    p = lstart(p);
    while (isblank(ch(p))) p++;
    return p;
}
static uint16_t lineno(uint16_t p)  /* 1.. */
{
    uint16_t i, n = 1;
    for (i = 0; i < p; i++) if (ch(i) == '\n') n++;
    return n;
}
static uint16_t nlines(void) { return lineno(LEN() - 1); }
static uint16_t gotol(uint16_t n)   /* el principio de la linea n (1..) */
{
    uint16_t p = 0, last = lastl();
    while (--n && p < last) p = nextl(p);
    return p;
}
static uint8_t cw(char c) { return c == '\t' ? 8 : (uint8_t)c < 32 || c == 127 ? 2 : 1; }
static uint16_t colof(uint16_t p)   /* la columna en pantalla de p */
{
    uint16_t i = lstart(p), c = 0;
    for (; i < p; i++) {
        char k = ch(i);
        if (k == '\t') c = (c | 7) + 1; else c += cw(k);
    }
    return c;
}
static uint16_t atcol(uint16_t ls, uint16_t col)   /* la pos mas cerca de col */
{
    uint16_t c = 0, e = lend(ls);
    while (ls < e) {
        char k = ch(ls);
        uint16_t nc = k == '\t' ? (c | 7) + 1 : c + cw(k);
        if (nc > col) break;
        c = nc; ls++;
    }
    return ls;
}

/* ---------------------------------------------------------------- pantalla */
/* la salida va por BDOS 6, un caracter cada vez: BDOS 2 y 9 miran el teclado
   (por ^S) y el caracter que se lleven ya no lo devuelve BDOS 6 */
#define oflush()
#define oc(c) putch(c)
static void os(const char *s) { while (*s) oc(*s++); }
static void onum(uint16_t v) { char b[6]; uint8_t n = 0; do b[n++] = '0' + v % 10; while (v /= 10); while (n) oc(b[--n]); }
static void ogo(uint8_t r, uint8_t c) { oc(27); oc('['); onum(r); oc(';'); onum(c); oc('H'); }
static void oeol(void) { os("\x1b[K"); }

static uint16_t top, cur, left, wantcol;
static uint8_t need, frow, crow;
#define N_NONE 0
#define N_LINE 1
#define N_FROM 2
#define N_ALL 3
static uint8_t msgon;
static char fname_[16];
/* hay una tecla esperando? Sin BDOS 11, que (como 2 y 9) se lleva el caracter
   a un bufer que BDOS 6 no mira: en MP/M, BDOS 6 FE; en CP/M, CONST del BIOS */
static uint8_t bconst(void) __sdcccall(0) __naked
{
    __asm
        push    ix
        push    iy
        ld      hl,(1)
        inc     hl
        inc     hl
        inc     hl
        ld      de,#00001$
        push    de
        jp      (hl)
00001$: pop     iy
        pop     ix
        ld      l,a
        ret
    __endasm;
}
static uint8_t pending(void) { return ismpm() ? bdos(6, 0xFE) & 0xFF : bconst(); }

static uint16_t drawline(uint8_t r, uint16_t p)
{
    uint16_t c = 0, n = LEN();
    ogo(r, 1);
    if (p >= n) { oc('~'); oeol(); return p; }
    for (; p < n; p++) {
        char k = ch(p);
        uint8_t w;
        if (k == '\n') { p++; break; }
        if (c >= left + 80) continue;
        if (k == '\t') {
            w = 8 - (c & 7);
            while (w--) { if (c >= left && c < left + 80) oc(' '); c++; }
            continue;
        }
        if ((uint8_t)k < 32 || k == 127) {
            if (c >= left && c < left + 80) oc('^');
            c++;
            k = k == 127 ? '?' : k + 64;
        } else if ((uint8_t)k > 126) k = '?';
        if (c >= left && c < left + 80) oc(k);
        c++;
    }
    if (c < left + 80) oeol();
    return p;
}
static void msg(const char *s)
{
    ogo(CMDROW, 1); os(s); oeol();
    msgon = 1;
}
static void msgn(const char *a, uint16_t v, const char *b)
{
    ogo(CMDROW, 1); os(a); onum(v); os(b); oeol();
    msgon = 1;
}
/* que se vea el cursor: top, left, crow */
static void adjust(void)
{
    uint16_t ls = lstart(cur), p, c;
    uint8_t r;
    if (ls < top) {
        if (prevl(top) == ls && need != N_ALL) {
            top = ls;
            if (need == N_FROM) frow++;
            ogo(1, 1); os("\x1b[L");       /* una fila hacia abajo */
            ogo(CMDROW, 1); oeol();
            drawline(1, top);
        } else {
            for (top = ls, r = 0; r < ROWS / 2 && top; r++) top = prevl(top);
            need = N_ALL;
        }
    }
    for (p = top, r = 1; p < ls && r <= ROWS + 1; r++) p = nextl(p);
    if (r > ROWS) {
        if (r == ROWS + 1 && need != N_ALL) {
            top = nextl(top);
            if (need == N_FROM && frow > 1) frow--;
            ogo(1, 1); os("\x1b[M");       /* una fila hacia arriba */
            drawline(ROWS, ls);
            ogo(CMDROW, 1); oeol();
            r = ROWS;
        } else {
            for (top = ls, r = 0; r < ROWS / 2 && top; r++) top = prevl(top);
            for (p = top, r = 0; r < ROWS && p < LEN(); r++) p = nextl(p);
            while (r++ < ROWS && top) top = prevl(top);   /* sin ~ si hay lineas antes */
            need = N_ALL;
            for (p = top, r = 1; p < ls; r++) p = nextl(p);
        }
    }
    crow = r;
    c = colof(cur);
    if (c < left || c >= left + 80) {
        left = c < 72 ? 0 : (c - 40) & ~7;
        need = N_ALL;
    }
}
static void refresh(void)
{
    uint16_t p;
    uint8_t r;
    adjust();
    if (need == N_ALL) {
        for (p = top, r = 1; r <= ROWS; r++) p = drawline(r, p);
    } else if (need == N_FROM) {
        for (p = top, r = 1; r < frow; r++) p = nextl(p);
        for (; r <= ROWS; r++) p = drawline(r, p);
    } else if (need == N_LINE) drawline(crow, lstart(cur));
    need = N_NONE;
    ogo(crow, colof(cur) - left + 1);
    oflush();
}
static uint8_t rowof(uint16_t p)    /* la fila de una linea (o 1) */
{
    uint16_t q = top; uint8_t r = 1;
    p = lstart(p);
    if (p < top) return 1;
    while (q < p && r <= ROWS) { q = nextl(q); r++; }
    return r;
}
static void needfrom(uint16_t p)
{
    uint8_t r = rowof(p);
    if (need == N_ALL) return;
    if (need == N_FROM && frow < r) return;
    need = N_FROM; frow = r;
}

/* ---------------------------------------------------------------- teclado */
static uint8_t curk[200], dotk[200], nk, dotn, rec, recbad;
static uint8_t *rp; static uint8_t rn, inj;   /* inj: una tecla puesta por el programa (no se graba) */
static uint8_t pb[2], npb;       /* teclas devueltas (se sacan del final) */
static uint8_t rawk(void)
{
    int k;
    if (npb) return pb[--npb];
    oflush();
    while (!(k = getkey())) delay(1);
    return k;
}
static uint8_t soon(void)        /* un caracter que llega enseguida, o 0 */
{
    uint8_t n, k = 0;
    for (n = 0; n < 60 && !(k = getkey()); n++) ;
    return k;
}
static uint8_t termkey(void)
{
    uint8_t k = rawk(), k2;
    if (k != 27) return k == 127 ? 8 : k;
    k2 = soon();
    if (k2 != '[' && k2 != 'O') { if (k2) pb[npb++] = k2; return 27; }
    k = soon();
    if (k2 == 'O' && !(k >= 'A' && k <= 'D') && k != 'H' && k != 'F') {
        if (k) pb[npb++] = k;          /* ESC O y otra cosa: era ESC, O... */
        pb[npb++] = 'O';
        return 27;
    }
    switch (k) {
    case 'A': return KUP;
    case 'B': return KDOWN;
    case 'C': return KRIGHT;
    case 'D': return KLEFT;
    case 'H': return KHOME;
    case 'F': return KEND;
    }
    if (k >= '1' && k <= '6') {
        k2 = soon();
        if (k2 == '~') switch (k) {
            case '1': return KHOME;
            case '3': return KDEL;
            case '4': return KEND;
            case '5': return KPGUP;
            case '6': return KPGDN;
        }
    }
    return 0;
}
static uint8_t getk(void)
{
    uint8_t c;
    if (inj) { c = inj; inj = 0; return c; }
    if (rn) { rn--; c = *rp++; }
    else c = termkey();
    if (rec) { if (nk < sizeof curk) curk[nk++] = c; else recbad = 1; }
    return c;
}

/* ---------------------------------------------------------------- linea de ordenes */
static char cl[80];
static uint8_t readline(char lead)
{
    uint8_t n = 0, c;
    ogo(CMDROW, 1); oc(lead); oeol();
    for (;;) {
        c = getk();
        if (c == 27) { ogo(CMDROW, 1); oeol(); return 0; }
        if (c == '\r' || c == '\n') break;
        if (c == 8) {
            if (!n) { ogo(CMDROW, 1); oeol(); return 0; }
            n--; os("\b \b");
        } else if (c >= 32 && c < 127 && n < 78) { cl[n++] = c; oc(c); }
    }
    cl[n] = 0;
    return 1;
}

/* ---------------------------------------------------------------- copiar */
#define YSZ 2000
static char ybuf[YSZ];
static uint16_t ylen;
static uint8_t ylw;
static uint8_t yank(uint16_t a, uint16_t b, uint8_t lw)
{
    uint16_t i;
    if (b - a > YSZ) { msg("Too much to yank (2000 max)"); return 0; }
    for (i = a; i < b; i++) ybuf[i - a] = ch(i);
    ylen = b - a; ylw = lw;
    return 1;
}

/* ---------------------------------------------------------------- movimientos */
static uint8_t cls(char c)
{
    if (c == ' ' || c == '\t' || c == '\n') return 0;
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_') return 1;
    return 2;
}
static uint16_t wfwd(uint16_t p)
{
    uint16_t n = LEN() - 1;
    uint8_t k = cls(ch(p));
    if (k) while (p < n && cls(ch(p)) == k) p++;
    while (p < n) {
        char c = ch(p);
        if (c == '\n') { p++; if (ch(p) == '\n') break; continue; }
        if (isblank(c)) p++; else break;
    }
    return p;
}
static uint16_t wback(uint16_t p)
{
    uint8_t k;
    if (!p) return 0;
    p--;
    while (p) {
        char c = ch(p);
        if (c == '\n') { if (ch(p - 1) == '\n') break; p--; continue; }
        if (isblank(c)) p--; else break;
    }
    k = cls(ch(p));
    if (k) while (p && cls(ch(p - 1)) == k) p--;
    return p;
}
static uint16_t wend(uint16_t p)
{
    uint16_t n = LEN() - 1;
    uint8_t k;
    if (p < n) p++;
    while (p < n && !cls(ch(p))) p++;
    k = cls(ch(p));
    while (p + 1 < n && cls(ch(p + 1)) == k) p++;
    return p;
}
static char fch, fcmd;
static uint8_t findc(char cmd, char c, uint16_t cnt, uint16_t *to)
{
    uint16_t p = cur, ls = lstart(cur), le = lend(cur);
    uint8_t fwd = cmd == 'f' || cmd == 't';
    while (cnt--) {
        uint16_t q = p;
        for (;;) {
            if (fwd) { if (q + 1 >= le) return 0; q++; }
            else { if (q <= ls) return 0; q--; }
            if (ch(q) == c) break;
        }
        p = q;
        if (cmd == 't' && cnt == 0) p--;
        if (cmd == 'T' && cnt == 0) p++;
    }
    *to = p;
    return 1;
}
static uint8_t match_(uint16_t *to)
{
    static const char br[] = "()[]{}";
    uint16_t p = cur, le = lend(cur), n = LEN();
    const char *b;
    char o, c;
    int16_t d = 1;
    while (p < le && !strchr(br, ch(p))) p++;
    if (p >= le) return 0;
    b = strchr(br, ch(p));
    o = *b;
    if ((b - br) & 1) {          /* cierre: hacia atras */
        c = b[-1];
        while (p) { char k = ch(--p); if (k == o) d++; else if (k == c && !--d) { *to = p; return 1; } }
    } else {
        c = b[1];
        while (++p < n) { char k = ch(p); if (k == o) d++; else if (k == c && !--d) { *to = p; return 1; } }
    }
    return 0;
}
/* un movimiento: la nueva pos en *to; *lw de lineas, *inc incluye el final.
   op: hay un operador pendiente (l puede llegar al fin de linea) */
static uint8_t motion(uint8_t c, uint16_t cnt, uint8_t had, uint8_t op, uint16_t *to, uint8_t *lw, uint8_t *inc)
{
    uint16_t p = cur, ls = lstart(cur), le = lend(cur);
    *lw = 0; *inc = 0;
    switch (c) {
    case 'h': case KLEFT: case 8:
        if (p == ls) return 0;
        while (cnt-- && p > ls) p--;
        break;
    case 'l': case KRIGHT: case ' ':
        if (p + (op ? 0 : 1) >= le) return 0;
        while (cnt-- && p + (op ? 0 : 1) < le) p++;
        break;
    case 'j': case KDOWN: case CTRL('N'): case '+': case '\r':
        while (cnt--) { if (nextl(p) >= LEN()) { if (p == cur || lstart(p) == ls) return 0; break; } p = nextl(p); }
        p = (c == '+' || c == '\r') ? firstnb(p) : atcol(p, wantcol);
        *lw = 1;
        break;
    case 'k': case KUP: case CTRL('P'): case '-':
        if (!ls) return 0;
        while (cnt-- && lstart(p)) p = prevl(p);
        p = c == '-' ? firstnb(p) : atcol(lstart(p), wantcol);
        *lw = 1;
        break;
    case '0': case KHOME: p = ls; break;
    case '^': p = firstnb(p); break;
    case '$': case KEND:
        while (--cnt && nextl(p) < LEN()) p = nextl(p);
        le = lend(p);
        p = le > lstart(p) ? le - 1 : le;
        *inc = 1;
        break;
    case 'w': while (cnt--) p = wfwd(p); break;
    case 'W': case 'B': case 'E': return 0;
    case 'b': while (cnt--) p = wback(p); break;
    case 'e': while (cnt--) p = wend(p); *inc = 1; break;
    case 'G':
        p = had ? gotol(cnt) : lastl();
        p = firstnb(p); *lw = 1;
        break;
    case 'g':
        if (getk() != 'g') return 0;
        p = firstnb(gotol(had ? cnt : 1)); *lw = 1;
        break;
    case 'H': case 'L': case 'M': {
        uint8_t r, n = ROWS;
        uint16_t q = top;
        for (r = 1; r < ROWS && nextl(q) < LEN(); r++) q = nextl(q);
        n = r;                    /* filas con texto */
        r = c == 'H' ? (had ? cnt : 1) : c == 'L' ? n + 1 - (had ? cnt : 1) : (n + 1) / 2;
        if (r < 1) r = 1;
        if (r > n) r = n;
        for (q = top; --r; ) q = nextl(q);
        p = firstnb(q); *lw = 1;
        break;
    }
    case 'f': case 'F': case 't': case 'T': {
        uint8_t k = getk();
        if (k == 27) return 0;
        fcmd = c; fch = k;
        if (!findc(c, k, cnt, &p)) return 0;
        *inc = c == 'f' || c == 't';
        break;
    }
    case ';': case ',': {
        char k = fcmd;
        if (!k) return 0;
        if (c == ',') k = k == 'f' ? 'F' : k == 'F' ? 'f' : k == 't' ? 'T' : 't';
        if (!findc(k, fch, cnt, &p)) return 0;
        *inc = k == 'f' || k == 't';
        break;
    }
    case '%': if (!match_(&p)) return 0; *inc = 1; break;
    default: return 0;
    }
    *to = p;
    return 1;
}

/* ---------------------------------------------------------------- busqueda */
static char pat[80], sdir = '/';
static uint8_t search(uint8_t fwd, uint16_t *to)
{
    uint16_t n = LEN(), m = strlen(pat), p = cur, k, i;
    if (!m) { msg("No previous pattern"); return 0; }
    for (k = 0; k < n; k++) {
        if (fwd) { p++; if (p >= n) { p = 0; } }
        else { if (!p) p = n; p--; }
        if (p + m > n) continue;
        for (i = 0; i < m && ch(p + i) == pat[i]; i++) ;
        if (i == m) { *to = p; return 1; }
    }
    msg("Pattern not found");
    return 0;
}

/* ---------------------------------------------------------------- archivos */
static uint8_t rb[128];
static uint8_t loadat(const char *name, uint16_t at, uint16_t *cnt)  /* 0 bien, 1 no esta, 2 grande */
{
    static FCB f;
    uint16_t n = 0;
    if (!mkfcb(&f, name) || fopen(&f)) return 1;
    moveto(at);
    while (!fread(&f, rb)) {
        uint8_t *s = rb, *e = rb + 128;
        char *d = buf + gs, *lim = buf + ge;
        for (; s < e; s++) {
            char c = *s;
            if (c == '\r') continue;
            if (c == 0x1A) { n += d - (buf + gs); gs = d - buf; goto fin; }
            if (d == lim) { n += d - (buf + gs); gs = d - buf; fclose(&f); *cnt = n; return 2; }
            *d++ = c;
        }
        n += d - (buf + gs); gs = d - buf;
    }
fin:
    fclose(&f);
    *cnt = n;
    return 0;
}
static uint8_t save(const char *name)
{
    static FCB f, t;
    static uint8_t rn_[36];
    uint16_t i, n = LEN(), lines = 0;
    uint8_t k = 0, err = 0;
    if (!mkfcb(&f, name)) { msg("Bad file name"); return 0; }
    memcpy(&t, &f, sizeof t);
    memcpy(t.f + 8, "$$$", 3);
    if (fmake(&t)) { msg("Cannot create the file (directory full?)"); return 0; }
    for (i = 0; i <= n && !err; i++) {
        char c = i < n ? ch(i) : 0x1A;
        if (c == '\n') { rb[k++] = '\r'; lines++; if (k == 128) { err = fwrite(&t, rb); k = 0; } }
        rb[k++] = c;
        if (k == 128) { err = fwrite(&t, rb); k = 0; }
    }
    if (k && !err) { while (k < 128) rb[k++] = 0x1A; err = fwrite(&t, rb); }
    fclose(&t);
    if (err) { fdelete(&t); msg("Write error (disk full?): file not written"); return 0; }
    f.ex = 0;
    fdelete(&f);
    memset(rn_, 0, 36);
    memcpy(rn_, &t, 12);
    memcpy(rn_ + 17, f.f, 11);
    bdos(23, (uint16_t)rn_);
    modified = 0;
    ogo(CMDROW, 1); oc('"'); os(name); os("\" "); onum(lines); os(" lines, "); onum(n + lines); os(" bytes written"); oeol();
    msgon = 1;
    return 1;
}
static void info(void)
{
    uint16_t l = lineno(cur), t = nlines();
    ogo(CMDROW, 1); oc('"'); os(*fname_ ? fname_ : "[No name]"); os("\" ");
    if (modified) os("[Modified] ");
    os("line "); onum(l); os(" of "); onum(t); os(" --"); onum((uint16_t)((uint32_t)l * 100 / t)); os("%-- col ");
    onum(colof(cur) + 1); os("   free "); onum(room()); oeol();
    msgon = 1;
}
static void newbuf(void) { gs = 0; ge = bsz; ulen[0] = ulen[1] = 0; uok[0] = uok[1] = 0; }
static void edit(const char *name)
{
    uint16_t n;
    uint8_t r;
    newbuf();
    strncpy(fname_, name, 15);
    r = *name ? loadat(name, 0, &n) : 1;
    if (!LEN() || ch(LEN() - 1) != '\n') { moveto(LEN()); buf[gs++] = '\n'; }
    cur = top = left = 0; modified = 0;
    need = N_ALL;
    if (!*name) return;
    if (r == 1) { ogo(CMDROW, 1); oc('"'); os(name); os("\" [New file]"); oeol(); }
    else if (r == 2) msg("File too large: only the beginning was read. Do not write it back!");
    else { ogo(CMDROW, 1); oc('"'); os(name); os("\" "); onum(nlines()); os(" lines, "); onum(n); os(" chars"); oeol(); }
    msgon = 1;
}

/* ---------------------------------------------------------------- ex */
static uint8_t quit;
static char *skip(char *s) { while (*s == ' ') s++; return s; }
static char *addr(char *s, uint16_t *l, uint8_t *ok)
{
    *ok = 1;
    if (*s == '.') { *l = lineno(cur); return s + 1; }
    if (*s == '$') { *l = nlines(); return s + 1; }
    if (*s >= '0' && *s <= '9') { uint16_t v = 0; while (*s >= '0' && *s <= '9') v = v * 10 + *s++ - '0'; *l = v; return s; }
    *ok = 0;
    return s;
}
static uint16_t subst(uint16_t a, uint16_t b, char *s)   /* s/viejo/nuevo/[g] */
{
    char d = *s++, *o = s, *nw, *e;
    uint16_t lo, ln, l, p, cnt = 0, last = cur;
    uint8_t g = 0;
    while (*s && *s != d) s++;
    if (!*s) return 0xFFFF;
    *s++ = 0; nw = s;
    while (*s && *s != d) s++;
    if (*s) { *s++ = 0; g = *s == 'g'; }
    lo = strlen(o); ln = strlen(nw);
    if (!lo) { if (!*pat) return 0xFFFF; o = pat; lo = strlen(pat); } else strcpy(pat, o);
    p = gotol(a);
    for (l = a; l <= b; l++) {
        uint16_t q = p;
        e = 0;
        for (;;) {
            uint16_t le = lend(p), i;
            for (; q + lo <= le; q++) {
                for (i = 0; i < lo && ch(q + i) == o[i]; i++) ;
                if (i == lo) break;
            }
            if (q + lo > le) break;
            del(q, lo);
            if (!ins(q, nw, ln)) { msg("Out of memory"); return cnt; }
            cnt++; last = q;
            q += ln;
            if (!g) break;
        }
        (void)e;
        if (nextl(p) >= LEN()) break;
        p = nextl(p);
    }
    if (cnt) cur = firstnb(last);
    return cnt;
}
static void excmd(void)
{
    char *s = skip(cl), *a;
    uint16_t l1 = lineno(cur), l2, n;
    uint8_t ok, rng = 0, bang;
    if (*s == '%') { l1 = 1; l2 = nlines(); s++; rng = 1; }
    else {
        s = addr(s, &l1, &ok);
        l2 = l1;
        if (ok) { rng = 1; if (*s == ',') { s = addr(s + 1, &l2, &ok); if (!ok) { msg("Bad range"); return; } } }
    }
    s = skip(s);
    if (!*s) {                   /* :N */
        if (rng) { cur = firstnb(gotol(l2)); }
        return;
    }
    if (l1 > l2) { n = l1; l1 = l2; l2 = n; }
    if (l1 < 1) l1 = 1;
    if (*s == 's' && (s[1] == '/' || s[1] == '#' || s[1] == ',')) {
        ustart();
        n = subst(l1, l2, s + 1);
        if (n == 0xFFFF) msg("Bad substitute");
        else if (!n) msg("Pattern not found");
        else msgn("", n, " substitutions");
        need = N_ALL;
        return;
    }
    if (*s == 'd' && !s[1]) {
        uint16_t pa = gotol(l1), pb = nextl(gotol(l2));
        ustart();
        if (yank(pa, pb, 1)) del(pa, pb - pa);
        if (!LEN()) insc(0, '\n');
        cur = firstnb(pa < LEN() ? pa : lastl());
        need = N_ALL;
        return;
    }
    a = s;
    while (*s && *s != ' ' && *s != '!') s++;
    bang = *s == '!';
    n = s - a;
    if (bang) s++;
    s = skip(s);
    if ((n == 1 && *a == 'w') || (n == 2 && a[0] == 'w' && a[1] == 'q') || (n == 1 && *a == 'x')) {
        uint8_t q = *a == 'x' || n == 2;
        if (*a == 'x' && !modified) { quit = 1; return; }
        if (*s) { if (!*fname_) strncpy(fname_, s, 15); }
        else s = fname_;
        if (!*s) { msg("No file name"); return; }
        if (save(s) && q) quit = 1;
        return;
    }
    if (n == 1 && *a == 'q') {
        if (modified && !bang) { msg("No write since last change (:q! quits anyway)"); return; }
        quit = 1;
        return;
    }
    if (n == 1 && *a == 'e') {
        if (modified && !bang) { msg("No write since last change (:e! discards it)"); return; }
        if (!*s) s = fname_;
        { static char nm[16]; strncpy(nm, s, 15); edit(nm); }
        return;
    }
    if (n == 1 && *a == 'r') {
        uint16_t at = nextl(cur), c;
        uint8_t r;
        if (!*s) { msg("Which file?"); return; }
        ustart();
        r = loadat(s, at, &c);
        if (r == 1) { msg("File not found"); return; }
        ulogop(0, at, c, 0);
        modified = 1;
        if (c && ch(at + c - 1) != '\n') insc(at + c, '\n');
        if (r == 2) msg("Out of memory: only part of the file was read");
        else msgn("", c, " chars read");
        cur = at; need = N_ALL;
        return;
    }
    msg("Unknown command (:w :q :q! :wq :x :e :r :N :d :s)");
}

/* ---------------------------------------------------------------- insertar */
static void insmode(void)
{
    uint8_t c;
    for (;;) {
        if (!pending()) refresh();
        c = getk();
        if (c == 27) break;
        if (c == '\r' || c == '\n') {
            uint16_t p = lstart(cur), i = 0;
            static char ind[40];
            while (i < 39 && isblank(ch(p + i)) && p + i < cur) { ind[i] = ch(p + i); i++; }
            if (!insc(cur, '\n')) { msg("Out of memory"); continue; }
            cur++;
            if (i && ins(cur, ind, i)) cur += i;
            needfrom(lstart(cur - i - 1));
            continue;
        }
        if (c == 8) {
            if (cur > lstart(cur)) { del(--cur, 1); if (!need) need = N_LINE; }
            continue;
        }
        if (c == KDEL) { if (ch(cur) != '\n') { del(cur, 1); if (!need) need = N_LINE; } continue; }
        if (c == KLEFT) { if (cur > lstart(cur)) cur--; continue; }
        if (c == KRIGHT) { if (ch(cur) != '\n') cur++; continue; }
        if (c == KUP || c == KDOWN) {
            uint16_t col = colof(cur), p = lstart(cur);
            if (c == KUP) { if (p) cur = atcol(prevl(p), col); }
            else if (nextl(p) < LEN()) cur = atcol(nextl(p), col);
            continue;
        }
        if (c == KHOME) { cur = lstart(cur); continue; }
        if (c == KEND) { cur = lend(cur); continue; }
        if (c == CTRL('V')) c = getk();
        else if (c < 32 && c != '\t') continue;
        if (c >= 0x80) continue;
        if (!insc(cur, c)) { msg("Out of memory"); continue; }
        cur++;
        if (!need) need = N_LINE;
    }
    if (cur > lstart(cur)) cur--;
}

/* ---------------------------------------------------------------- normal */
static uint16_t count(uint8_t *c, uint8_t *had)
{
    uint16_t n = 0;
    *had = 0;
    while ((*c >= '1' && *c <= '9') || (*had && *c == '0')) {
        n = n * 10 + *c - '0';
        *had = 1;
        *c = getk();
    }
    return *had ? n : 1;
}
static void fixcur(void)
{
    if (cur >= LEN()) cur = lastl();
    if (ch(cur) == '\n' && cur > lstart(cur)) cur--;
}
/* d c y con un movimiento; 1 si cambio algo */
static uint8_t oper(uint8_t o, uint16_t cnt)
{
    uint8_t c = getk(), had, lw, inc;
    uint16_t n, to, a, b;
    n = cnt * count(&c, &had);
    if (c == o) {                /* dd cc yy */
        a = lstart(cur); b = a;
        while (n-- && b < LEN()) b = nextl(b);
        lw = 1;
    } else {
        if (o == 'c' && c == 'w' && cls(ch(cur)))   /* cw es ce (en la ultima letra, solo esa) */
            c = n == 1 && cls(ch(cur + 1)) != cls(ch(cur)) ? 'l' : 'e';
        if (!motion(c, n, had, 1, &to, &lw, &inc)) return 0;
        if (lw) {
            a = lstart(cur < to ? cur : to);
            b = nextl(cur < to ? to : cur);
        } else {
            a = cur < to ? cur : to;
            b = (cur < to ? to : cur) + inc;
            if (c == 'w' && to > cur && lstart(to) != lstart(cur) && lend(cur) > cur) b = lend(cur);
            if (b > a && ch(b - 1) == '\n' && inc) b--;
        }
    }
    if (o == 'y') {
        yank(a, b, lw);
        if (!lw) cur = a;
        return 0;
    }
    ustart();
    if (!yank(a, b, lw)) return 0;
    if (o == 'c' && lw) {        /* cc: queda una linea vacia (con la sangria) */
        uint16_t f = a;
        while (isblank(ch(f))) f++;
        del(f, b - 1 - f);
        cur = f;
        needfrom(a);
        insmode();
        return 1;
    }
    del(a, b - a);
    if (!LEN()) insc(0, '\n');
    cur = a;
    if (lw) { if (cur >= LEN()) cur = lastl(); cur = firstnb(cur); need = N_ALL; }
    else needfrom(a);
    if (o == 'c') insmode();
    return 1;
}
static void put(uint8_t after, uint16_t cnt)
{
    uint16_t at, i;
    if (!ylen) return;
    ustart();
    if (ylw) at = after ? nextl(cur) : lstart(cur);
    else at = after && ch(cur) != '\n' ? cur + 1 : cur;
    for (i = 0; i < cnt; i++)
        if (!ins(at + i * ylen, ybuf, ylen)) { msg("Out of memory"); break; }
    cur = ylw ? firstnb(at) : at + i * ylen - 1;
    needfrom(at);
    if (ylw) need = N_ALL;
}
static void undo(void)
{
    uint8_t old = ucur;
    uint8_t *l = ulog[old];
    uint16_t u = ulen[old], pos = cur;
    if (!uok[old] || !u) { msg(uok[old] ? "Nothing to undo" : "Cannot undo (change too large)"); return; }
    ucur ^= 1;
    ustart();
    while (u) {
        uint16_t sz = l[u - 2] | (l[u - 1] << 8), p, n;
        uint8_t *e = l + u - sz;
        p = e[1] | (e[2] << 8); n = e[3] | (e[4] << 8);
        if (e[0]) ins(p, (char *)e + 5, n);
        else del(p, n);
        pos = p;
        u -= sz;
    }
    ulen[old] = 0;
    cur = pos;
    need = N_ALL;
}
static void join(uint16_t cnt)
{
    if (cnt < 2) cnt = 2;
    ustart();
    while (--cnt) {
        uint16_t e = lend(cur), f;
        if (e + 1 >= LEN()) break;
        f = e + 1;
        while (isblank(ch(f))) f++;
        del(e, f - e);
        if (ch(e) != '\n' && ch(e) != ')' && e > lstart(e) && !isblank(ch(e - 1))) insc(e, ' ');
        cur = e;
    }
    needfrom(cur);
}
static void scroll(uint8_t down, uint8_t n)
{
    while (n--) {
        if (down) { if (nextl(top) < LEN()) { top = nextl(top); if (lstart(cur) < top) cur = top; } }
        else if (top) { top = prevl(top); }
    }
    { uint16_t q = top; uint8_t r;
      for (r = 1; r < ROWS && nextl(q) < LEN(); r++) q = nextl(q);
      if (lstart(cur) > q) cur = q; }
    cur = firstnb(cur);
    need = N_ALL;
}

void main(void)
{
    char *p = args(), *a = nextarg(&p);
    uint16_t hi = *(uint16_t *)6 - 1024;
    buf = heap;
    if ((uint16_t)heap >= hi - 2048) { pstr("Not enough memory\n"); return; }
    bsz = hi - (uint16_t)heap;
    bdos(45, 0xFF);              /* los errores del BDOS vuelven, no terminan */
    pstr(CLS);
    edit(a ? a : "");
    while (!quit) {
        uint8_t c, had, chg = 0, lw, inc;
        uint16_t n, to;
        refresh();
        nk = 0; rec = 1; recbad = 0;
        c = getk();
        if (msgon) { ogo(CMDROW, 1); oeol(); msgon = 0; }
        n = count(&c, &had);
        switch (c) {
        case 'i': case 'a': case 'I': case 'A': case 'o': case 'O':
            ustart();
            if (c == 'a' && ch(cur) != '\n') cur++;
            else if (c == 'I') cur = firstnb(cur);
            else if (c == 'A') cur = lend(cur);
            else if (c == 'o' || c == 'O') {
                uint16_t ls = lstart(cur), i = 0, at = c == 'o' ? nextl(cur) : ls;
                static char ind[40];
                while (i < 39 && isblank(ch(ls + i))) { ind[i] = ch(ls + i); i++; }
                if (!insc(at, '\n')) { msg("Out of memory"); break; }
                if (i) ins(at, ind, i);
                cur = at + i;
                needfrom(at);
            }
            insmode();
            chg = 1;
            break;
        case 'x': case KDEL: case 'X': {
            uint16_t ls = lstart(cur), le = lend(cur), a2 = cur, b2 = cur;
            if (c == 'X') { while (n-- && a2 > ls) a2--; }
            else { while (n-- && b2 < le) b2++; }
            if (a2 == b2) break;
            ustart();
            yank(a2, b2, 0);
            del(a2, b2 - a2);
            cur = a2;
            need = need ? need : N_LINE;
            chg = 1;
            break;
        }
        case 'r': {
            uint8_t k = getk();
            uint16_t le = lend(cur);
            if (k == 27 || cur + n > le) break;
            ustart();
            del(cur, n);
            if (k == '\r') { insc(cur, '\n'); cur++; needfrom(cur - 1); }
            else { uint16_t i; for (i = 0; i < n; i++) insc(cur + i, k); cur += n - 1; if (!need) need = N_LINE; }
            chg = 1;
            break;
        }
        case '~': {
            uint16_t le = lend(cur);
            ustart();
            while (n-- && cur < le) {
                char k = ch(cur);
                if (k >= 'a' && k <= 'z') k -= 32; else if (k >= 'A' && k <= 'Z') k += 32;
                if (k != ch(cur)) { del(cur, 1); insc(cur, k); }
                if (cur + 1 < le) cur++; else break;
            }
            if (!need) need = N_LINE;
            chg = 1;
            break;
        }
        case 'd': case 'c': case 'y': chg = oper(c, n); break;
        case 'D': case 'C': inj = '$'; chg = oper(c == 'D' ? 'd' : 'c', n); break;
        case 's': inj = 'l'; chg = oper('c', n); break;
        case 'S': inj = 'c'; chg = oper('c', n); break;
        case 'Y': inj = 'y'; oper('y', n); break;
        case 'p': case 'P': put(c == 'p', n); chg = 1; break;
        case 'J': join(had ? n : 2); chg = 1; break;
        case 'u': undo(); break;
        case '.':
            if (dotn) { rp = dotk; rn = dotn; nk = 0; rec = 0; }
            continue;
        case '/': case '?':
            if (readline(c)) {
                if (*cl) strcpy(pat, cl);
                sdir = c;
                if (search(c == '/', &to)) cur = to;
                wantcol = colof(cur);
            }
            break;
        case 'n': case 'N': {
            uint8_t fwd = sdir != '?';
            if (c == 'N') fwd = !fwd;
            if (search(fwd, &to)) cur = to;
            break;
        }
        case ':':
            if (readline(':')) { excmd(); if (quit) break; }
            break;
        case 'Z':
            if (getk() == 'Z') {
                if (modified) { if (!*fname_) { msg("No file name"); break; } if (!save(fname_)) break; }
                quit = 1;
            }
            break;
        case CTRL('G'): info(); break;
        case CTRL('L'): pstr(CLS); need = N_ALL; break;
        case CTRL('F'): case KPGDN: scroll(1, (ROWS - 2) * n); break;
        case CTRL('B'): case KPGUP: scroll(0, (ROWS - 2) * n); break;
        case CTRL('D'): scroll(1, ROWS / 2); break;
        case CTRL('U'): scroll(0, ROWS / 2); break;
        case CTRL('E'): scroll(1, n); break;
        case CTRL('Y'): scroll(0, n); break;
        case 27: break;
        default:
            if (motion(c, n, had, 0, &to, &lw, &inc)) {
                cur = to;
                if (!lw) wantcol = colof(cur);
            } else if (c) oc(7);
        }
        fixcur();
        if (chg) {
            if (!recbad && nk) { memcpy(dotk, curk, nk); dotn = nk; }
            wantcol = colof(cur);
        }
        rec = 0;
    }
    ogo(CMDROW, 1); oeol();
    oflush();
    pstr("\r");
}
