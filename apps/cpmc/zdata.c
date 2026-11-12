/* ZDATA - base de datos de fichas para CP/M 2.2, CP/M 3 y MP/M II (terminal ANSI
   de 80x24). Usa archivos .DBF de dBase III (los leen dBase, Clipper, LibreOffice y
   Excel): las fichas quedan en el disco y se leen de a una, asi que el archivo puede
   ser mas grande que la memoria.
   ZDATA [archivo[.DBF]]
   La tabla: flechas (o ^E ^X ^S ^D) mueven, RePag/AvPag, Inicio/Fin (primer y ultimo
   campo), ^R/^C (primera y ultima ficha); Enter cambia el campo; A agrega una ficha,
   F la muestra entera, Supr marca para borrar, B busca, ^L sigue buscando, X filtra,
   O ordena, P limpia lo borrado, I imprime un informe, N crea un archivo, Q sale.
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include <string.h>
#include "cpm.h"

#define MAXF 32                  /* campos */
#define MAXR 1024                /* largo de una ficha */
#define TOP 3                    /* primera fila de fichas en pantalla */
#define NROWS 19                 /* fichas en pantalla */
#define KUP 0x81
#define KDOWN 0x82
#define KRIGHT 0x83
#define KLEFT 0x84
#define KHOME 0x85
#define KEND 0x86
#define KDEL 0x87
#define KPGUP 0x88
#define KPGDN 0x89
#define KINS 0x8A
#define CTRL(c) ((c) & 31)
#define INV ESC "[7m"
#define NORM ESC "[0m"
#define BOLD ESC "[1m"
#define EOL ESC "[K"

extern char heap[];

/* ---------------------------------------------------------------- el archivo */
typedef struct { char name[11]; char type; uint8_t len, dec; uint16_t off; } field;
static field fl[MAXF];
static uint8_t nf;
static uint32_t nrec;            /* fichas */
static uint16_t hlen, rlen;      /* largo del encabezado y de cada ficha */
static FCB df;
static char fname_[16];
static uint8_t isopen;
static uint8_t sec[128];         /* un registro de CP/M */
static uint16_t secn = 0xFFFF;   /* cual */
static uint8_t secdirty;
static uint8_t rec[MAXR + 1];    /* la ficha actual */
static uint32_t recn;            /* cual (desde 1; 0 = ninguna) */
static uint8_t ioerr;

static uint8_t flush_(void)
{
    if (secdirty) { if (rwrite(&df, secn, sec)) ioerr = 1; secdirty = 0; }
    return ioerr;
}
static void getsec(uint16_t n)
{
    if (n == secn) return;
    flush_();
    if (rread(&df, n, sec)) memset(sec, 0x1A, 128);   /* despues del final */
    secn = n;
}
/* bytes [pos, pos + n) del archivo: leer a buf o escribir de buf */
static void fio(uint32_t pos, uint8_t *buf, uint16_t n, uint8_t wr)
{
    static uint16_t s, o, k;
    while (n) {
        s = pos >> 7; o = pos & 127;
        getsec(s);
        k = 128 - o; if (k > n) k = n;
        if (wr) { memcpy(sec + o, buf, k); secdirty = 1; }
        else memcpy(buf, sec + o, k);
        pos += k; buf += k; n -= k;
    }
}
static uint32_t rpos(uint32_t r) { return hlen + (r - 1) * rlen; }
static void getrec(uint32_t r)
{
    if (r == recn) return;
    fio(rpos(r), rec, rlen, 0);
    recn = r;
}
static void putrec(void) { fio(rpos(recn), rec, rlen, 1); }
/* el encabezado: cuantas fichas y la fecha */
static void puthdr(void)
{
    static uint8_t h[8];
    static TOD t;
    static uint16_t y;
    static uint8_t mo, d;
    fio(0, h, 8, 0);
    t.day = 0;
    if (ismpm()) gettod(&t);
    if (t.day) { ymd(t.day, &y, &mo, &d); h[1] = y - 1900; h[2] = mo; h[3] = d; }
    h[4] = nrec; h[5] = nrec >> 8; h[6] = nrec >> 16; h[7] = nrec >> 24;
    fio(0, h, 8, 1);
}
static void closef(void)
{
    if (!isopen) return;
    flush_();
    fclose(&df);
    isopen = 0;
}
static uint8_t openf(const char *name)
{
    static uint8_t h[32];
    static uint16_t off;
    closef();
    if (!mkfcb(&df, name) || fopen(&df)) return 1;
    isopen = 1; secn = 0xFFFF; secdirty = 0; recn = 0; ioerr = 0;
    fio(0, h, 32, 0);
    if (h[0] != 3 && h[0] != 0x83 && h[0] != 0x30) { closef(); return 2; }
    nrec = h[4] | (uint16_t)h[5] << 8 | (uint32_t)h[6] << 16 | (uint32_t)h[7] << 24;
    hlen = h[8] | h[9] << 8;
    rlen = h[10] | h[11] << 8;
    if (rlen > MAXR || rlen < 2) { closef(); return 3; }
    nf = 0; off = 1;
    while (nf < MAXF && 32 + 32 * (uint16_t)nf + 1 < hlen) {
        fio(32 + 32 * (uint16_t)nf, h, 32, 0);
        if (h[0] == 0x0D) break;
        memcpy(fl[nf].name, h, 11); fl[nf].name[10] = 0;
        fl[nf].type = h[11]; fl[nf].len = h[16]; fl[nf].dec = h[17]; fl[nf].off = off;
        off += h[16];
        nf++;
    }
    strncpy(fname_, name, 15);
    return 0;
}
/* archivo nuevo con los campos de fl[] */
static uint8_t createf(const char *name)
{
    static uint8_t h[32];
    static uint8_t i;
    closef();
    if (!mkfcb(&df, name) || fmake(&df)) return 1;
    isopen = 1; secn = 0xFFFF; secdirty = 0; recn = 0; ioerr = 0;
    rlen = 1;
    for (i = 0; i < nf; i++) { fl[i].off = rlen; rlen += fl[i].len; }
    hlen = 32 + 32 * nf + 1;
    nrec = 0;
    memset(h, 0, 32);
    h[0] = 3; h[8] = hlen; h[9] = hlen >> 8; h[10] = rlen; h[11] = rlen >> 8;
    fio(0, h, 32, 1);
    for (i = 0; i < nf; i++) {
        memset(h, 0, 32);
        memcpy(h, fl[i].name, strlen(fl[i].name));
        h[11] = fl[i].type; h[16] = fl[i].len; h[17] = fl[i].dec;
        fio(32 + 32 * i, h, 32, 1);
    }
    h[0] = 0x0D; h[1] = 0x1A;
    fio(hlen - 1, h, 2, 1);
    puthdr();
    flush_();
    strncpy(fname_, name, 15);
    return ioerr;
}
/* una ficha vacia al final */
static uint8_t append(void)
{
    static uint8_t z;
    flush_();
    recn = ++nrec;
    memset(rec, ' ', rlen);
    putrec();
    z = 0x1A;
    fio(rpos(nrec + 1), &z, 1, 1);
    puthdr();
    return flush_();
}

