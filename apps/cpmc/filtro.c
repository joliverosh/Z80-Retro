/* filtro.c - el puente entre los filtros de Semilla (de stdin a stdout, con
   las opciones en la 1ra linea de la entrada) y CP/M / MP/M.
   El programa se compila con -Dmain=prog_main -Dexit=fexit y OPC=1 si lee
   opciones (OPC=0 si no). Desde la linea de ordenes:
     PROG [opciones] [archivo...] [>salida]
   - Lo que nombra un archivo que existe (admite * y ?) es entrada; si no hay
     ninguno, se lee la consola (^Z al principio de una linea termina).
   - Lo demas son las opciones (la 1ra linea); las que empiezan con '-' pasan
     a minusculas, porque CP/M pone toda la linea en mayusculas.
   - '?' pide las opciones por teclado, con minusculas y mayusculas tal cual.
   - '>ARCH' manda la salida a un archivo.
   Ademas: printf y sprintf (con %f %e %g para float), malloc, free, qsort.
   (C) OLIVEROS 2026 */
#include <string.h>
#include <stdarg.h>
#include <stddef.h>
#include "cpm.h"

#ifndef OPC
#define OPC 1
#endif
int prog_main(void);
void fexit(int);

/* ------------------------------------------------------------ entrada */
static char opt[160];
static uint8_t optn, optp, nopt;     /* nopt: 1 = sin linea de opciones */
static NAME12 files[48];
static uint8_t nf, fi;
static RD rd;
static uint8_t ropen_ = 0, coneof;
static char cline[130];
static uint8_t clen, cpos, cvalid;

static int conchar(void)              /* la consola, por lineas (BDOS 10) */
{
    if (coneof) return -1;
    if (!cvalid) {
        cline[0] = 127; cline[1] = 0;
        bdos(10, (uint16_t)cline);
        putch('\r'); putch('\n');
        clen = cline[1]; cpos = 0; cvalid = 1;
        if (clen && cline[2] == 0x1A) { coneof = 1; return -1; }
    }
    if (cpos < clen) return (uint8_t)cline[2 + cpos++];
    cvalid = 0;
    return '\n';
}
int getchar(void)
{
    int c;
    if (!nopt) {
        if (optp < optn) return (uint8_t)opt[optp++];
        nopt = 1;
        return '\n';
    }
    if (!nf) return conchar();
    for (;;) {
        if (!ropen_) {
            if (fi >= nf) return -1;
            nm2fcb(files[fi++], &rd.f);
            if (ropen(&rd, &rd.f)) continue;
            ropen_ = 1;
        }
        c = rgetc(&rd);
        if (c < 0 || c == 0x1A) { fclose(&rd.f); ropen_ = 0; continue; }
        if (c == '\r') continue;
        return c;
    }
}

/* ------------------------------------------------------------ salida */
static FCB of;
static uint8_t tofile, ob[1024], oerr;     /* 8 registros por llamada al BDOS */
static uint16_t obn;
static void obyte(uint8_t c)
{
    ob[obn++] = c;
    if (obn == 1024) { if (fwriten(&of, ob, 8)) oerr = 1; obn = 0; }
}
int putchar(int c)
{
    if (tofile) { if (c == '\n') obyte('\r'); obyte(c); }
    else { if (c == '\n') putch('\r'); putch(c); }
    return c;
}
int puts(const char *s) { while (*s) putchar(*s++); putchar('\n'); return 1; }
static void finish(void)
{
    if (tofile) {
        if (obn || !oerr) {                 /* ^Z hasta el final del registro */
            do ob[obn++] = 0x1A; while (obn & 127);
            if (fwriten(&of, ob, obn >> 7)) oerr = 1;
            obn = 0;
        }
        fclose(&of);
        if (oerr) pstr("Write error (disk full?)\r\n");
        tofile = 0;
    }
}
void fexit(int c) { (void)c; finish(); bdos(0, 0); }

