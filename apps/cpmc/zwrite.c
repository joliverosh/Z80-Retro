/* ZWRITE - procesador de texto para CP/M 2.2, CP/M 3 y MP/M II (terminal ANSI de
   80 columnas, UTF-8): escribe Markdown con las teclas de WordStar
   ZWRITE archivo        edita (los parrafos se parten entre palabras en la pantalla)
   ZWRITE -V archivo     solo la vista formateada
   Teclas: el diamante ^E ^X ^S ^D, ^A ^F palabras, ^R ^C paginas, ^G ^T ^Y borrar,
   ^V sobreescribir, ^N partir, ^U deshacer, ^Q (lugares, buscar, reemplazar),
   ^K (bloques, archivos, imprimir), ^O D vista, ^P B Y negrita y cursiva, ^J ayuda.
   Imprime justificado, con paginas, encabezado y numeros, en la impresora o en un
   .PRN. Sale de MD (el editor de Markdown) y comparte su forma de dibujar.
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include <string.h>
#include "cpm.h"

#define W 80                     /* columnas */
#define ROWS 21                  /* filas de texto */
#define STROW 22                 /* la barra de estado */
#define MSGROW 23                /* ayuda y mensajes */
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
static uint16_t bsz, gs, ge;
static uint8_t modified;
static uint16_t bb, be;                  /* el bloque (^KB ^KK): [bb, be) */
static uint8_t bhide;
#define LEN() (bsz - (ge - gs))
static uint8_t ch(uint16_t i) { return i < gs ? buf[i] : buf[i + (ge - gs)]; }
static void moveto(uint16_t p)
{
    if (p < gs) { uint16_t n = gs - p; memmove(buf + ge - n, buf + p, n); gs = p; ge -= n; }
    else if (p > gs) { uint16_t n = p - gs; memmove(buf + gs, buf + ge, n); gs += n; ge += n; }
}

/* deshacer: un registro de operaciones con marcas de grupo; si se llena se
   olvidan las mas viejas. Entrada: tipo (0 ins, 1 del, 2 marca), pos, n,
   [texto borrado] */
#define ULOG 1500
static uint8_t ulog[ULOG];
static uint16_t ulen;
static uint8_t undoing;
static uint16_t esz(uint8_t *e) { return 5 + (e[0] == 1 ? (e[3] | (e[4] << 8)) : 0); }
static void ulogop(uint8_t t, uint16_t p, uint16_t n)
{
    uint16_t sz = 5 + (t == 1 ? n : 0), i;
    uint8_t *e;
    if (undoing) return;
    if (sz > ULOG) { ulen = 0; return; }
    while (ulen + sz > ULOG) {                 /* fuera lo mas viejo */
        uint16_t s = esz(ulog);
        memmove(ulog, ulog + s, ulen - s);
        ulen -= s;
    }
    e = ulog + ulen;
    e[0] = t; e[1] = p; e[2] = p >> 8; e[3] = n; e[4] = n >> 8;
    if (t == 1) for (i = 0; i < n; i++) e[5 + i] = ch(p + i);
    ulen += sz;
}
static uint8_t lastmark(void)          /* la ultima entrada es una marca? */
{
    uint16_t o = 0, l = 0xFFFF;
    while (o < ulen) { l = o; o += esz(ulog + o); }
    return l == 0xFFFF || ulog[l] == 2;
}
static void ugroup(void) { if (!lastmark()) ulogop(2, 0, 0); }
static uint16_t room(void) { return ge - gs; }
static uint8_t ins(uint16_t p, const char *s, uint16_t n)
{
    if (n > room()) return 0;
    moveto(p);
    memcpy(buf + gs, s, n);
    gs += n;
    ulogop(0, p, n);
    if (bb > p) bb += n;
    if (be > p) be += n;
    modified = 1;
    return 1;
}
static uint8_t insc(uint16_t p, char c) { return ins(p, &c, 1); }
static void del(uint16_t p, uint16_t n)
{
    if (!n) return;
    ulogop(1, p, n);
    moveto(p);
    ge += n;
    if (bb > p) bb = bb >= p + n ? bb - n : p;
    if (be > p) be = be >= p + n ? be - n : p;
    modified = 1;
}

/* ---------------------------------------------------------------- lineas */
static uint16_t lstart(uint16_t p) { while (p && ch(p - 1) != '\n') p--; return p; }
static uint16_t lend(uint16_t p) { uint16_t n = LEN(); while (p < n && ch(p) != '\n') p++; return p; }
static uint16_t nextl(uint16_t p) { uint16_t e = lend(p); return e < LEN() ? e + 1 : e; }
static uint16_t prevl(uint16_t p) { p = lstart(p); return p ? lstart(p - 1) : 0; }
static uint16_t lastl(void) { return lstart(LEN() - 1); }
static uint16_t lineno(uint16_t p) { uint16_t i, n = 1; for (i = 0; i < p; i++) if (ch(i) == '\n') n++; return n; }
static uint16_t nlines(void) { return lineno(LEN() - 1); }
static uint16_t gotol(uint16_t n) { uint16_t p = 0, l = lastl(); while (--n && p < l) p = nextl(p); return p; }
static uint8_t cont(uint8_t c) { return (c & 0xC0) == 0x80; }   /* resto de un UTF-8 */
/* columnas de la palabra que empieza en p (hasta un espacio o el fin de la linea) */
static uint8_t wordw(uint16_t p)
{
    uint8_t n = 0, c;
    uint16_t e = LEN();
    while (p < e && (c = ch(p)) != ' ' && c != '\n' && n < W) { if (!cont(c)) n++; p++; }
    return n;
}
/* la columna despues del byte en p (las columnas siguen de una fila a la otra).
   Despues de un espacio, si la palabra siguiente no cabe en la fila, salta a la
   otra (las lineas se parten entre palabras) */
static uint16_t adv(uint16_t col, uint16_t p)
{
    uint8_t c = ch(p), w;
    if (c == '\t') return (col | 7) + 1;
    if (cont(c)) return col;
    if (c < 32 || c == 127) { if (col % W == W - 1) col++; return col + 2; }
    col++;
    if (c == ' ' && col % W && (w = wordw(p + 1)) && w < W && col % W + w > W) col += W - col % W;
    return col;
}
static uint16_t colat(uint16_t ls, uint16_t p) { uint16_t c = 0; for (; ls < p; ls++) c = adv(c, ls); return c; }
static uint8_t height(uint16_t ls) { return colat(ls, lend(ls)) / W + 1; }
/* la pos de la linea ls mas cerca de la columna col */
static uint16_t atcol(uint16_t ls, uint16_t col)
{
    uint16_t c = 0, e = lend(ls);
    while (ls < e) {
        uint16_t n = ls + 1, nc;
        while (n < e && cont(ch(n))) n++;
        nc = c; { uint16_t k; for (k = ls; k < n; k++) nc = adv(nc, k); }
        if (nc > col || (nc / W != c / W && nc % W && col < nc - nc % W)) break;
        c = nc; ls = n;
    }
    return ls;
}
static uint16_t left1(uint16_t p) { if (p) { p--; while (p && cont(ch(p))) p--; } return p; }
static uint16_t right1(uint16_t p) { uint16_t n = LEN(); if (p < n) { p++; while (p < n && cont(ch(p))) p++; } return p; }

/* ---------------------------------------------------------------- pantalla */
#define oc(c) putch(c)
static void os(const char *s) { while (*s) oc(*s++); }
static void onum(uint16_t v) { char b[6]; uint8_t n = 0; do b[n++] = '0' + v % 10; while (v /= 10); while (n) oc(b[--n]); }
static void ogo(uint8_t r, uint8_t c) { oc(27); oc('['); onum(r); oc(';'); onum(c); oc('H'); }
static void oeol(void) { os("\x1b[K"); }
static void sgr(const char *s) { oc(27); oc('['); os(s); oc('m'); }
/* corre las filas de texto una hacia arriba (up) o abajo, sin tocar las de
   abajo (la barra, la ayuda y la linea de estado de MP/M) */
static void scrl(uint8_t up)
{
    os("\x1b[1;21r\x1b[1;1H");
    os(up ? "\x1b[M" : "\x1b[L");
    os("\x1b[r");
}

static uint16_t tl, cur, wantcol, ltop;   /* tl: linea de arriba; ts: su fila */
static uint8_t ts, need, frow, crow, ccol, msgon, stdirty;
static uint8_t topfence;                  /* tl esta dentro de un bloque de codigo */
#define N_NONE 0
#define N_LINE 1
#define N_FROM 2
#define N_ALL 3
static char fname_[16];