/* ---------------------------------------------------------------- pantalla y teclado */
static uint8_t pk;
static uint8_t soon(void)
{
    static uint8_t n, k;
    k = 0;
    for (n = 0; n < 60 && !(k = getkey()); n++) ;
    return k;
}
static uint8_t key(void)
{
    static int k;
    static uint8_t k2;
    if (pk) { k = pk; pk = 0; return k; }
    oflush();
    while (!(k = getkey())) delay(1);
    if (k == 127) return 8;
    if (k != 27) return k;
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
        case '2': return KINS;
        case '3': return KDEL;
        case '4': return KEND;
        case '5': return KPGUP;
        case '6': return KPGDN;
        }
    return 0;
}
static uint8_t wskey(uint8_t k)       /* el diamante de WordStar */
{
    switch (k) {
    case CTRL('E'): return KUP;
    case CTRL('X'): return KDOWN;
    case CTRL('S'): return KLEFT;
    case CTRL('D'): return KRIGHT;
    }
    return k;
}
static uint8_t msgon;
static void msg(const char *s) { gotoxy(1, 24); pf(INV " %s " NORM EOL, s); msgon = 1; }
static void line(uint8_t r, const char *s) { gotoxy(1, r); pstr(s); pstr(EOL); }
static uint8_t ask(const char *s)
{
    static uint8_t k;
    line(24, s);
    k = key();
    if (k >= 'a' && k <= 'z') k -= 32;
    return k;
}
/* una linea de texto en (x, y), hasta w letras; Enter 1, ESC 0. eb tiene lo que habia */
static char eb[130];
static uint8_t editat(uint8_t x, uint8_t y, uint8_t w, uint8_t upper)
{
    static uint8_t n, p, k, s0;
    n = strlen(eb); if (n > w) n = w; eb[n] = 0;
    p = n;
    pstr(SHOW);
    for (;;) {
        s0 = p > 70 ? p - 70 : 0;
        gotoxy(x, y);
        pstr(INV);
        pstr(eb + s0);
        for (k = n - s0; k < (w < 72 ? w : 72); k++) putch(' ');
        pstr(NORM);
        gotoxy(x + p - s0, y);
        k = wskey(key());
        switch (k) {
        case 13: pstr(HIDE); return 1;
        case 27: pstr(HIDE); return 0;
        case KLEFT: if (p) p--; break;
        case KRIGHT: if (p < n) p++; break;
        case KHOME: case CTRL('A'): p = 0; break;
        case KEND: case CTRL('F'): p = n; break;
        case 8: if (p) { memmove(eb + p - 1, eb + p, n - p + 1); p--; n--; } break;
        case KDEL: case CTRL('G'): if (p < n) { memmove(eb + p, eb + p + 1, n - p); n--; } break;
        case CTRL('Y'): n = p = 0; eb[0] = 0; break;
        default:
            if (k >= 32 && k < 127 && n < w) {
                if (upper && k >= 'a' && k <= 'z') k -= 32;
                memmove(eb + p + 1, eb + p, n - p + 1);
                eb[p++] = k; n++;
            }
        }
    }
}
static uint8_t input(const char *prompt, const char *init)
{
    strcpy(eb, init);
    line(24, prompt);
    return editat(strlen(prompt) + 1, 24, 60, 0);
}