/* ------------------------------------------------------------ printf */
typedef void (*OUTF)(char);
static char *sp_;
static void outc(char c) { putchar(c); }
static void outs_(char c) { *sp_++ = c; }
static void rep(OUTF o, char c, int16_t n) { while (n-- > 0) o(c); }
static void emit(OUTF o, const char *s, int16_t w, uint8_t left, char pad)
{
    int16_t n = strlen(s);
    if (!left) {
        if (pad == '0' && (*s == '-' || *s == '+')) { o(*s++); n--; w--; }
        rep(o, pad, w - n);
    }
    while (*s) o(*s++);
    if (left) rep(o, ' ', w - n);
}
static char *utoa_(uint32_t v, char *e, uint8_t base, uint8_t up)
{
    *e = 0;
    do { uint8_t d = v % base; *--e = d < 10 ? '0' + d : (up ? 'A' : 'a') + d - 10; v /= base; } while (v);
    return e;
}
#ifdef FLOATS
/* float en texto: f (prec decimales), e o g; en b (40 bytes) */
static void ftoa_(float v, int16_t prec, char conv, char *b)
{
    char *p = b, tmp[14], *t;
    int16_t ex = 0, i;
    uint32_t m;
    float s;
    if (v != v) { strcpy(b, "nan"); return; }
    if (v < 0) { *p++ = '-'; v = -v; }
    if (v > 3.4e38) { strcpy(p, "inf"); return; }
    if (prec < 0) prec = 6;
    if (conv == 'g') {
        if (!prec) prec = 1;
        if (v != 0) {
            s = v;
            while (s >= 10) { s /= 10; ex++; }
            while (s < 1) { s *= 10; ex--; }
            /* redondeo a prec cifras: puede subir el exponente (9,9999995 -> 10) */
            {
                uint32_t lim = 1;
                for (i = 1; i < prec && i < 9; i++) lim *= 10;
                if ((uint32_t)(s * lim + 0.5) >= lim * 10) ex++;
            }
        }
        if (ex < -4 || ex >= prec) { conv = 'E'; prec--; }    /* E: e sin ceros al final */
        else { conv = 'F'; prec = prec - 1 - ex; }
    }
    if (conv == 'f' || conv == 'F') {
        if (prec > 9) prec = 9;
        for (i = 0, s = 1; i < prec; i++) s *= 10;
        if (v * s >= 4.29e9) { conv = conv == 'F' ? 'E' : 'e'; prec = 6; goto expo; }
        m = (uint32_t)(v * s + 0.5);
        t = utoa_(m, tmp + 13, 10, 0);
        i = strlen(t);
        if (i <= prec) { *p++ = '0'; } else { memcpy(p, t, i - prec); p += i - prec; }
        if (prec) {
            char *dot = p;
            *p++ = '.';
            for (; i < prec; i++) *p++ = '0';
            i = strlen(t);
            { int16_t k = i > prec ? i - prec : 0; while (t[k]) *p++ = t[k++]; }
            if (conv == 'F') {           /* %g: sin ceros ni punto al final */
                while (p[-1] == '0') p--;
                if (p - 1 == dot) p--;
            }
        }
        *p = 0;
        return;
    }
expo:
    ex = 0;
    if (v != 0) {
        while (v >= 10) { v /= 10; ex++; }
        while (v < 1) { v *= 10; ex--; }
    }
    if (prec > 8) prec = 8;
    for (i = 0, s = 1; i < prec; i++) s *= 10;
    m = (uint32_t)(v * s + 0.5);
    if (m >= (uint32_t)(s * 10)) { m /= 10; ex++; }
    t = utoa_(m, tmp + 13, 10, 0);
    *p++ = *t++;
    if (prec) {
        char *dot = p;
        *p++ = '.';
        while (*t) *p++ = *t++;
        if (conv == 'E') { while (p[-1] == '0') p--; if (p - 1 == dot) p--; }
    }
    *p++ = 'e';
    *p++ = ex < 0 ? '-' : '+';
    if (ex < 0) ex = -ex;
    if (ex >= 100) { *p++ = '0' + ex / 100; ex %= 100; }
    *p++ = '0' + ex / 10; *p++ = '0' + ex % 10;
    *p = 0;
}
#endif
static void vfmt(OUTF o, const char *f, va_list ap)
{
    char b[44];
    for (; *f; f++) {
        uint8_t left = 0, lng = 0, plus = 0;
        char pad = ' ', c;
        int16_t w = 0, prec = -1;
        if (*f != '%') { o(*f); continue; }
        f++;
        for (;; f++) {
            if (*f == '-') left = 1;
            else if (*f == '0') pad = '0';
            else if (*f == '+') plus = 1;
            else if (*f == ' ' || *f == '#') ;
            else break;
        }
        if (*f == '*') { w = va_arg(ap, int); f++; }
        else while (*f >= '0' && *f <= '9') w = w * 10 + *f++ - '0';
        if (*f == '.') {
            f++; prec = 0;
            if (*f == '*') { prec = va_arg(ap, int); f++; }
            else while (*f >= '0' && *f <= '9') prec = prec * 10 + *f++ - '0';
        }
        while (*f == 'l' || *f == 'h') { if (*f == 'l') lng = 1; f++; }
        c = *f;
        if (!c) break;
        if (left) pad = ' ';
        switch (c) {
        case 'd': case 'i': {
            int32_t v = lng ? va_arg(ap, long) : (int32_t)va_arg(ap, int);
            char *s = utoa_(v < 0 ? -(uint32_t)v : (uint32_t)v, b + 40, 10, 0);
            while (prec > 0 && (b + 40 - s) < prec) *--s = '0';
            if (v < 0) *--s = '-'; else if (plus) *--s = '+';
            emit(o, s, w, left, prec >= 0 ? ' ' : pad);
            break;
        }
        case 'u': case 'x': case 'X': case 'o': {
            uint32_t v = lng ? va_arg(ap, unsigned long) : (uint32_t)va_arg(ap, unsigned);
            char *s = utoa_(v, b + 40, c == 'u' ? 10 : c == 'o' ? 8 : 16, c == 'X');
            while (prec > 0 && (b + 40 - s) < prec) *--s = '0';
            emit(o, s, w, left, prec >= 0 ? ' ' : pad);
            break;
        }
        case 'c': b[0] = va_arg(ap, int); b[1] = 0; emit(o, b, w, left, ' '); break;
        case 's': {
            const char *s = va_arg(ap, const char *);
            if (prec >= 0) {
                int16_t n = 0;
                while (n < prec && n < 40 && s[n]) { b[n] = s[n]; n++; }
                b[n] = 0; s = b;
            }
            emit(o, s, w, left, ' ');
            break;
        }
#ifdef FLOATS
        case 'f': case 'e': case 'g': case 'F': case 'E': case 'G': {
            float v = va_arg(ap, double);       /* (en SDCC, double = float) */
            ftoa_(v, prec, c | 32, plus && v >= 0 ? b + 1 : b);
            if (plus && v >= 0) b[0] = '+';
            emit(o, b, w, left, pad);
            break;
        }
#endif
        default: o(c);
        }
    }
}
int printf(const char *f, ...) { va_list ap; va_start(ap, f); vfmt(outc, f, ap); va_end(ap); return 0; }
int sprintf(char *d, const char *f, ...)
{
    va_list ap; va_start(ap, f);
    sp_ = d; vfmt(outs_, f, ap); *sp_ = 0;
    va_end(ap);
    return sp_ - d;
}