/* ---- el marcado de Markdown (para editar y para la vista) */
static uint8_t isfence(uint16_t ls)
{
    uint8_t i = 0;
    while (i < 3 && ch(ls) == ' ') { ls++; i++; }
    return ch(ls) == '`' && ch(ls + 1) == '`' && ch(ls + 2) == '`';
}
static uint8_t fenceat(uint16_t ls)       /* ls esta dentro de un bloque ``` */
{
    uint16_t p = 0;
    uint8_t f = 0;
    if (ls >= ltop) { p = ltop; f = topfence; }
    while (p < ls) { if (isfence(p)) f ^= 1; p = nextl(p); }
    return f;
}
static uint8_t hlevel(uint16_t ls)        /* # al principio: el nivel */
{
    uint8_t n = 0;
    while (ch(ls + n) == '#' && n < 7) n++;
    return n && n <= 6 && (ch(ls + n) == ' ' || ch(ls + n) == '\n' || ls + n >= LEN()) ? n : 0;
}
/* largo de la marca de lista ("- ", "* ", "+ ", "12. ") despues de la sangria */
static uint8_t listmark(uint16_t p)
{
    uint8_t c = ch(p), n = 0;
    if ((c == '-' || c == '*' || c == '+') && ch(p + 1) == ' ') return 2;
    while (ch(p + n) >= '0' && ch(p + n) <= '9' && n < 4) n++;
    if (n && (ch(p + n) == '.' || ch(p + n) == ')') && ch(p + n + 1) == ' ') return n + 2;
    return 0;
}
static uint8_t isrule(uint16_t ls)
{
    uint8_t c = ch(ls), n = 0;
    uint16_t e = lend(ls);
    if (c != '-' && c != '*' && c != '_') return 0;
    for (; ls < e; ls++) { if (ch(ls) == c) n++; else if (ch(ls) != ' ') return 0; }
    return n >= 3;
}

/* ---- dibujar una linea de la edicion, desde su fila 'desde' (0..) */
static const char *hcol[6] = {"1;33", "1;36", "1;32", "1;35", "1;35", "1;35"};
static uint8_t vrow, vfirst, vrow0;       /* fila de pantalla de la linea */
static uint16_t vcol;
static const char *vstyle;
static uint8_t vb, vi, vc, vl, vu, vk;   /* negrita, cursiva, codigo, enlace, url, bloque */
static void vsgr(void)
{
    oc(27); oc('['); oc('0');
    if (vstyle) { oc(';'); os(vstyle); }
    if (vb) os(";1");
    if (vi) os(";4");
    if (vc) os(";32");
    if (vl) os(";34;4");
    if (vu) os(";2");
    if (vk) os(";7");
    oc('m');
}
static uint8_t vis(void) { return vrow >= vfirst && vrow0 + vrow - vfirst <= ROWS && vrow0 + vrow - vfirst >= 1; }
static uint8_t inblk(uint16_t p) { return !bhide && bb < be && p >= bb && p < be; }
static void vput(uint16_t p, uint8_t sty)  /* el byte en p, con la columna */
{
    uint8_t c = ch(p), k = inblk(p);
    uint16_t nc = adv(vcol, p);
    if (k != vk) { vk = k; sty = 1; }
    if (c < 32 || c == 127) {
        if (vcol % W == W - 1) { if (vis()) oc(' '); vcol++; }
    }
    if (!cont(c) && c != '\t' && vcol && vcol % W == 0 && vcol / W != vrow) {
        vrow = vcol / W;
        if (vis()) { ogo(vrow0 + vrow - vfirst, 1); vsgr(); }
    }
    if (c == '\t') {
        while (vcol < nc) {
            if (vcol % W == 0 && vcol / W != vrow) { vrow = vcol / W; if (vis()) { ogo(vrow0 + vrow - vfirst, 1); vsgr(); } }
            if (vis()) oc(' ');
            vcol++;
        }
        return;
    }
    if (vis()) {
        if (sty) vsgr();
        if (c < 32 || c == 127) { oc('^'); oc(c == 127 ? '?' : c + 64); }
        else oc(c);
        if (nc % W == 0 && nc - vcol > 1) oeol();   /* la palabra siguiente va abajo */
    }
    vcol = nc;
}
/* dibuja la linea ls en la fila r0 de la pantalla, desde su fila 'desde'; devuelve
   cuantas filas de pantalla uso (de las visibles) */
static uint8_t drawline(uint16_t ls, uint8_t r0, uint8_t desde, uint8_t fence)
{
    uint16_t p = ls, e = lend(ls);
    uint8_t h, lv, q;
    vrow = 0; vfirst = desde; vrow0 = r0; vcol = 0;
    vb = vi = vc = vl = vu = vk = 0;
    vstyle = 0;
    if (fence || isfence(ls)) vstyle = "32";
    else if ((lv = hlevel(ls))) vstyle = hcol[lv - 1];
    else if (ch(ls) == '>') vstyle = "36";
    else if (isrule(ls)) vstyle = "2";
    if (vis()) { ogo(r0, 1); vsgr(); }
    if (!vstyle) {                       /* la marca de lista, en color */
        while (p < e && ch(p) == ' ') vput((p++), 0);
        if ((q = listmark(p))) {
            vstyle = "33"; vput((p), 1);
            while (--q) vput((++p), 0);
            p++;
            vstyle = 0; vsgr();
        }
    }
    for (; p < e; p++) {
        uint8_t c = ch(p), s = 0;
        if (!fence && !isfence(ls)) {
            if (c == '\\' && p + 1 < e) { vput(p, 0); vput((++p), 0); continue; }
            if (c == '`') { if (!vc) { vc = 1; s = 1; } else { vput(p, 0); vc = 0; vsgr(); continue; } }
            else if (!vc) {
                if ((c == '*' || c == '_') && ch(p + 1) == c) {
                    if (!vb) { vb = 1; vput(p, 1); vput((++p), 0); continue; }
                    vput(p, 0); vput((++p), 0); vb = 0; vsgr(); continue;
                }
                if (c == '*' || (c == '_' && (p == ls || !((ch(p - 1) | 32) >= 'a' && (ch(p - 1) | 32) <= 'z')))) {
                    if (!vi && p + 1 < e && ch(p + 1) != ' ') { vi = 1; s = 1; }
                    else if (vi) { vput(p, 0); vi = 0; vsgr(); continue; }
                }
                else if (c == '[' && !vl) { vl = 1; s = 1; }
                else if (c == ']' && vl) { vput(p, 0); vl = 0; if (ch(p + 1) == '(') vu = 1; vsgr(); continue; }
                else if (c == ')' && vu) { vput(p, 0); vu = 0; vsgr(); continue; }
            }
        }
        vput(p, s);
    }
    h = vcol / W + 1;
    if (vrow != h - 1) { vrow = h - 1; if (vis()) ogo(vrow0 + vrow - vfirst, 1); }
    if (vis()) { sgr("0"); oeol(); }
    {   /* filas dibujadas */
        int16_t n = (int16_t)h - desde;
        if (n < 0) n = 0;
        if (r0 + n - 1 > ROWS) n = ROWS - r0 + 1;
        return n;
    }
}