/* ---------------------------------------------------------------- los campos */
/* el texto de un campo de la ficha actual, como se ve (fechas dd/mm/aaaa) */
static uint8_t ftext(uint8_t i, char *o)
{
    static uint8_t *s;
    static uint8_t n;
    s = rec + fl[i].off;
    n = fl[i].len;
    if (fl[i].type == 'D' && n == 8) {
        if (s[0] == ' ') { o[0] = 0; return 0; }
        o[0] = s[6]; o[1] = s[7]; o[2] = '/'; o[3] = s[4]; o[4] = s[5]; o[5] = '/';
        memcpy(o + 6, s, 4); o[10] = 0;
        return 10;
    }
    if (fl[i].type == 'L') { o[0] = s[0] == 'T' || s[0] == 'Y' ? 'Y' : s[0] == 'F' || s[0] == 'N' ? 'N' : ' '; o[1] = 0; return 1; }
    memcpy(o, s, n); o[n] = 0;
    while (n && o[n - 1] == ' ') o[--n] = 0;
    if (fl[i].type == 'N') { s = (uint8_t *)o; while (*s == ' ') s++; memmove(o, s, strlen((char *)s) + 1); n = strlen(o); }
    return n;
}
static uint8_t fwid(uint8_t i)        /* ancho en pantalla */
{
    static uint8_t w, l;
    w = fl[i].type == 'D' ? 10 : fl[i].len;
    l = strlen(fl[i].name);
    if (w < l) w = l;
    if (w > 30) w = 30;
    return w;
}
static uint8_t isdig(char c) { return c >= '0' && c <= '9'; }
/* pone el texto t en el campo i de la ficha actual; 1 si no sirve */
static uint8_t fset(uint8_t i, const char *t)
{
    static uint8_t *d, n, k, j, ip, dp, neg;
    static char b[24];
    d = rec + fl[i].off;
    n = fl[i].len;
    while (*t == ' ') t++;
    switch (fl[i].type) {
    case 'N':                            /* numero: a la derecha, con dec decimales */
        if (!*t) { memset(d, ' ', n); return 0; }
        neg = *t == '-'; if (neg || *t == '+') t++;
        ip = 0; dp = 0; k = 0;
        while (isdig(*t) && ip < 18) b[ip++] = *t++;
        if (*t == '.' || *t == ',') { t++; while (isdig(*t) && dp < 9) { b[ip + dp] = *t++; dp++; } }
        if (*t && *t != ' ') return 1;
        while (dp < fl[i].dec) b[ip + dp++] = '0';
        dp = fl[i].dec;                  /* lo de mas, se corta */
        j = 0;
        { static char o[24]; uint8_t m = 0;
          if (neg) o[m++] = '-';
          if (!ip) o[m++] = '0';
          for (j = 0; j < ip; j++) o[m++] = b[j];
          if (dp) { o[m++] = '.'; for (j = 0; j < dp; j++) o[m++] = b[ip + j]; }
          if (m > n) return 1;
          memset(d, ' ', n - m);
          memcpy(d + n - m, o, m); }
        return 0;
    case 'D':                            /* fecha dd/mm/aaaa -> aaaammdd */
        if (!*t) { memset(d, ' ', n); return 0; }
        { static uint16_t v[3]; uint8_t q = 0;
          v[0] = v[1] = v[2] = 0;
          while (*t && q < 3) {
              if (isdig(*t)) v[q] = v[q] * 10 + *t - '0';
              else if (*t == '/' || *t == '-' || *t == '.') q++;
              else return 1;
              t++;
          }
          if (v[2] < 100) v[2] += v[2] < 70 ? 2000 : 1900;
          if (!v[0] || v[0] > 31 || !v[1] || v[1] > 12 || v[2] > 9999) return 1;
          d[0] = '0' + v[2] / 1000; d[1] = '0' + v[2] / 100 % 10; d[2] = '0' + v[2] / 10 % 10; d[3] = '0' + v[2] % 10;
          d[4] = '0' + v[1] / 10; d[5] = '0' + v[1] % 10; d[6] = '0' + v[0] / 10; d[7] = '0' + v[0] % 10; }
        return 0;
    case 'L':
        k = *t >= 'a' ? *t - 32 : *t;
        if (k == 'Y' || k == 'S' || k == 'T') d[0] = 'T';
        else if (k == 'N' || k == 'F') d[0] = 'F';
        else if (!k) d[0] = ' ';
        else return 1;
        return 0;
    default:                             /* texto */
        k = strlen(t);
        if (k > n) k = n;
        memcpy(d, t, k);
        memset(d + k, ' ', n - k);
        return 0;
    }
}
/* el campo como numero para comparar y sumar: en centesimos... no: como texto
   alineado. Para sumar, valores con dec decimales en un int32 */
static int32_t fnum(uint8_t i)
{
    static uint8_t *s, n, neg, k;
    static int32_t v;
    s = rec + fl[i].off; n = fl[i].len;
    v = 0; neg = 0;
    for (k = 0; k < n; k++) {
        if (s[k] == '-') neg = 1;
        else if (isdig(s[k])) v = v * 10 + s[k] - '0';
    }
    return neg ? -v : v;
}
static uint8_t fold(uint8_t c) { return c >= 'a' && c <= 'z' ? c - 32 : c; }
/* compara el campo i con el texto t: <0, 0, >0 (numeros como numeros, el resto sin
   mayusculas; las fechas como aaaammdd) */