/* ------------------------------------------------------------ memoria */
typedef struct blk { struct blk *nx; uint16_t sz; } BLK;  /* sz en bytes, con la cabecera */
static BLK *freel;
static char *brk_, *top_;
extern char heap[];
void free(void *p)
{
    BLK *b, *q, **pp;
    if (!p) return;
    b = (BLK *)p - 1;
    for (pp = &freel; (q = *pp) && q < b; pp = &q->nx) ;
    b->nx = q; *pp = b;
    if (q && (char *)b + b->sz == (char *)q) { b->sz += q->sz; b->nx = q->nx; }   /* une con el de despues */
    if (pp != &freel) {
        BLK *pr = (BLK *)((char *)pp - offsetof(BLK, nx));
        if ((char *)pr + pr->sz == (char *)b) { pr->sz += b->sz; pr->nx = b->nx; }
    }
}
void *malloc(size_t n)
{
    BLK *b, **pp;
    uint16_t need = (n + sizeof(BLK) + 1) & ~1;
    if (n > 0xF000) return 0;
    for (pp = &freel; (b = *pp); pp = &b->nx)
        if (b->sz >= need) {
            if (b->sz - need >= sizeof(BLK) + 4) {
                BLK *r = (BLK *)((char *)b + need);
                r->sz = b->sz - need; r->nx = b->nx;
                b->sz = need; *pp = r;
            } else *pp = b->nx;
            return b + 1;
        }
    if ((uint16_t)(top_ - brk_) < need) return 0;
    b = (BLK *)brk_; brk_ += need; b->sz = need;
    return b + 1;
}
void *calloc(size_t a, size_t b) { void *p = malloc(a * b); if (p) memset(p, 0, a * b); return p; }
void *realloc(void *p, size_t n)
{
    void *q;
    uint16_t old;
    if (!p) return malloc(n);
    old = ((BLK *)p - 1)->sz - sizeof(BLK);
    if (old >= n) return p;
    q = malloc(n);
    if (q) { memcpy(q, p, old); free(p); }
    return q;
}
static void swapb(char *a, char *b, uint16_t n) { while (n--) { char t = *a; *a++ = *b; *b++ = t; } }
void qsort(void *base, size_t n, size_t sz, int (*cmp)(const void *, const void *))
{
    char *b = base;
    while (n > 1) {                  /* Lomuto; recursa por el lado chico */
        size_t i, k = 0;
        char *piv = b + (n - 1) * sz;
        swapb(b + (n / 2) * sz, piv, sz);
        for (i = 0; i < n - 1; i++)
            if (cmp(b + i * sz, piv) < 0) { swapb(b + i * sz, b + k * sz, sz); k++; }
        swapb(b + k * sz, piv, sz);
        if (k < n - 1 - k) { qsort(b, k, sz, cmp); b += (k + 1) * sz; n -= k + 1; }
        else { qsort(b + (k + 1) * sz, n - 1 - k, sz, cmp); n = k; }
    }
}