static uint8_t mode;                      /* 0 editar, 1 vista */
static uint8_t viewonly;
static const char *const help = "^K block/file  ^Q quick  ^O view  ^P bold/italic  ^U undo  ^J help";
static uint8_t ovr;                       /* ^V: sobreescribir */
static void msg(const char *s) { ogo(MSGROW, 1); sgr("0"); os(s); oeol(); msgon = 1; }
static void showhelp(void) { ogo(MSGROW, 1); sgr("2"); os(help); sgr("0"); oeol(); msgon = 0; }
static void status(void)
{
    ogo(STROW, 1); sgr("7");
    os(" ZWRITE  "); os(*fname_ ? fname_ : "[no name]");
    if (modified) os(" [modified]");
    if (ovr) os("  OVERTYPE");
    if (bb < be && !bhide) os("  BLOCK");
    os("\x1b[K");
    sgr("0");
    stdirty = 0;
}
static void statpos(void)
{
    uint16_t l = lineno(cur);
    ogo(STROW, 58); sgr("7");
    os("line "); onum(l); os(", col "); onum(colat(lstart(cur), cur) + 1); os("      ");
    ogo(STROW, 44); onum(room()); os(" free ");
    ogo(STROW, 80); oc(' ');
    sgr("0");
}
/* filas de pantalla de (l, s) a la linea de p (o 0xFF si p esta antes o muy lejos) */
static uint8_t rowsto(uint16_t p, uint8_t sub)
{
    uint16_t l = tl;
    uint8_t r = 1;
    int16_t rr;
    if (p < tl || (p == tl && sub < ts)) return 0xFF;
    rr = 1 - ts;
    while (l < p) { rr += height(l); l = nextl(l); if (rr > ROWS + 40) return 0xFE; }
    rr += sub;
    r = rr > 250 ? 250 : rr;
    return r;
}
static void back1(void) { if (ts) ts--; else if (tl) { tl = prevl(tl); ts = height(tl) - 1; } }
static void fwd1(void) { if (ts + 1 < height(tl)) ts++; else if (nextl(tl) < LEN()) { tl = nextl(tl); ts = 0; } }
static void setltop(void)
{
    uint16_t p = 0;
    uint8_t f = 0;
    if (tl >= ltop) { p = ltop; f = topfence; }
    while (p < tl) { if (isfence(p)) f ^= 1; p = nextl(p); }
    ltop = tl; topfence = f;
}
static void adjust(void)
{
    uint16_t ls = lstart(cur);
    uint8_t sub = colat(ls, cur) / W, r;
    r = rowsto(ls, sub);
    if (r == 0xFF) {
        uint16_t ol = tl; uint8_t os_ = ts;
        back1();
        if (tl == ls && ts == sub && need != N_ALL && !(ol == tl && os_ == ts)) {
            setltop();
            scrl(0);
            drawline(tl, 1, ts, fenceat(tl));
            if (need == N_FROM) frow++;
        } else {
            tl = ls; ts = sub;
            for (r = 0; r < ROWS / 3; r++) back1();
            need = N_ALL;
        }
        r = rowsto(ls, sub);
    } else if (r > ROWS) {
        if (r == ROWS + 1 && need != N_ALL) {
            fwd1();
            setltop();
            scrl(1);
            if (need == N_FROM && frow > 1) frow--;
            r = ROWS;
            drawline(ls, ROWS, sub, fenceat(ls));
        } else {
            tl = ls; ts = sub;
            for (r = 0; r < ROWS * 2 / 3; r++) back1();
            need = N_ALL;
        }
        r = rowsto(ls, sub);
    }
    crow = r;
    ccol = colat(ls, cur) % W + 1;
}
static void redraw(uint8_t from)
{
    uint16_t l = tl;
    uint8_t r = 1, f, sub = ts;
    setltop();
    f = topfence;
    while (r <= ROWS && l < LEN()) {
        uint8_t h = height(l) - sub, n;
        if (r + h - 1 >= from) {
            uint8_t d = sub + (r < from ? from - r : 0);
            n = drawline(l, r + (d - sub), d, f);
            (void)n;
        }
        if (isfence(l)) f ^= 1;
        r += h; sub = 0;
        l = nextl(l);
    }
    for (; r <= ROWS; r++) if (r >= from) { ogo(r, 1); sgr("2"); oc('~'); sgr("0"); oeol(); }
}
static void refresh(void)
{
    adjust();
    if (need == N_ALL) { redraw(1); stdirty = 1; if (!msgon) showhelp(); }
    else if (need == N_FROM) redraw(frow);
    else if (need == N_LINE) {
        uint16_t ls = lstart(cur);
        uint8_t sub = colat(ls, cur) / W, d;
        d = sub && crow > 1 ? sub - 1 : sub;   /* desde la fila anterior: algo puede volver arriba */
        drawline(ls, crow - (sub - d), d, fenceat(ls));
    }
    need = N_NONE;
    if (stdirty) status();
    statpos();
    ogo(crow, ccol);
}
static void needfrom(uint16_t p)
{
    uint8_t r = rowsto(lstart(p), 0);
    if (r == 0xFF || r == 0xFE) { need = N_ALL; return; }
    if (r < 1) r = 1;
    if (need == N_ALL || (need == N_FROM && frow < r)) return;
    need = N_FROM; frow = r;
}

/* ---------------------------------------------------------------- teclado */
static uint8_t pb[2], npb;
static uint8_t rawk(void)
{
    int k;
    if (npb) return pb[--npb];
    while (!(k = getkey())) delay(1);
    return k;
}
/* hay una tecla esperando? Se lee (BDOS 6 FF) y se guarda: BDOS 11, y el
   6 FE de CP/M 3 (que MP/M II no tiene), no sirven */