static int8_t fcmp(uint8_t i, const char *t)
{
    static char a[MAXR + 1], b[40];
    static uint8_t k;
    static int32_t x, y;
    if (fl[i].type == 'N') {
        static uint8_t sv[24];
        x = fnum(i);
        memcpy(sv, rec + fl[i].off, fl[i].len);
        if (fset(i, t)) { memcpy(rec + fl[i].off, sv, fl[i].len); return 2; }
        y = fnum(i);
        memcpy(rec + fl[i].off, sv, fl[i].len);
        return x < y ? -1 : x > y;
    }
    if (fl[i].type == 'D') {
        static uint8_t sv[8];
        memcpy(sv, rec + fl[i].off, 8);
        if (fset(i, t)) return 2;
        memcpy(b, rec + fl[i].off, 8); b[8] = 0;
        memcpy(rec + fl[i].off, sv, 8);
        memcpy(a, sv, 8); a[8] = 0;
    } else { ftext(i, a); strncpy(b, t, 39); b[39] = 0; }
    for (k = 0; a[k] && fold(a[k]) == fold(b[k]); k++) ;
    return fold(a[k]) < fold(b[k]) ? -1 : fold(a[k]) > fold(b[k]);
}
static uint8_t has(uint8_t i, const char *w)    /* el campo contiene w (sin mayusculas) */
{
    static char a[MAXR + 1];
    static uint8_t k, j;
    ftext(i, a);
    for (k = 0; a[k]; k++) {
        for (j = 0; w[j] && fold(a[k + j]) == fold(w[j]); j++) ;
        if (!w[j]) return 1;
    }
    return !*w;
}
static uint8_t fieldby(const char *s)          /* el campo de ese nombre o 0xFF */
{
    static uint8_t i, k;
    for (i = 0; i < nf; i++) {
        for (k = 0; fl[i].name[k] && fold(s[k]) == fl[i].name[k]; k++) ;
        if (!fl[i].name[k] && !(isdig(s[k]) || fold(s[k]) >= 'A' && fold(s[k]) <= 'Z' || s[k] == '_')) return i;
    }
    return 0xFF;
}

/* ---------------------------------------------------------------- el filtro */
/* "CAMPO op valor": = <> < > <= >= y $ (contiene) */
static uint8_t xf = 0xFF, xop;   /* campo y operacion (0 ninguno) */
static char xv[40], xtext[60];
static uint8_t passes(uint32_t r)
{
    static int8_t c;
    getrec(r);
    if (xf == 0xFF) return 1;
    if (xop == '$') return has(xf, xv);
    c = fcmp(xf, xv);
    if (c == 2) return 0;
    switch (xop) {
    case '=': return !c;
    case 'n': return c != 0;
    case '<': return c < 0;
    case '>': return c > 0;
    case 'l': return c <= 0;
    case 'g': return c >= 0;
    }
    return 1;
}
static uint8_t setfilter(const char *s)
{
    static char nm[12];
    static uint8_t k, f;
    if (!*s) { xf = 0xFF; xtext[0] = 0; return 0; }
    for (k = 0; k < 11 && s[k] && s[k] != ' ' && !strchr("=<>$", s[k]); k++) nm[k] = s[k];
    nm[k] = 0;
    if ((f = fieldby(nm)) == 0xFF) return 1;
    s += k;
    while (*s == ' ') s++;
    if (s[0] == '<' && s[1] == '>') { xop = 'n'; s += 2; }
    else if (s[0] == '<' && s[1] == '=') { xop = 'l'; s += 2; }
    else if (s[0] == '>' && s[1] == '=') { xop = 'g'; s += 2; }
    else if (strchr("=<>$", *s) && *s) xop = *s++;
    else return 1;
    while (*s == ' ') s++;
    strncpy(xv, s, 39);
    if (*xv == '"') { memmove(xv, xv + 1, strlen(xv)); if (*xv && xv[strlen(xv) - 1] == '"') xv[strlen(xv) - 1] = 0; }
    xf = f;
    return 0;
}
static uint32_t nextok(uint32_t r, int8_t dir)   /* la siguiente ficha que pasa el filtro, o 0 */
{
    while (1) {
        if (dir > 0) { if (r >= nrec) return 0; r++; }
        else { if (r <= 1) return 0; r--; }
        if (passes(r)) return r;
    }
}