/* ------------------------------------------------------------ arranque */
static uint8_t isfile(const char *a)
{
    if (*a == '-' || !a[0]) return 0;
    {
        const char *p = a;
        uint8_t dot = 0, len = 0, i;
        if (a[1] == ':') p += 2;
        for (i = 0; p[i]; i++) {
            if (p[i] == '.') dot++;
            else if (strchr("<>,;=[]|/\\\"'", p[i])) return 0;
            len++;
        }
        if (!len || len > 12 || dot > 1) return 0;
    }
    return glob(a, files + nf, 48 - nf);
}
void main(void)
{
    char *p = args(), *a;
    uint8_t ask = 0;
    brk_ = heap;
    top_ = (char *)(*(uint16_t *)6) - 1536;
    optn = optp = 0;
    nopt = !OPC;
    while ((a = nextarg(&p))) {
        uint8_t n;
        if (*a == '>') {
            a = a[1] ? a + 1 : nextarg(&p);
            if (!a || !mkfcb(&of, a) || fmake(&of)) { pstr("Cannot create the output file\r\n"); return; }
            tofile = 1;
            continue;
        }
        if (a[0] == '?' && !a[1]) { ask = 1; continue; }
        if ((n = isfile(a))) { nf += n; continue; }
        if (optn) opt[optn++] = ' ';
        if (*a == '-') { char *q = a; for (; *q; q++) if (*q >= 'A' && *q <= 'Z') *q += 32; }
        while (*a && optn < sizeof opt - 1) opt[optn++] = *a++;
    }
    if (ask) {
        pstr(OPC ? "Options: " : "Input: ");
        cline[0] = 127; cline[1] = 0;
        bdos(10, (uint16_t)cline);
        pstr("\r\n");
        if (optn) opt[optn++] = ' ';
        { uint8_t i; for (i = 0; i < (uint8_t)cline[1] && optn < sizeof opt - 1; i++) opt[optn++] = cline[2 + i]; }
    }
    if (!OPC && optn) {              /* sin opciones: lo escrito es la entrada */
        nopt = 0;                    /* (sale como una linea) */
        if (!nf) nf = 0, coneof = 1;
    }
    prog_main();
    finish();
}

char *gets(char *s)              /* una linea, sin el \n; 0 al final */
{
    int c;
    char *p = s;
    while ((c = getchar()) >= 0 && c != '\n') *p++ = c;
    *p = 0;
    return c < 0 && p == s ? 0 : s;
}