static uint8_t pending(void)
{
    uint8_t k;
    if (npb) return 1;
    if ((k = getkey())) { pb[npb++] = k; return 1; }
    return 0;
}
static uint8_t soon(void)
{
    uint8_t n, k = 0;
    for (n = 0; n < 60 && !(k = getkey()); n++) ;
    return k;
}
static uint8_t key(void)
{
    uint8_t k = rawk(), k2;
    if (k != 27) return k == 127 ? 8 : k;
    k2 = soon();
    if (k2 != '[' && k2 != 'O') { if (k2) pb[npb++] = k2; return 27; }
    k = soon();
    if (k2 == 'O' && !(k >= 'A' && k <= 'D') && k != 'H' && k != 'F') {
        if (k) pb[npb++] = k;
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
static char cl[80];
static uint8_t readline(const char *prompt)
{
    uint8_t n = strlen(cl), c;
    ogo(MSGROW, 1); sgr("0"); os(prompt); os(cl); oeol();
    msgon = 1;
    for (;;) {
        c = key();
        if (c == 27 || c == CTRL('C')) { showhelp(); return 0; }
        if (c == '\r' || c == '\n') break;
        if (c == 8) { if (n) { n--; os("\b \b"); } }
        else if (c >= 32 && c < 0xFE && n < 70) { cl[n++] = c; oc(c); }
    }
    cl[n] = 0;
    return 1;
}

/* ---------------------------------------------------------------- archivos */
static uint8_t rb[1024];               /* 8 registros por llamada al BDOS */
static uint8_t loadat(const char *name, uint16_t *cnt)
{
    static FCB f;
    uint16_t n = 0;
    if (!mkfcb(&f, name) || fopen(&f)) return 1;
    moveto(0);
    uint8_t g;
    while ((g = freadn(&f, rb, 8))) {
        uint8_t *s = rb, *e = rb + ((uint16_t)g << 7);
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
    uint16_t k = 0;
    uint8_t err = 0;
    if (!mkfcb(&f, name)) { msg("Bad file name"); return 0; }
    memcpy(&t, &f, sizeof t);
    memcpy(t.f + 8, "$$$", 3);
    if (fmake(&t)) { msg("Cannot create the file (directory full?)"); return 0; }
    for (i = 0; i <= n && !err; i++) {
        uint8_t c = i < n ? ch(i) : 0x1A;
        if (c == '\n') { rb[k++] = '\r'; lines++; if (k == 1024) { err = fwriten(&t, rb, 8); k = 0; } }
        rb[k++] = c;
        if (k == 1024) { err = fwriten(&t, rb, 8); k = 0; }
    }
    if (k && !err) { while (k & 127) rb[k++] = 0x1A; err = fwriten(&t, rb, k >> 7); }
    fclose(&t);
    if (err) { fdelete(&t); msg("Write error (disk full?): file not written"); return 0; }
    fdelete(&f);
    memset(rn_, 0, 36);
    memcpy(rn_, &t, 12);
    memcpy(rn_ + 17, f.f, 11);
    bdos(23, (uint16_t)rn_);
    modified = 0;
    stdirty = 1;
    ogo(MSGROW, 1); sgr("0"); oc('"'); os(name); os("\" "); onum(lines); os(" lines written"); oeol();
    msgon = 1;
    return 1;
}

/* ---------------------------------------------------------------- vista */
/* La vista va escribiendo filas; solo se ven las de pvtop a pvtop+ROWS-1.
   Imprimir (prn) usa lo mismo: cada fila se junta en plb y pnl la manda a la
   impresora o al archivo, justificada si es una fila partida de un parrafo */
static uint8_t vw = W;                    /* el ancho: W en pantalla, pw al imprimir */
static uint8_t prn;                       /* imprimiendo */
static void psg(const char *s) { if (!prn) sgr(s); }
static const char *u8(const char *u, const char *a) { return prn ? a : u; }
static void prnline(void);
static void pch(uint8_t c);
static void dotcmd(uint16_t p, uint16_t e);
static uint8_t pjust;                     /* la fila que termina se parte: justificar */
static uint16_t pvtop, pvrow, pvcol;
static uint8_t pvind;                     /* sangria de las filas siguientes */
static const char *pvpre;                 /* prefijo de cada fila (citas) */
static uint8_t pb_, pi_, pc_, pl_, pu_, ph;   /* estilos y nivel de titulo */
static uint8_t pvlo, pvhi = ROWS - 1;      /* las filas de la ventana que se dibujan */
static uint8_t pvcount;                  /* solo contar filas */
static uint8_t pvis(void) { return !prn && !pvcount && pvrow >= pvtop + pvlo && pvrow <= pvtop + pvhi; }
static uint8_t plb[200], pls[200], pln;   /* la fila que se imprime: letras y estilos */
static void psgr(void)
{
    if (prn) return;
    if (!pvis()) return;
    oc(27); oc('['); oc('0');
    if (ph == 1) os(";1;33"); else if (ph == 2) os(";1;36"); else if (ph) os(";1");
    if (pb_) os(";1");
    if (pi_) os(";3");
    if (pc_) os(";32");
    if (pl_) os(";34;4");
    if (pu_) os(";2");
    oc('m');
}
static void pnl(void)                     /* fila nueva */
{
    if (prn && pvrow != 0xFFFF) prnline();
    pjust = 0;
    if (pvis()) { psg("0"); if (pvcol < vw) oeol(); }   /* (con 80, ESC[K borraria la ultima) */
    pvrow++;
    pvcol = 0;
    if (pvis()) ogo(pvrow - pvtop + 1, 1);
    if (pvpre) { if (prn) { pch(pvpre[0]); pch(' '); } else { if (pvis()) { psg("36"); os(pvpre); } pvcol = 2; } }
    while (pvcol < pvind) { if (prn) pch(' '); else { if (pvis()) oc(' '); pvcol++; } }
    psgr();
}
static void pch(uint8_t c)
{
    if (prn) { if (pln < sizeof plb) { plb[pln] = c; pls[pln++] = (pb_ || ph) | pi_ << 1; } }
    else if (pvis()) oc(c);
    if (!cont(c)) pvcol++;
}
static void pstr_(const char *s) { while (*s) pch(*s++); }
/* palabras: se juntan en wbuf (bytes y marcas de estilo 1-8) y se parten a vw */
static uint8_t wbuf[120], wn, ww, wsp;
static void wflush(void)
{
    uint8_t i;
    if (!wn) return;
    if (pvcol + (wsp && pvcol > pvind ? 1 : 0) + ww > vw && pvcol > pvind) { pjust = 1; pnl(); }
    else if (wsp && pvcol > pvind && (!pvpre || pvcol > 2)) pch(' ');
    for (i = 0; i < wn; i++) {
        uint8_t c = wbuf[i];
        if (c < 9) {
            switch (c) {
            case 1: pb_ ^= 1; break;
            case 2: pi_ ^= 1; break;
            case 3: pc_ ^= 1; break;
            case 4: pl_ = 1; break;
            case 5: pl_ = 0; break;
            case 6: pu_ = 1; break;
            case 7: pu_ = 0; break;
            }
            psgr();
        } else {
            if (pvcol >= vw) pnl();
            pch(c);
        }
    }
    wn = ww = 0; wsp = 0;
}
static void wadd(uint8_t c)
{
    if (c == ' ') { wflush(); wsp = 1; return; }
    if (wn >= sizeof wbuf - 1) wflush();
    wbuf[wn++] = c;
    if (c >= 9 && !cont(c)) ww++;
}
static uint8_t incode;
/* el texto de [a,b) con sus marcas en linea (puede ser de varias lineas) */
static void inl(uint16_t a, uint16_t b)
{
    uint16_t p;
    for (p = a; p < b; p++) {
        uint8_t c = ch(p);
        if (c == '\n' || c == '\t') { wadd(' '); continue; }
        if (c == '\\' && p + 1 < b && ch(p + 1) > ' ') { wadd(ch(++p)); continue; }
        if (c == '`') { wadd(3); incode ^= 1; continue; }
        if (incode) { wadd(c); continue; }
        if ((c == '*' || c == '_') && ch(p + 1) == c) { wadd(1); p++; continue; }
        if (c == '*' || (c == '_' && (p == a || ch(p - 1) == ' ' || ch(p + 1) == ' ' || p + 1 == b))) { wadd(2); continue; }
        if (c == '!' && ch(p + 1) == '[') { wadd('['); wadd('i'); wadd('m'); wadd('g'); wadd(':'); wadd(' '); p++; continue; }
        if (c == '[') {                   /* [texto](url) */
            uint16_t q = p + 1;
            while (q < b && ch(q) != ']' && ch(q) != '\n') q++;
            if (q < b && ch(q) == ']' && ch(q + 1) == '(') {
                uint16_t u = q + 2, ue = u;
                while (ue < b && ch(ue) != ')' && ch(ue) != '\n') ue++;
                wadd(4); inl(p + 1, q); wadd(5);
                if (ue - u < 60 && ch(u) != '#') {
                    wadd(' '); wadd(6); wadd('<');
                    for (; u < ue; u++) wadd(ch(u));
                    wadd('>'); wadd(7);
                }
                p = ue;
                continue;
            }
        }
        wadd(c);
    }
}
static uint16_t skipsp(uint16_t p) { while (ch(p) == ' ' || ch(p) == '\t') p++; return p; }
static uint8_t blank(uint16_t ls) { return skipsp(ls) >= lend(ls); }
/* una celda de tabla: ancho visible (sin marcas) */
static uint8_t cellw(uint16_t a, uint16_t b)
{
    uint8_t n = 0;
    for (; a < b; a++) {
        uint8_t c = ch(a);
        if (c == '*' || c == '`' || (c == '_' && (ch(a + 1) == '_' || ch(a - 1) == '_'))) continue;
        if (c == '\\') { a++; n++; continue; }
        if (!cont(c)) n++;
    }
    return n;
}
#define TMAXC 8
static uint8_t tw[TMAXC];
static uint8_t cells(uint16_t ls, uint16_t *ca, uint16_t *cb)   /* las celdas de una fila */
{
    uint16_t p = skipsp(ls), e = lend(ls);
    uint8_t n = 0;
    if (ch(p) == '|') p++;
    while (e > p && (ch(e - 1) == ' ' || ch(e - 1) == '|')) { if (ch(e - 1) == '|') { e--; break; } e--; }
    while (p <= e && n < TMAXC) {
        uint16_t q = p;
        while (q < e && !(ch(q) == '|' && ch(q - 1) != '\\')) q++;
        ca[n] = skipsp(p);
        cb[n] = q;
        while (cb[n] > ca[n] && ch(cb[n] - 1) == ' ') cb[n]--;
        n++;
        if (q >= e) break;
        p = q + 1;
    }
    return n;
}
static uint8_t issep(uint16_t ls)
{
    uint16_t p = skipsp(ls), e = lend(ls);
    uint8_t d = 0;
    for (; p < e; p++) { uint8_t c = ch(p); if (c == '-') d = 1; else if (c != '|' && c != ':' && c != ' ') return 0; }
    return d;
}
static void table(uint16_t a, uint16_t b)  /* las lineas [a,b) son una tabla */
{
    uint16_t l, ca[TMAXC], cb[TMAXC];
    uint8_t n, i, nc = 0, row = 0;
    memset(tw, 0, sizeof tw);
    for (l = a; l < b; l = nextl(l)) {
        if (issep(l)) continue;
        n = cells(l, ca, cb);
        if (n > nc) nc = n;
        for (i = 0; i < n; i++) { uint8_t w = cellw(ca[i], cb[i]); if (w > tw[i]) tw[i] = w; }
    }
    for (l = a; l < b; l = nextl(l)) {
        if (issep(l)) {
            pnl();
            for (i = 0; i < nc; i++) {
                uint8_t k;
                if (i) pstr_(u8("\xe2\x94\x80\xe2\x94\xbc\xe2\x94\x80", "-+-"));    /* ─┼─ */
                for (k = 0; k < tw[i]; k++) pstr_(u8("\xe2\x94\x80", "-"));
            }
            continue;
        }
        n = cells(l, ca, cb);
        pnl();
        if (!row) { ph = 3; psgr(); }
        for (i = 0; i < nc; i++) {
            uint8_t w = 0;
            if (i) { uint8_t h = ph; ph = 0; psgr(); pstr_(u8(" \xe2\x94\x82 ", " | ")); ph = h; psgr(); }   /* │ */
            if (i < n) {
                uint16_t q0 = pvcol;
                wn = ww = 0; wsp = 0;
                inl(ca[i], cb[i]); wflush();
                w = pvcol - q0;
            }
            while (w++ < tw[i]) pch(' ');
            pb_ = pi_ = pc_ = pl_ = pu_ = 0;
            psgr();
        }
        ph = 0; psgr();
        row++;
    }
}
/* toda la vista; devuelve cuantas filas tiene */
static uint16_t render(void)
{
    uint16_t l = 0, n = LEN();
    uint8_t blankrow = 1;
    pvrow = 0xFFFF; pvcol = 0; pvind = 0; pvpre = 0;
    pb_ = pi_ = pc_ = pl_ = pu_ = ph = 0;
    incode = 0;
    while (l < n) {
        uint16_t p = skipsp(l), e = lend(l);
        uint8_t q;
        if (!prn && !pvcount && pvrow != 0xFFFF && pvrow > pvtop + pvhi) return 0;   /* ya se vio todo */
        if (ch(p) == '<' && ch(p + 1) == '!' && ch(p + 2) == '-' && ch(p + 3) == '-') {   /* <!-- .orden --> */
            if (prn) dotcmd(p + 4, e);
            l = nextl(l);
            continue;
        }
        if (blank(l)) { pvpre = 0; pvind = 0; if (!blankrow) { pnl(); blankrow = 1; } l = nextl(l); continue; }
        blankrow = 0;
        pvind = 0; pvpre = 0;
        if (isfence(l)) {                 /* ``` ... ``` */
            l = nextl(l);
            while (l < n && !isfence(l)) {
                uint16_t k, c = 0;
                pvind = 2; pc_ = 1; pnl();
                for (k = l; k < lend(l) && c < vw - 2; k++) { uint8_t ch_ = ch(k); if (ch_ == '\t') { do pch(' '); while (++c & 3); } else { pch(ch_); if (!cont(ch_)) c++; } }
                pc_ = 0;
                l = nextl(l);
            }
            pvind = 0; psgr();
            l = nextl(l);
            continue;
        }
        if ((ph = hlevel(l))) {           /* titulo */
            uint8_t lv = ph;
            pnl();
            wn = ww = 0; wsp = 0;
            inl(skipsp(l + lv), e); wflush();
            if (lv <= 2) {
                uint8_t k, w = pvcol < vw ? pvcol : vw;
                pnl();
                for (k = 0; k < w; k++) pstr_(lv == 1 ? u8("\xe2\x95\x90", "=") : u8("\xe2\x94\x80", "-"));   /* ═ ─ */
            }
            ph = 0; psgr();
            l = nextl(l);
            continue;
        }
        if (isrule(p)) {
            uint8_t k;
            pnl(); psg("2");
            for (k = 0; k < vw; k++) pstr_(u8("\xe2\x94\x80", "-"));
            psgr();
            l = nextl(l);
            continue;
        }
        if (ch(p) == '|') {               /* tabla */
            uint16_t b = l;
            while (b < n && ch(skipsp(b)) == '|') b = nextl(b);
            table(l, b);
            l = b;
            continue;
        }
        /* parrafo, punto de lista o cita: hasta una linea en blanco o un bloque */
        {
            uint8_t ind = p - l;
            uint16_t a;
            q = listmark(p);
            if (ch(p) == '>') {
                pvpre = u8("\xe2\x94\x82 ", "| ");      /* │ */
                pnl();
                a = skipsp(p + 1);
            } else if (q) {
                pvind = ind;
                pnl();
                psg("33");
                if (ch(p) == '-' || ch(p) == '*' || ch(p) == '+') pstr_(u8("\xe2\x80\xa2 ", "- "));   /* • */
                else { uint8_t k; for (k = 0; k < q; k++) pch(ch(p + k)); }
                psgr();
                pvind = ind + (ch(p) >= '0' && ch(p) <= '9' ? q : 2);
                a = p + q;
            } else { pnl(); a = p; }
            wn = ww = 0; wsp = 0;
            for (;;) {
                uint16_t le = lend(a);
                inl(a, le);
                wadd(' ');
                l = nextl(l);
                if (l >= n || blank(l) || isfence(l) || hlevel(l) || ch(skipsp(l)) == '|' || isrule(skipsp(l))) break;
                p = skipsp(l);
                if (listmark(p) || (ch(p) == '>') != (pvpre != 0)) break;
                a = ch(p) == '>' ? skipsp(p + 1) : p;
            }
            wflush();
            pb_ = pi_ = pc_ = pl_ = pu_ = 0;
            psgr();
        }
    }
    pnl();
    return pvrow;
}
static uint16_t vtotal;
static void vstatus(void)
{
    ogo(STROW, 1); psg("7");
    os(" ZWRITE preview  "); os(*fname_ ? fname_ : "[no name]");
    os("\x1b[K"); ogo(STROW, 58); os("row "); onum(pvtop + 1); os(" of "); onum(vtotal); os("  ");
    psg("0");
    ogo(MSGROW, 1); psg("2");
    os(viewonly ? "arrows, PgUp/PgDn, Home/End to move; Q quits" : "arrows, ^E ^X ^R ^C, PgUp/PgDn, Home/End to move; ESC or Q back to edit");
    psg("0"); oeol();
}
static void vdraw(uint8_t lo, uint8_t hi)  /* las filas lo..hi de la ventana */
{
    uint8_t r;
    pvlo = lo; pvhi = hi;
    render();
    if (pvrow <= pvtop + hi)              /* lo que queda despues del final: vacio */
        for (r = pvrow < pvtop + lo ? lo : pvrow - pvtop; r <= hi; r++) { ogo(r + 1, 1); oeol(); }
    pvlo = 0; pvhi = ROWS - 1;
}
static void view(void)
{
    uint8_t k;
    uint16_t old;
    pvcount = 1; pvtop = 0;               /* primero, cuantas filas hay */
    vtotal = render() + 1;
    pvcount = 0;
    os(CLS);
    vdraw(0, ROWS - 1); vstatus();
    for (;;) {
        k = key();
        old = pvtop;
        if (k == KDOWN || k == '\r' || k == 'j' || k == CTRL('X')) pvtop++;
        else if (k == KUP || k == 'k' || k == CTRL('E')) { if (pvtop) pvtop--; }
        else if (k == KPGDN || k == ' ' || k == CTRL('C')) pvtop += ROWS - 1;
        else if (k == KPGUP || k == 'b' || k == CTRL('R')) pvtop = pvtop > ROWS - 1 ? pvtop - (ROWS - 1) : 0;
        else if (k == KHOME || k == 'g') pvtop = 0;
        else if (k == KEND || k == 'G') pvtop = 0xF000;
        else if (k == CTRL('L')) { os(CLS); old = 0xFFFF; }
        else if (k == 'q' || k == 'Q' || k == 27 || k == CTRL('O') || k == CTRL('Q') || k == CTRL('K')) break;
        if (vtotal <= ROWS) pvtop = 0;
        else if (pvtop > vtotal - ROWS) pvtop = vtotal - ROWS;
        if (pvtop == old) continue;
        if (pvtop == old + 1) {           /* una fila: se corre la pantalla */
            scrl(1);
            vdraw(ROWS - 1, ROWS - 1);
        } else if (pvtop + 1 == old) {
            scrl(0);
            vdraw(0, 0);
        } else vdraw(0, ROWS - 1);
        vstatus();
    }
}

/* ---------------------------------------------------------------- imprimir */
/* Paginas de pl lineas: arriba una en blanco, el encabezado y otra en blanco;
   abajo una en blanco, el numero de pagina y un salto de pagina (^L). Ordenes en
   el texto: <!-- .page -->, <!-- .header texto -->, <!-- .width n -->,
   <!-- .margin n -->, <!-- .lines n -->, <!-- .nonumber --> */
static uint8_t pw = 65, pm = 8, pl = 66, pnumon = 1, pline, ppage, odev, oerr, obp;
static char phdr[64];
static FCB of;
static uint8_t ob[128];
static void pout(uint8_t c)
{
    if (odev) { bdos(5, c); return; }
    ob[obp++] = c;
    if (obp == 128) { if (fwrite(&of, ob)) oerr = 1; obp = 0; }
}
static void pouts(const char *s) { while (*s) pout(*s++); }
static void pnewl(void) { pout('\r'); pout('\n'); }
static void pspc(uint8_t n) { while (n--) pout(' '); }
static void pcenter(const char *s)
{
    uint8_t n = strlen(s);
    pspc(pm + (pw > n ? (pw - n) >> 1 : 0));
    pouts(s);
}
static void ptop(void)
{
    ppage++;
    pnewl();
    if (*phdr) pcenter(phdr);
    pnewl(); pnewl();
    pline = 0;
}
static void pbot(void)
{
    char t[12];
    uint8_t n = 0, k;
    uint16_t v = ppage;
    while (pline < pl - 6) { pnewl(); pline++; }
    pnewl();
    if (pnumon) {
        t[n++] = '-'; t[n++] = ' ';
        { char d[6]; k = 0; do d[k++] = '0' + v % 10; while (v /= 10); while (k) t[n++] = d[--k]; }
        t[n++] = ' '; t[n++] = '-'; t[n] = 0;
        pcenter(t);
    }
    pnewl();
    pout(12);
    pline = 0xFF;
}
static uint8_t jb[200], js[200];
static void prnline(void)
{
    uint8_t i, n, lead = 0, gaps = 0, wid = 0, g, add, k, c, st;
    if (pline == 0xFF) ptop();
    while (pln && plb[pln - 1] == ' ') pln--;
    while (lead < pln && plb[lead] == ' ') lead++;
    if (lead < pvind && pvind < pln) lead = pvind;   /* la marca de la lista no se estira */
    for (i = 0; i < pln; i++) { if (!cont(plb[i])) wid++; if (i >= lead && plb[i] == ' ') gaps++; }
    if (pjust && gaps && wid < pw && pln + (pw - wid) <= sizeof jb) {   /* justificar */
        add = pw - wid;
        for (i = n = g = 0; i < pln; i++) {
            jb[n] = plb[i]; js[n++] = pls[i];
            if (i >= lead && plb[i] == ' ') {
                for (k = add / gaps + (g < add % gaps); k; k--) { jb[n] = ' '; js[n++] = 0; }
                g++;
            }
        }
        memcpy(plb, jb, n); memcpy(pls, js, n); pln = n;
    }
    pspc(pm);
    for (i = 0; i < pln; i++) {
        c = plb[i]; st = pls[i];
        pout(c);
        if (odev && c > ' ' && c < 128) {              /* en la impresora: negrita y subrayado */
            if (st & 1) { pout(8); pout(c); }
            if (st & 2) { pout(8); pout('_'); }
        }
    }
    pnewl();
    pln = 0;
    if (++pline >= pl - 6) pbot();
}
static uint8_t pnum(const char *s) { uint8_t v = 0; while (*s == ' ') s++; while (*s >= '0' && *s <= '9') v = v * 10 + *s++ - '0'; return v; }
static void dotcmd(uint16_t p, uint16_t e)
{
    char t[64];
    uint8_t n = 0, v;
    while (p < e && ch(p) == ' ') p++;
    while (p < e && n < 63 && !(ch(p) == '-' && ch(p + 1) == '-' && ch(p + 2) == '>')) t[n++] = ch(p++);
    while (n && t[n - 1] == ' ') n--;
    t[n] = 0;
    if (pln || pvrow != 0xFFFF) { if (pln) prnline(); pvrow = 0xFFFF; }   /* lo que queda de antes */
    if (!memcmp(t, ".page", 5)) { if (pline != 0xFF && pline) pbot(); }
    else if (!memcmp(t, ".header", 7)) { strcpy(phdr, t + (t[7] == ' ' ? 8 : 7)); }
    else if (!memcmp(t, ".nonumber", 9)) pnumon = 0;
    else if (!memcmp(t, ".width", 6)) { if ((v = pnum(t + 6)) >= 20 && v <= 132) pw = v; vw = pw; }
    else if (!memcmp(t, ".margin", 7)) { if ((v = pnum(t + 7)) <= 40) pm = v; }
    else if (!memcmp(t, ".lines", 6)) { if ((v = pnum(t + 6)) >= 20) pl = v; }
}
/* ^KP: todo el texto a la impresora o a un archivo .PRN */
static void print(void)
{
    char *d;
    cl[0] = 0;
    if (!readline("Print to file (Enter = printer): ")) return;
    odev = !cl[0];
    if (!odev) {
        for (d = cl; *d; d++) if (*d >= 'a' && *d <= 'z') *d -= 32;
        if (!strchr(cl, '.')) strcat(cl, ".PRN");
        if (!mkfcb(&of, cl) || fmake(&of)) { msg("Cannot create the file"); return; }
        obp = 0; oerr = 0;
    }
    msg("Printing...");
    pw = 65; pm = 8; pl = 66; pnumon = 1; phdr[0] = 0;
    prn = 1; vw = pw; pline = 0xFF; ppage = 0; pln = 0; pvcount = 0;
    render();
    if (pline != 0xFF) pbot();
    prn = 0; vw = W;
    if (!odev) {
        if (obp) { memset(ob + obp, 26, 128 - obp); if (fwrite(&of, ob)) oerr = 1; }
        fclose(&of);
    }
    msg(oerr ? "Write error (disk full?)" : "Printed");
}

/* ---------------------------------------------------------------- edicion */
#define CUTSZ 256
static char cutb[CUTSZ];
static uint16_t cutn;
static uint8_t lastcut, typing;
static char pat[72];
static uint8_t fold(uint8_t c) { return c >= 'A' && c <= 'Z' ? c + 32 : c; }
static uint8_t find(uint16_t from)
{
    uint16_t n = LEN(), m = strlen(pat), p = from, k, i;
    if (!m) return 0;
    for (k = 0; k <= n; k++, p++) {
        if (p >= n) p = 0;
        if (p + m > n) continue;
        for (i = 0; i < m && fold(ch(p + i)) == fold(pat[i]); i++) ;
        if (i == m) { cur = p; return 1; }
    }
    return 0;
}
static void undo(void)
{
    uint16_t o, l;
    uint8_t any = 0;
    if (lastmark() && ulen) {             /* la marca del final no cuenta */
        o = 0; l = 0; while (o < ulen) { l = o; o += esz(ulog + o); }
        ulen = l;
    }
    undoing = 1;
    while (ulen) {
        uint8_t *e;
        o = 0; l = 0; while (o < ulen) { l = o; o += esz(ulog + o); }
        e = ulog + l;
        ulen = l;
        if (e[0] == 2) break;
        {
            uint16_t p = e[1] | (e[2] << 8), n = e[3] | (e[4] << 8);
            if (e[0] == 0) { moveto(p); ge += n; cur = p; }
            else { moveto(p); memcpy(buf + gs, e + 5, n); gs += n; cur = p + n; }
            modified = 1;
            any = 1;
        }
    }
    undoing = 0;
    if (!any) msg("Nothing to undo");
    need = N_ALL; stdirty = 1;
}
static void newline(void)
{
    uint16_t ls = lstart(cur), p = ls, i;
    char pre[16];
    uint8_t n = 0, q;
    while (ch(p) == ' ' && n < 8) pre[n++] = ch(p++);
    q = ch(p) == '>' ? 0 : listmark(p);
    if (ch(p) == '>') { pre[n++] = '>'; pre[n++] = ' '; q = 0; }
    else if (q) {
        if (ch(p) >= '0' && ch(p) <= '9') {        /* el numero siguiente */
            uint16_t v = 0; uint8_t k;
            for (k = 0; k < q - 2; k++) v = v * 10 + ch(p + k) - '0';
            v++;
            { char t[6]; uint8_t m = 0; do t[m++] = '0' + v % 10; while (v /= 10); while (m) pre[n++] = t[--m]; }
            pre[n++] = ch(p + q - 2); pre[n++] = ' ';
        } else { pre[n++] = ch(p); pre[n++] = ' '; }
    }
    /* un punto vacio: termina la lista */
    if ((q || ch(p) == '>') && skipsp(p + (q ? q : 1)) >= lend(ls) && cur == lend(ls)) {
        del(ls, cur - ls);
        cur = ls;
        need = N_LINE;
        return;
    }
    if (!insc(cur, '\n')) { msg("Out of memory"); return; }
    cur++;
    if (n && cur - 1 == lend(ls)) {
        if (ins(cur, pre, n)) cur += n;
    } else {
        i = 0;
        while (i < n && pre[i] == ' ') i++;          /* en medio: solo la sangria */
        if (i && ins(cur, pre, i)) cur += i;
    }
    needfrom(ls);
}
static void edit(const char *name)
{
    uint16_t n;
    uint8_t r = 1;
    gs = 0; ge = bsz; ulen = 0;
    strncpy(fname_, name, 15);
    if (*name) r = loadat(name, &n);
    if (!LEN() || ch(LEN() - 1) != '\n') { moveto(LEN()); buf[gs++] = '\n'; }
    cur = tl = ltop = 0; ts = topfence = 0; modified = 0;
    need = N_ALL; stdirty = 1;
    if (!*name) return;
    if (r == 1) msg("New file");
    else if (r == 2) msg("File too large: only the beginning was read. Do not save it over the original!");
}

/* ---- WordStar */
static uint8_t isw(uint8_t c) { return c > ' ' && c != '\n'; }
static uint16_t wordl(uint16_t p) { while (p && !isw(ch(p - 1))) p--; while (p && isw(ch(p - 1))) p--; return p; }
static uint16_t wordr(uint16_t p) { uint16_t n = LEN() - 1; while (p < n && isw(ch(p))) p++; while (p < n && !isw(ch(p))) p++; return p; }
/* una tecla de un menu de prefijo (^K ^Q ^O ^P): la letra en mayuscula */
static uint8_t pfx(const char *m)
{
    uint8_t k;
    msg(m);
    k = key();
    if (k < 32) k += 64;                  /* ^K B = ^K ^B */
    if (k >= 'a' && k <= 'z') k -= 32;
    showhelp();
    return k;
}
static void helpscr(void)
{
    os(CLS);
    os("ZWRITE - writes Markdown with the WordStar keys                     (C) OLIVEROS 2026\r\n\r\n"
       " Cursor   ^E up  ^X down  ^S left  ^D right  ^A word left  ^F word right\r\n"
       "          ^R page up  ^C page down  ^W ^Z line up/down   (or the arrows and keys)\r\n"
       " Delete   ^G char  DEL/BS char left  ^T word  ^Y line  ^QY to end of line\r\n"
       " Insert   ^V insert/overtype  ^N split the line  Tab  ^U undo\r\n"
       " ^Q       S D start/end of line  E X top/bottom of screen  R C start/end of file\r\n"
       "          F find  A find and replace (options: U any case, G whole file, N no\r\n"
       "          asking)  I go to line   ^L repeats the last find\r\n"
       " ^K       B K block start/end  H hide  C copy  V move  Y delete  W write  R read\r\n"
       "          S save  D, X save and exit  Q quit  P print\r\n"
       " ^O       D preview (formatted, without the marks)\r\n"
       " ^P       B **bold**  Y *italic*\r\n\r\n"
       " Markdown: # titles, - and 1. lists, > quotes, ``` code, | tables |, **bold**,\r\n"
       " *italic*, `code`. The lines are paragraphs: Enter only ends a paragraph.\r\n"
       " Print commands: <!-- .page -->  <!-- .header text -->  <!-- .width 65 -->\r\n"
       " <!-- .margin 8 -->  <!-- .lines 66 -->  <!-- .nonumber -->\r\n\r\n"
       " Press any key.");
    key();
    os(CLS);
    need = N_ALL; stdirty = 1;
}
static uint8_t findopt[8];
static char rep_[72];
static uint8_t isopt(char o) { return strchr((char *)findopt, o) != 0; }
static uint8_t matchat(uint16_t p, uint16_t m)
{
    uint16_t i;
    if (isopt('U')) { for (i = 0; i < m && fold(ch(p + i)) == fold(pat[i]); i++) ; }
    else for (i = 0; i < m && ch(p + i) == pat[i]; i++) ;
    return i == m;
}
/* busca desde 'from' hacia el final; 1 si lo encontro (cur alli) */
static uint8_t findfw(uint16_t from)
{
    uint16_t n = LEN(), m = strlen(pat), p;
    if (!m) return 0;
    for (p = from; p + m <= n; p++) if (matchat(p, m)) { cur = p; return 1; }
    return 0;
}
static uint8_t lastfind;                  /* 1 buscar, 2 reemplazar (para ^L) */
static void doreplace(uint8_t again)
{
    uint16_t m = strlen(pat), r = strlen(rep_), cnt = 0, from = again ? cur : cur;
    uint8_t all = isopt('G'), noask = isopt('N'), k;
    if (all && !again) from = 0;
    while (findfw(from)) {
        k = 'Y';
        if (!noask) {
            refresh();
            msg("Replace (Y/N, ESC stops)? ");
            k = key();
            if (k >= 'a') k -= 32;
            showhelp();
            if (k == 27) break;
        }
        if (k == 'Y') {
            ugroup();
            del(cur, m);
            if (!ins(cur, rep_, r)) { msg("Out of memory"); break; }
            from = cur + r; cnt++;
        } else from = cur + 1;
        if (!all && !noask) break;
        if (!all) break;
    }
    need = N_ALL;
    if (!cnt && !findfw(cur)) msg("Not found");
}
/* ^KR: lee un archivo en el cursor */
static void readin(void)
{
    uint16_t n, p = cur, oldlen = LEN();
    uint8_t r;
    cl[0] = 0;
    if (!readline("Read file: ") || !*cl) return;
    moveto(cur);
    ugroup();
    {   /* loadat escribe en el hueco desde cur */
        uint16_t gs0 = gs;
        r = loadat(cl, &n);
        if (r == 1) { msg("File not found"); return; }
        { uint16_t k = gs - gs0; gs = gs0; ulogop(0, p, 0); gs = gs0 + k; ulog[ulen - 2] = k; ulog[ulen - 1] = k >> 8;
          if (bb > p) bb += k; if (be > p) be += k; }
        modified = 1;
        if (r == 2) msg("Not enough memory: only the beginning was read");
    }
    (void)oldlen;
    need = N_ALL;
}
/* ^KW: el bloque (o todo, sin bloque) a un archivo */
static void writeblk(void)
{
    uint16_t a = 0, b = LEN(), i;
    char *d;
    if (bb < be) { a = bb; b = be; }
    cl[0] = 0;
    if (!readline("Write to file: ") || !*cl) return;
    for (d = cl; *d; d++) if (*d >= 'a' && *d <= 'z') *d -= 32;
    if (!mkfcb(&of, cl) || fmake(&of)) { msg("Cannot create the file"); return; }
    odev = 0; obp = 0; oerr = 0;
    for (i = a; i < b; i++) { if (ch(i) == '\n') pout('\r'); pout(ch(i)); }
    if (obp) { memset(ob + obp, 26, 128 - obp); if (fwrite(&of, ob)) oerr = 1; }
    else pout(26), (void)0;
    fclose(&of);
    msg(oerr ? "Write error (disk full?)" : "Written");
}
static uint8_t quitask(void)
{
    uint8_t k;
    if (!modified) return 1;
    msg("Abandon the changes? (Y/N) ");
    k = key() | 32;
    showhelp();
    return k == 'y';
}
static uint8_t savefile(void)
{
    if (!*fname_) { cl[0] = 0; if (!readline("Save as: ") || !*cl) return 0; strncpy(fname_, cl, 15); stdirty = 1; }
    return save(fname_);
}

void main(void)
{
    char *p = args(), *a = nextarg(&p);
    uint16_t hi = *(uint16_t *)6 - 1024;
    uint8_t quit = 0;
    buf = heap;
    if ((uint16_t)heap >= hi - 2048) { pstr("Not enough memory\n"); return; }
    bsz = hi - (uint16_t)heap;
    bdos(45, 0xFF);
    if (a && a[0] == '-' && (a[1] | 32) == 'v') { viewonly = 1; a = nextarg(&p); }
    if (!a && viewonly) { pstr("Usage: ZWRITE [-V] file\n"); return; }
    pstr(CLS);
    edit(a ? a : "");
    if (viewonly) { view(); pstr(CLS); return; }
    while (!quit) {
        uint8_t c, wasmod = modified, h0, k;
        uint16_t l0;
        if (!pending()) refresh();
        c = key();
        l0 = lstart(cur); h0 = height(l0);
        if (msgon) showhelp();
        if (!(c >= 32 && c < 0xFE && c != 0x7F) && c != '\t') typing = 0;
        switch (c) {               /* el diamante de WordStar */
        case CTRL('E'): c = KUP; break;
        case CTRL('X'): c = KDOWN; break;
        case CTRL('S'): c = KLEFT; break;
        case CTRL('D'): c = KRIGHT; break;
        case CTRL('R'): c = KPGUP; break;
        case CTRL('C'): c = KPGDN; break;
        case CTRL('W'): c = KUP; break;
        case CTRL('Z'): c = KDOWN; break;
        case CTRL('G'): c = KDEL; break;
        case 127: c = 8; break;
        }
        switch (c) {
        case KLEFT: cur = left1(cur); wantcol = colat(lstart(cur), cur); break;
        case KRIGHT: if (cur < LEN() - 1) cur = right1(cur); wantcol = colat(lstart(cur), cur); break;
        case CTRL('A'): cur = wordl(cur); wantcol = colat(lstart(cur), cur); break;
        case CTRL('F'): cur = wordr(cur); wantcol = colat(lstart(cur), cur); break;
        case KUP: case KDOWN: {
            uint16_t ls = lstart(cur), cc = colat(ls, cur);
            uint8_t sub = cc / W;
            uint16_t want = wantcol % W;
            if (c == KUP) {
                if (sub) cur = atcol(ls, (sub - 1) * W + want);
                else if (ls) { uint16_t pl_ = prevl(ls); cur = atcol(pl_, (height(pl_) - 1) * W + want); }
            } else {
                if (sub + 1 < height(ls)) cur = atcol(ls, (sub + 1) * W + want);
                else if (nextl(ls) < LEN()) cur = atcol(nextl(ls), want);
            }
            break;
        }
        case KHOME: cur = lstart(cur); wantcol = 0; break;
        case KEND: cur = lend(cur); wantcol = colat(lstart(cur), cur); break;
        case KPGUP: case KPGDN: {
            uint8_t i;
            for (i = 0; i < ROWS - 1; i++) {
                if (c == KPGUP) back1(); else fwd1();
            }
            if (c == KPGUP) { uint16_t ls = lstart(cur); uint8_t k2; for (k2 = 0; k2 < ROWS - 1 && ls; k2++) ls = prevl(ls); cur = atcol(ls, wantcol % W); }
            else { uint16_t ls = lstart(cur); uint8_t k2; for (k2 = 0; k2 < ROWS - 1 && nextl(ls) < LEN(); k2++) ls = nextl(ls); cur = atcol(ls, wantcol % W); }
            need = N_ALL;
            break;
        }
        case '\r': ugroup(); newline(); ugroup(); wantcol = colat(lstart(cur), cur); break;
        case CTRL('N'):                    /* partir la linea: el cursor no se mueve */
            ugroup();
            if (insc(cur, '\n')) needfrom(lstart(cur));
            break;
        case 8:
            if (!cur) break;
            ugroup();
            { uint16_t q = left1(cur), ls = lstart(cur);
              if (cur == ls) needfrom(q); else if (!need) need = N_LINE;
              del(q, cur - q); cur = q; }
            wantcol = colat(lstart(cur), cur);
            break;
        case KDEL:
            if (cur >= LEN() - 1) break;
            ugroup();
            { uint16_t q = right1(cur);
              if (ch(cur) == '\n') needfrom(cur); else if (!need) need = N_LINE;
              del(cur, q - cur); }
            break;
        case CTRL('T'):                    /* la palabra a la derecha */
            ugroup();
            { uint16_t q = wordr(cur);
              if (q == cur && ch(cur) == '\n' && cur < LEN() - 1) q++;
              if (q > cur) { needfrom(lstart(cur)); del(cur, q - cur); } }
            break;
        case CTRL('Y'): {                  /* la linea */
            uint16_t ls = lstart(cur), b = nextl(cur);
            if (b == ls) break;
            if (b >= LEN() && LEN() - ls <= 1) b = LEN() - 1 > ls ? LEN() - 1 : b;
            ugroup();
            del(ls, b - ls);
            if (!LEN() || ch(LEN() - 1) != '\n') insc(LEN(), '\n');
            cur = ls < LEN() ? ls : lastl();
            needfrom(ls);
            break;
        }
        case CTRL('V'): ovr ^= 1; stdirty = 1; break;
        case CTRL('U'): undo(); break;
        case CTRL('L'):
            if (lastfind == 2) doreplace(1);
            else if (lastfind == 1) { if (!findfw(right1(cur))) msg("Not found"); }
            wantcol = colat(lstart(cur), cur);
            break;
        case CTRL('J'): helpscr(); break;
        case CTRL('P'):
            k = pfx("^P  B **bold**   Y *italic*");
            if (k == 'B' || k == 'Y') {
                ugroup();
                if (ins(cur, k == 'B' ? "**" : "*", k == 'B' ? 2 : 1)) cur += k == 'B' ? 2 : 1;
                if (!need) need = N_LINE;
            }
            break;
        case CTRL('O'):
            k = pfx("^O  D preview (formatted, without the marks)");
            if (k == 'D') { view(); need = N_ALL; stdirty = 1; }
            break;
        case CTRL('Q'):
            k = pfx("^Q  S D line start/end  E X screen top/bottom  R C file start/end  F find  A replace  Y del to EOL  I line");
            switch (k) {
            case 'S': cur = lstart(cur); break;
            case 'D': cur = lend(cur); break;
            case 'R': cur = 0; break;
            case 'C': cur = LEN() - 1; break;
            case 'E': case 'X': {
                uint8_t i, r = crow;
                for (i = 0; i < ROWS && (k == 'E' ? r > 1 : r < ROWS); i++) {
                    uint16_t ls = lstart(cur), cc = colat(ls, cur), o = cur;
                    uint8_t sub = cc / W;
                    if (k == 'E') { if (sub) cur = atcol(ls, (sub - 1) * W + cc % W); else if (ls) { uint16_t q = prevl(ls); cur = atcol(q, (height(q) - 1) * W + cc % W); } r--; }
                    else { if (sub + 1 < height(ls)) cur = atcol(ls, (sub + 1) * W + cc % W); else if (nextl(ls) < LEN()) cur = atcol(nextl(ls), cc % W); r++; }
                    if (cur == o) break;
                }
                break;
            }
            case 'Y': { uint16_t e = lend(cur); if (e > cur) { ugroup(); del(cur, e - cur); if (!need) need = N_LINE; } break; }
            case 'F': case 'A':
                strcpy(cl, pat);
                if (!readline("Find: ") || !*cl) break;
                strcpy(pat, cl);
                if (k == 'A') { strcpy(cl, rep_); if (!readline("Replace with: ")) break; strcpy(rep_, cl); }
                strcpy(cl, (char *)findopt);
                if (!readline("Options (U any case, G whole file, N no asking): ")) break;
                { uint8_t i; for (i = 0; cl[i] && i < 7; i++) findopt[i] = cl[i] >= 'a' ? cl[i] - 32 : cl[i]; findopt[i] = 0; }
                lastfind = k == 'F' ? 1 : 2;
                if (k == 'F') { if (!findfw(isopt('G') ? 0 : right1(cur))) msg("Not found"); }
                else doreplace(0);
                break;
            case 'I':
                cl[0] = 0;
                if (readline("Go to line: ")) {
                    uint16_t v = 0; char *s = cl;
                    while (*s >= '0' && *s <= '9') v = v * 10 + *s++ - '0';
                    if (v) cur = gotol(v);
                }
                break;
            }
            wantcol = colat(lstart(cur), cur);
            break;
        case CTRL('K'):
            k = pfx("^K  B K block  H hide  C copy  V move  Y delete  W write  R read  S save  D X exit  Q quit  P print");
            switch (k) {
            case 'B': bb = cur; if (be <= bb) be = bb; bhide = 0; need = N_ALL; stdirty = 1; break;
            case 'K': be = cur; if (bb >= be) bb = lstart(cur) < cur ? lstart(cur) : 0; bhide = 0; need = N_ALL; stdirty = 1; break;
            case 'H': bhide ^= 1; need = N_ALL; stdirty = 1; break;
            case 'C': case 'V': {
                uint16_t n = be - bb, ob0 = bb, src = bb, dst = cur, left, part, i;
                uint8_t ok = 1;
                if (bb >= be || bhide) { msg("No block (^KB and ^KK mark it)"); break; }
                if (k == 'V' && cur > bb && cur < be) { msg("The cursor is inside the block"); break; }
                if (n > room()) { msg("Out of memory"); break; }
                ugroup();
                for (left = n; left; left -= part) {   /* de a CUTSZ bytes */
                    part = left > CUTSZ ? CUTSZ : left;
                    for (i = 0; i < part; i++) cutb[i] = ch(src + i);
                    if (!ins(dst, cutb, part)) { ok = 0; break; }
                    if (src >= dst) src += part;       /* lo que falta se corrio */
                    src += part; dst += part;
                }
                if (!ok) { msg("Out of memory"); break; }
                if (k == 'V') {
                    uint16_t o = ob0 >= cur ? ob0 + n : ob0, nb = cur;
                    del(o, n);
                    if (nb > o) nb -= n;
                    cur = nb;
                }
                bb = cur; be = cur + n;
                need = N_ALL;
                break;
            }
            case 'Y':
                if (bb >= be || bhide) { msg("No block"); break; }
                ugroup();
                cur = bb;
                del(bb, be - bb);
                if (!LEN() || ch(LEN() - 1) != '\n') insc(LEN(), '\n');
                bb = be = 0;
                need = N_ALL; stdirty = 1;
                break;
            case 'W': writeblk(); break;
            case 'R': readin(); break;
            case 'S': savefile(); break;
            case 'D': case 'X': if (!modified || savefile()) quit = 1; break;
            case 'Q': if (quitask()) quit = 1; break;
            case 'P': print(); need = N_ALL; break;
            }
            break;
        case '\t':
            ugroup();
            { uint8_t k2 = 4 - colat(lstart(cur), cur) % 4;
              if (ins(cur, "    ", k2)) cur += k2; }
            if (!need) need = N_LINE;
            break;
        default:
            if (c >= 32 && c < 0xFE && c != 0x7F) {
                if (!typing) ugroup();
                typing = 1;
                if (ovr && ch(cur) != '\n' && cur < LEN() - 1) del(cur, right1(cur) - cur);
                if (!insc(cur, c)) { msg("Out of memory"); break; }
                cur++;
                if (!need) need = N_LINE;
                wantcol = colat(lstart(cur), cur);
            }
        }
        if (cur >= LEN()) cur = LEN() - 1;
        if (modified != wasmod) stdirty = 1;
        if (need == N_LINE && (lstart(cur) != l0 || height(l0) != h0)) needfrom(l0 < cur ? l0 : cur);
    }
    ogo(MSGROW, 1); sgr("0"); oeol();
    ogo(STROW, 1); oeol();
    pstr("\r");
}