/* ---------------------------------------------------------------- la tabla */
static uint32_t top, cur;        /* primera ficha en pantalla y la del cursor */
static uint8_t cf, lf;           /* campo del cursor y primer campo en pantalla */
static uint8_t nvis;             /* campos que entran */
static uint8_t dirty;
static char tb[MAXR + 1];
static void colsfit(void)
{
    static uint8_t x, i;
    if (cf < lf) lf = cf;
    for (;;) {
        x = 9;
        for (i = lf; i < nf && x + fwid(i) <= 80; i++) x += fwid(i) + 1;
        nvis = i - lf;
        if (cf < lf + nvis || lf >= cf) break;
        lf++;
    }
}
static void drawrow(uint8_t row, uint32_t r)
{
    static uint8_t i, w, n, x;
    gotoxy(1, row);
    if (!r) { pstr(EOL); return; }
    getrec(r);
    pf("%c%6lu ", rec[0] == '*' ? '*' : ' ', r);
    x = 9;
    for (i = lf; i < lf + nvis; i++) {
        w = fwid(i);
        n = ftext(i, tb);
        if (n > w) { tb[w] = 0; n = w; }
        if (r == cur && i == cf) pstr(INV);
        if (fl[i].type == 'N') { while (n < w) { putch(' '); n++; } pstr(tb); }
        else { pstr(tb); while (n < w) { putch(' '); n++; } }
        if (r == cur && i == cf) pstr(NORM);
        putch(' ');
        x += w + 1;
    }
    pstr(EOL);
}
static void drawhdr(void)
{
    static uint8_t i, w, n;
    gotoxy(1, 1);
    pstr(INV);
    pf(" ZDATA  %s  %lu records", fname_, nrec);
    if (xf != 0xFF) pf("  filter: %s", xtext);
    pstr(EOL NORM);
    gotoxy(1, 2);
    pstr(BOLD "        ");
    for (i = lf; i < lf + nvis; i++) {
        w = fwid(i);
        n = strlen(fl[i].name);
        if (fl[i].type == 'N') { while (n < w) { putch(' '); n++; } pstr(fl[i].name); }
        else { pstr(fl[i].name); while (n < w) { putch(' '); n++; } }
        putch(' ');
    }
    pstr(NORM EOL);
}
static void drawall(void)
{
    static uint8_t j;
    static uint32_t r;
    colsfit();
    drawhdr();
    r = top;
    for (j = 0; j < NROWS; j++) {
        drawrow(TOP + j, r);
        if (r) r = nextok(r, 1);
    }
    line(23, ESC "[2m Enter edit  A add  F form  Del delete  B find  X filter  O sort  ? more Q quit" NORM);
    dirty = 0;
}
/* deja cur a la vista (top) */
static void scroll(void)
{
    static uint8_t j;
    static uint32_t r;
    if (!cur) { top = 0; return; }
    if (cur < top || !top) { top = cur; dirty = 1; return; }
    r = top;
    for (j = 0; j < NROWS - 1 && r && r != cur; j++) r = nextok(r, 1);
    if (r != cur) {                       /* cur esta mas abajo: que quede en la ultima fila */
        top = cur;
        for (j = 0; j < NROWS - 1; j++) { r = nextok(top, -1); if (!r) break; top = r; }
        dirty = 1;
    }
}
static void first(void) { cur = passes(1) ? 1 : nextok(1, 1); if (!nrec) cur = 0; top = cur; dirty = 1; }

/* cambia el campo cf de la ficha cur en (x, y) */
static void editfield(uint8_t x, uint8_t y)
{
    static uint8_t w;
    if (!cur) return;
    getrec(cur);
    ftext(cf, eb);
    w = fl[cf].type == 'D' ? 10 : fl[cf].len;
    for (;;) {
        if (!editat(x, y, w, 0)) return;
        if (!fset(cf, eb)) break;
        msg(fl[cf].type == 'N' ? "Not a number (or too long)" : fl[cf].type == 'D' ? "Date: dd/mm/yyyy" : "Y or N");
    }
    putrec();
    if (flush_()) msg("Write error (disk full?)");
}
static uint8_t cellx(void)
{
    static uint8_t x, i;
    x = 9;
    for (i = lf; i < cf; i++) x += fwid(i) + 1;
    return x;
}
static uint8_t currow(void)
{
    static uint8_t j;
    static uint32_t r;
    r = top;
    for (j = 0; j < NROWS && r; j++) { if (r == cur) return TOP + j; r = nextok(r, 1); }
    return TOP;
}

/* F: la ficha entera, un campo por fila */
static void form(void)
{
    static uint8_t i, k, j, w, n;
    if (!cur) return;
    i = 0;
    for (;;) {
        getrec(cur);
        pstr(CLS);
        pf(INV " ZDATA  %s  record %lu of %lu%s" EOL NORM, fname_, cur, nrec, rec[0] == '*' ? "  (deleted)" : "");
        for (j = 0; j < nf && j < 20; j++) {
            gotoxy(2, 3 + j);
            pf("%-10s ", fl[j].name);
            n = ftext(j, tb); w = fl[j].len; if (w > 60) w = 60;
            if (n > 60) tb[60] = 0;
            if (j == i) pstr(INV);
            pstr(tb);
            for (; n < w; n++) putch(' ');
            if (j == i) pstr(NORM);
        }
        line(24, ESC "[2m Up/Down field  Enter edit  PgUp/PgDn record  ESC back" NORM);
        k = wskey(key());
        if (k == KUP && i) i--;
        else if (k == KDOWN && i + 1 < nf && i < 19) i++;
        else if (k == KPGDN || k == CTRL('C')) { uint32_t r = nextok(cur, 1); if (r) cur = r; }
        else if (k == KPGUP || k == CTRL('R')) { uint32_t r = nextok(cur, -1); if (r) cur = r; }
        else if (k == 13) { cf = i; editfield(13, 3 + i); }
        else if (k == 27 || k == 'q' || k == 'Q') break;
    }
    pstr(CLS);
    dirty = 1;
}

/* B: busca un texto en el campo del cursor, desde la ficha siguiente */
static char ftxt[40];
static void findnext(void)
{
    static uint32_t r;
    if (!cur || !*ftxt) return;
    for (r = nextok(cur, 1); r; r = nextok(r, 1)) if (has(cf, ftxt)) { cur = r; return; }
    msg("Not found");
}

/* O: ordena por el campo del cursor; escribe las fichas en el nuevo orden en un .$$$
   y despues cambia los nombres */
static void sortf(void)
{
    static uint8_t desc, kl, i, *keys;
    static uint16_t n, j, *idx, t;
    static uint16_t avail;
    static FCB nf_;
    static uint8_t rn[36];
    if (nrec < 2) return;
    desc = ask("Sort by this field: A(scending) D(escending)");
    if (desc != 'A' && desc != 'D') return;
    desc = desc == 'D';
    kl = fl[cf].type == 'N' ? 4 : fl[cf].len; if (kl > 20) kl = 20;
    avail = (uint16_t)((uint8_t *)&avail) - (uint16_t)heap - 1024;
    if (nrec > 8000 || nrec * (kl + 2) > avail) { msg("Too many records to sort in memory"); return; }
    n = nrec;
    keys = (uint8_t *)heap;
    idx = (uint16_t *)(heap + n * kl);
    line(24, "Sorting...");
    for (j = 0; j < n; j++) {               /* las claves: el texto (los numeros a la derecha ya) */
        getrec(j + 1);
        if (fl[cf].type == 'N') {         /* numero: 4 bytes que se comparan como texto */
            static uint32_t v;
            v = (uint32_t)fnum(cf) ^ 0x80000000UL;
            keys[j * kl] = v >> 24; keys[j * kl + 1] = v >> 16; keys[j * kl + 2] = v >> 8; keys[j * kl + 3] = v;
        } else {
            memcpy(keys + j * kl, rec + fl[cf].off, kl);
            for (i = 0; i < kl; i++) keys[j * kl + i] = fold(keys[j * kl + i]);
        }
        idx[j] = j;
    }
    {                                       /* Shell, con los saltos de Knuth */
        static uint16_t gap, a, b;
        static int16_t c;
        for (gap = 1; gap < n / 3; gap = gap * 3 + 1) ;
        for (; gap; gap /= 3)
            for (a = gap; a < n; a++) {
                t = idx[a];
                for (b = a; b >= gap; b -= gap) {
                    c = memcmp(keys + idx[b - gap] * kl, keys + t * kl, kl);
                    if (desc) c = -c;
                    if (c <= 0) break;
                    idx[b] = idx[b - gap];
                }
                idx[b] = t;
            }
    }
    /* el archivo nuevo: el encabezado tal cual y las fichas en orden */
    flush_();
    memcpy(&nf_, &df, sizeof nf_);
    memcpy(nf_.f + 8, "$$$", 3);
    nf_.ex = nf_.s2 = nf_.cr = 0;
    if (fmake(&nf_)) { msg("Cannot create the file"); return; }
    {
        static uint32_t pos, end;
        static uint8_t ob[128];
        static uint16_t op, rr;
        static uint8_t c;
        op = 0; rr = 0;
        end = rpos(n + 1);
        for (pos = 0; pos < hlen; pos++) { fio(pos, &c, 1, 0); ob[op++] = c; if (op == 128) { if (rwrite(&nf_, rr++, ob)) ioerr = 1; op = 0; } }
        for (j = 0; j < n; j++) {
            getrec(idx[j] + 1);
            for (i = 0; i < rlen; i++) { ob[op++] = rec[i]; if (op == 128) { if (rwrite(&nf_, rr++, ob)) ioerr = 1; op = 0; } }
            if (i < rlen) break;
        }
        ob[op++] = 0x1A;
        while (op < 128) ob[op++] = 0x1A;
        if (rwrite(&nf_, rr, ob)) ioerr = 1;
        (void)end;
    }
    fclose(&nf_);
    if (ioerr) { fdelete(&nf_); msg("Write error (disk full?)"); return; }
    closef();
    fdelete(&df);
    memset(rn, 0, 36);
    memcpy(rn, &nf_, 12);
    memcpy(rn + 17, df.f, 11);
    bdos(23, (uint16_t)rn);
    strcpy(eb, fname_);
    openf(eb);
    first();
}
/* P: saca las fichas marcadas (las corre hacia arriba en el mismo archivo) */
static void pack(void)
{
    static uint32_t r, w;
    static uint8_t z;
    if (ask("Remove the deleted records for good? (Y/N)") != 'Y') return;
    line(24, "Packing...");
    w = 0;
    for (r = 1; r <= nrec; r++) {
        getrec(r);
        if (rec[0] == '*') continue;
        w++;
        if (w != r) { recn = w; putrec(); }
    }
    nrec = w;
    z = 0x1A;
    fio(rpos(nrec + 1), &z, 1, 1);
    puthdr();
    recn = 0;
    if (flush_()) msg("Write error");
    first();
}

/* I: informe con los campos que entran en 132 columnas (o 80), totales de los numeros */
static FCB of;
static uint8_t ob[128], obp, odev, oerr;
static void oc(char c)
{
    if (odev) { bdos(5, (uint8_t)c); return; }
    ob[obp++] = c;
    if (obp == 128) { if (fwrite(&of, ob)) oerr = 1; obp = 0; }
}
static void os(const char *s) { while (*s) oc(*s++); }
static void osp(uint8_t n) { while (n--) oc(' '); }
static void report(void)
{
    static uint8_t i, w, n, k, pw, cols, line_, page;
    static int32_t tot[MAXF];
    static uint32_t r, cnt;
    static char *d;
    if (!nrec) return;
    if (!input("Report to file (Enter = printer): ", "")) return;
    odev = !eb[0];
    if (!odev) {
        for (d = eb; *d; d++) if (*d >= 'a' && *d <= 'z') *d -= 32;
        if (!strchr(eb, '.')) strcat(eb, ".PRN");
        if (!mkfcb(&of, eb) || fmake(&of)) { msg("Cannot create the file"); return; }
        obp = 0; oerr = 0;
    }
    pw = ask("Width: 8(0) or 1(32) columns") == '1' ? 132 : 80;
    if (!input("Title: ", "")) { if (!odev) fclose(&of); return; }
    strcpy(tb, eb);
    line(24, "Printing...");
    cols = 0; w = 0;
    for (i = 0; i < nf && w + fwid(i) + 1 <= pw; i++) { w += fwid(i) + 1; cols++; tot[i] = 0; }
    line_ = 99; page = 0; cnt = 0;
    for (r = 1; r <= nrec; r++) {
        if (!passes(r) || rec[0] == '*') continue;
        if (line_ >= 58) {
            if (page) oc(12);
            page++;
            os(tb); osp(pw > strlen(tb) + 10 ? pw - strlen(tb) - 10 : 1); os("Page "); oc('0' + page / 10 % 10); oc('0' + page % 10); os("\r\n\r\n");
            for (i = 0; i < cols; i++) {
                w = fwid(i); n = strlen(fl[i].name);
                if (fl[i].type == 'N') { osp(w - n); os(fl[i].name); } else { os(fl[i].name); osp(w - n); }
                oc(' ');
            }
            os("\r\n");
            for (i = 0; i < cols; i++) { for (k = 0; k < fwid(i); k++) oc('-'); oc(' '); }
            os("\r\n");
            line_ = 4;
        }
        for (i = 0; i < cols; i++) {
            w = fwid(i);
            n = ftext(i, eb); if (n > w) { eb[w] = 0; n = w; }
            if (fl[i].type == 'N') { osp(w - n); os(eb); tot[i] += fnum(i); } else { os(eb); osp(w - n); }
            oc(' ');
        }
        os("\r\n");
        line_++; cnt++;
    }
    for (i = 0; i < cols; i++) { for (k = 0; k < fwid(i); k++) oc(fl[i].type == 'N' ? '=' : ' '); oc(' '); }
    os("\r\n");
    for (i = 0; i < cols; i++) {             /* totales */
        w = fwid(i);
        if (fl[i].type == 'N') {
            static char t[16];
            static int32_t v;
            static uint8_t m, neg;
            v = tot[i]; neg = v < 0; if (neg) v = -v;
            m = 0;
            do { if (fl[i].dec && m == fl[i].dec) t[m++] = '.'; t[m++] = '0' + v % 10; v /= 10; } while (v || m <= fl[i].dec);
            if (neg) t[m++] = '-';
            osp(w > m ? w - m : 0);
            while (m) oc(t[--m]);
        } else if (!i) { os("Total"); osp(w > 5 ? w - 5 : 0); }
        else osp(w);
        oc(' ');
    }
    os("\r\n\r\n");
    { static char t[12]; static uint8_t m; m = 0; do { t[m++] = '0' + cnt % 10; cnt /= 10; } while (cnt); while (m) oc(t[--m]); }
    os(" records\r\n");
    if (odev) oc(12);
    else {
        if (obp) { memset(ob + obp, 26, 128 - obp); if (fwrite(&of, ob)) oerr = 1; }
        fclose(&of);
    }
    msg(oerr ? "Write error (disk full?)" : "Report done");
}

/* N: archivo nuevo: los campos uno por uno */
static void create(void)
{
    static char name[16], *d;
    static uint8_t k, t, len, dec;
    if (!input("New file: ", "")) return;
    if (!eb[0]) return;
    for (d = eb; *d; d++) if (*d >= 'a' && *d <= 'z') *d -= 32;
    if (!strchr(eb, '.')) strcat(eb, ".DBF");
    strncpy(name, eb, 15);
    nf = 0;
    pstr(CLS);
    pf(INV " ZDATA  new file %s: the fields (Enter with no name ends)" EOL NORM "\r\n\r\n", name);
    while (nf < MAXF) {
        gotoxy(1, 3 + nf); pf("%2u name: ", nf + 1);
        eb[0] = 0;
        if (!editat(11, 3 + nf, 10, 1) || !eb[0]) break;
        if (fieldby(eb) != 0xFF) { msg("That name is taken"); continue; }
        strncpy(fl[nf].name, eb, 10); fl[nf].name[10] = 0;
        gotoxy(23, 3 + nf); pstr("type C(text) N(number) D(date) L(Y/N): ");
        do { t = key(); if (t >= 'a') t -= 32; } while (!strchr("CNDL\033", t));
        if (t == 27) break;
        putch(t);
        len = t == 'D' ? 8 : t == 'L' ? 1 : 0; dec = 0;
        if (!len) {
            gotoxy(66, 3 + nf); pstr("width: ");
            strcpy(eb, t == 'N' ? "10" : "20");
            if (!editat(73, 3 + nf, 3, 0)) break;
            for (d = eb, len = 0; isdig(*d); d++) len = len * 10 + *d - '0';
            if (!len || (t == 'N' && len > 18) || len > 254) { msg("Bad width"); continue; }
            if (t == 'N') {
                gotoxy(66, 3 + nf); pstr("decimals: ");
                strcpy(eb, "0");
                if (!editat(76, 3 + nf, 1, 0)) break;
                dec = eb[0] - '0';
                if (dec > 9 || dec + 2 > len) dec = 0;
            }
        }
        fl[nf].type = t; fl[nf].len = len; fl[nf].dec = dec;
        nf++;
    }
    if (!nf) { pstr(CLS); if (isopen) { strcpy(eb, fname_); openf(eb); } dirty = 1; return; }
    if (createf(name)) msg("Cannot create the file");
    pstr(CLS);
    cur = top = 0; cf = lf = 0;
    xf = 0xFF;
    dirty = 1;
}

static void help(void)
{
    pstr(CLS "ZDATA - a card file on dBase III files (.DBF)                    (C) OLIVEROS 2026\r\n\r\n"
         " Arrows or ^E ^X ^S ^D move, PgUp/PgDn (^R ^C at the edges: first/last record),\r\n"
         " Home/End: first/last field.\r\n\r\n"
         " Enter  change the field          A  add a record (Ins too)\r\n"
         " F      the whole record          Del  mark/unmark for deletion (*)\r\n"
         " B      find text in this field   ^L  find the next one\r\n"
         " X      filter: FIELD op value (= <> < > <= >= and $ for contains);\r\n"
         "        Enter alone removes it.   Example: CITY $ cali   AMOUNT >= 1000\r\n"
         " O      sort the file by this field (it rewrites the file)\r\n"
         " P      pack: remove the deleted records\r\n"
         " I      report to the printer or a .PRN file, with totals\r\n"
         " N      new file (the fields: name, type C N D L, width, decimals)\r\n"
         " Q      quit\r\n\r\n"
         " Dates are typed dd/mm/yyyy. The files are dBase III: dBase, Clipper,\r\n"
         " LibreOffice and Excel read them. Every change is written at once.\r\n\r\n"
         " Press any key.");
    key();
    pstr(CLS);
    dirty = 1;
}

void main(void)
{
    static char *a, *f, *d;
    static uint8_t k, e, r;
    static uint32_t o;
    a = args();
    f = nextarg(&a);
    pstr(HIDE CLS);
    if (f && *f) {
        strncpy(eb, f, 15); eb[15] = 0;
        for (d = eb; *d; d++) if (*d >= 'a' && *d <= 'z') *d -= 32;
        if (!strchr(eb, '.')) strcat(eb, ".DBF");
        e = openf(eb);
        if (e == 1) { strcpy(tb, eb); create(); if (!isopen) { pstr(SHOW CLS); return; } (void)tb; }
        else if (e) { pstr(SHOW "Not a dBase III file\r\n"); return; }
    } else create();
    if (!isopen) { pstr(SHOW CLS); return; }
    first();
    for (;;) {
        scroll();
        if (dirty) drawall();
        if (!msgon) line(24, "");
        msgon = 0;
        r = currow();
        if (cur) drawrow(r, cur);
        gotoxy(1, r);
        k = wskey(key());
        o = cur;
        switch (k) {
        case KUP: if (cur) { uint32_t q = nextok(cur, -1); if (q) cur = q; } break;
        case KDOWN: if (cur) { uint32_t q = nextok(cur, 1); if (q) cur = q; } break;
        case KLEFT: if (cf) cf--; dirty = cf < lf; break;
        case KRIGHT: if (cf + 1 < nf) cf++; dirty = cf >= lf + nvis; break;
        case KHOME: cf = 0; dirty = 1; break;
        case KEND: cf = nf - 1; dirty = 1; break;
        case KPGDN: case KPGUP: {
            uint8_t j; uint32_t q;
            for (j = 0; j < NROWS - 1; j++) { q = nextok(cur, k == KPGDN ? 1 : -1); if (!q) break; cur = q; }
            dirty = 1;
            break;
        }
        case CTRL('R'): first(); break;
        case CTRL('C'): { uint32_t q = nrec + 1; q = nextok(q, -1); if (q) cur = q; dirty = 1; break; }
        case 13: editfield(cellx(), r); dirty = 1; break;
        case 'a': case 'A': case KINS:
            if (xf != 0xFF) { xf = 0xFF; xtext[0] = 0; }
            if (append()) { msg("Write error (disk full?)"); break; }
            cur = nrec; cf = 0; dirty = 1;
            scroll(); drawall();
            editfield(cellx(), currow());
            dirty = 1;
            break;
        case KDEL: case 'd': case 'D':
            if (!cur) break;
            getrec(cur);
            rec[0] = rec[0] == '*' ? ' ' : '*';
            putrec();
            if (flush_()) msg("Write error");
            break;
        case 'f': case 'F': form(); break;
        case 'b': case 'B':
            if (!input("Find in this field: ", ftxt)) break;
            strncpy(ftxt, eb, 39);
            findnext();
            break;
        case CTRL('L'): findnext(); break;
        case 'x': case 'X':
            if (!input("Filter (FIELD op value; Enter alone: none): ", xtext)) break;
            strncpy(xtext, eb, 59);
            if (setfilter(xtext)) { msg("Use: FIELD op value  (= <> < > <= >= $)"); xf = 0xFF; xtext[0] = 0; }
            first();
            if (!cur && xf != 0xFF) msg("No record passes the filter");
            break;
        case 'o': case 'O': sortf(); dirty = 1; break;
        case 'p': case 'P': pack(); break;
        case 'i': case 'I': report(); dirty = 1; break;
        case 'n': case 'N': create(); if (isopen) first(); else { pstr(SHOW CLS); return; } break;
        case '?': help(); break;
        case CTRL('J'): help(); break;
        case 'q': case 'Q': case 27:
            closef();
            pstr(SHOW CLS);
            return;
        }
        if (cur != o && !dirty) { drawrow(r, o); }
    }
}
