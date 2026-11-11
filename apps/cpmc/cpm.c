/* cpm.c - BDOS, consola, printf chico y archivos para CP/M y MP/M II (SDCC) */
#include <stdarg.h>
#include <string.h>
#include "cpm.h"

uint16_t zde, zhl;

/* La salida a la consola se junta en ob[] y sale de una vez con el servicio
   46 del XIOS de ZEPHYRUS (sin pasar por el BDOS: la mitad de ciclos por
   caracter). En CP/M o con un MP/M sin ese servicio, cada caracter va por el
   BDOS 6 como antes. Cualquier llamada al BDOS vacia ob[] antes. */
#define OBSZ 128
uint8_t obn;
static uint8_t ob[OBSZ], omode;     /* 0 sin decidir, 1 servicio 46, 2 BDOS */

uint16_t bdos(uint8_t c, uint16_t de) __sdcccall(0) __naked
{
    (void)c; (void)de;
    __asm
        ld      a,(_obn)
        or      a
        call    nz,_oflush
        ld      hl,#2
        add     hl,sp
        ld      c,(hl)
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        push    ix
        push    iy
        call    5
        pop     iy
        pop     ix
        ld      l,a             ; (por convencion A = L y B = H)
        ret
    __endasm;
}

/* zios: RST 30h con C, B, DE, HL. Devuelve A; DE y HL en zde, zhl */
uint8_t zios(uint8_t c, uint8_t b, uint16_t de, uint16_t hl) __sdcccall(0) __naked
{
    (void)c; (void)b; (void)de; (void)hl;
    __asm
        push    ix
        push    iy
        ld      ix,#6
        add     ix,sp
        ld      c,0(ix)
        ld      b,1(ix)
        ld      e,2(ix)
        ld      d,3(ix)
        ld      l,4(ix)
        ld      h,5(ix)
        rst     0x30
        ld      (_zde),de
        ld      (_zhl),hl
        pop     iy
        pop     ix
        ld      l,a
        ret
    __endasm;
}

void oflush(void)
{
    uint8_t n = obn;
    obn = 0;
    if (n) zios(46, 0, n, (uint16_t)ob);
}

static void putchs(char c)          /* sin decidir, o por el BDOS */
{
    if (!omode) {
        omode = 2;
        if (ismpm() && zios(46, 0, 0, 0) == 0) { omode = 1; putch(c); return; }
    }
    if ((uint8_t)c >= 0xFE) bdos(2, (uint8_t)c);
    else bdos(6, (uint8_t)c);
}

/* putch: lo de cada caracter, en asm (unos 90 ciclos en vez de 300) */
void putch(char c) __naked
{
    (void)c;
    __asm
        ld      c,a
        ld      a,(_omode)
        dec     a
        jr      z,putch1
        ld      a,c
        jp      _putchs
putch1:
        ld      hl,#_obn
        ld      a,(hl)
        inc     (hl)
        ld      e,a
        ld      d,#0
        ld      hl,#_ob
        add     hl,de
        ld      (hl),c
        cp      #OBSZ-1
        ret     nz
        jp      _oflush
    __endasm;
}

void pstr(const char *s)
{
    while (*s) {
        if (*s == '\n') putch('\r');
        putch(*s++);
    }
}

static uint8_t hexa;
static void pnum(uint32_t v, uint8_t base, uint8_t w, char pad, uint8_t neg)
{
    char b[12]; uint8_t n = 0;
    do { uint8_t d = v % base; b[n++] = d < 10 ? '0' + d : hexa + d - 10; v /= base; } while (v);
    if (neg) b[n++] = '-';
    while (n < w) { putch(pad); w--; }
    while (n) putch(b[--n]);
}

void pf(const char *fmt, ...)
{
    va_list ap; va_start(ap, fmt);
    while (*fmt) {
        char c = *fmt++;
        if (c != '%') { if (c == '\n') putch('\r'); putch(c); continue; }
        char pad = ' '; uint8_t w = 0, lng = 0;
        if (*fmt == '0') { pad = '0'; fmt++; }
        while (*fmt >= '0' && *fmt <= '9') w = w * 10 + (*fmt++ - '0');
        if (*fmt == 'l') { lng = 1; fmt++; }
        c = *fmt++;
        if (c == 'd') {
            int32_t v = lng ? va_arg(ap, int32_t) : (int32_t)va_arg(ap, int);
            if (v < 0) pnum((uint32_t)-v, 10, w, pad, 1); else pnum(v, 10, w, pad, 0);
        } else if (c == 'u' || c == 'x' || c == 'X') {
            uint32_t v = lng ? va_arg(ap, uint32_t) : (uint32_t)va_arg(ap, unsigned);
            hexa = c == 'x' ? 'a' : 'A';
            pnum(v, c == 'u' ? 10 : 16, w, pad, 0);
        } else if (c == 's') {
            const char *s = va_arg(ap, const char *);
            uint8_t n = strlen(s);
            while (n < w) { putch(' '); w--; }
            pstr(s);
        } else if (c == 'c') putch((char)va_arg(ap, int));
        else putch(c);
    }
    va_end(ap);
}

int getkey(void) { return bdos(6, 0xFF) & 0xFF; }

int waitkey(void)
{
    int k;
    while (!(k = getkey())) delay(1);
    return k;
}

static uint8_t mpm = 0xFF;
uint8_t ismpm(void)
{
    if (mpm == 0xFF) mpm = (bdos(12, 0) >> 8) == 1;
    return mpm;
}

void delay(uint16_t t) { if (ismpm()) bdos(141, t); }

static char up(char c) { return c >= 'a' && c <= 'z' ? c - 32 : c; }

uint8_t mkfcb(FCB *f, const char *s)
{
    uint8_t i;
    memset(f, 0, sizeof(FCB));
    memset(f->f, ' ', 11);
    while (*s == ' ') s++;
    if (!*s) return 0;
    if (s[1] == ':') { f->dr = up(s[0]) - 'A' + 1; if (f->dr > 16) return 0; s += 2; }
    for (i = 0; i < 8 && *s && *s != '.'; s++) {
        if (*s == '*') { while (i < 8) f->f[i++] = '?'; continue; }
        f->f[i++] = up(*s);
    }
    while (*s && *s != '.') s++;
    if (*s == '.') {
        s++;
        for (i = 8; i < 11 && *s; s++) {
            if (*s == '*') { while (i < 11) f->f[i++] = '?'; continue; }
            f->f[i++] = up(*s);
        }
    }
    return f->f[0] != ' ';
}

uint8_t fopen(FCB *f) { f->ex = f->s2 = f->cr = 0; return (bdos(15, (uint16_t)f) & 0xFF) == 0xFF; }
void fclose(FCB *f) { bdos(16, (uint16_t)f); }
uint8_t fread(FCB *f, uint8_t *buf) { bdos(26, (uint16_t)buf); return bdos(20, (uint16_t)f) & 0xFF; }
uint8_t fwrite(FCB *f, uint8_t *buf) { bdos(26, (uint16_t)buf); return bdos(21, (uint16_t)f) & 0xFF; }
uint8_t fmake(FCB *f)
{
    bdos(19, (uint16_t)f);
    f->ex = f->s2 = f->cr = 0;
    return (bdos(22, (uint16_t)f) & 0xFF) == 0xFF;
}
uint16_t fsize(FCB *f) { bdos(35, (uint16_t)f); return f->r0 | (f->r1 << 8); }

char *args(void)
{
    static char line[130];
    uint8_t n = *(uint8_t *)0x80, i;
    for (i = 0; i < n; i++) line[i] = ((char *)0x81)[i];
    line[n] = 0;
    return line;
}

char *nextarg(char **p)
{
    char *s = *p, *r;
    while (*s == ' ') s++;
    if (!*s) { *p = s; return 0; }
    r = s;
    while (*s && *s != ' ') s++;
    if (*s) *s++ = 0;
    *p = s;
    return r;
}

void fname(FCB *f, char *o)
{
    uint8_t i;
    if (f->dr) { *o++ = 'A' + f->dr - 1; *o++ = ':'; }
    for (i = 0; i < 8 && f->f[i] != ' '; i++) *o++ = f->f[i] & 0x7F;
    if ((f->f[8] & 0x7F) != ' ') {
        *o++ = '.';
        for (i = 8; i < 11 && (f->f[i] & 0x7F) != ' '; i++) *o++ = f->f[i] & 0x7F;
    }
    *o = 0;
}

uint16_t ticks(void) { zios(31, 0, 0, 0); return zhl; }
uint8_t tps(void) { return zios(31, 0, 0, 0); }

uint16_t sysdat(void) { return bdos(154, 0); }
uint16_t datapg(void) { return *(uint16_t *)(sysdat() + 252); }
uint8_t mycons(void) { return bdos(153, 0) & 0xFF; }
void gettod(TOD *t) { bdos(155, (uint16_t)t); }
uint8_t bcd(uint8_t b) { return (b >> 4) * 10 + (b & 15); }
void ymd(uint16_t day, uint16_t *y, uint8_t *mo, uint8_t *d)
{
    static const uint8_t ml[12] = {31,28,31,30,31,30,31,31,30,31,30,31};
    uint16_t yr = 1978; uint8_t m = 0;
    for (;;) {
        uint16_t n = (yr & 3) ? 365 : 366;
        if (day <= n) break;
        day -= n; yr++;
    }
    for (;;) {
        uint8_t n = ml[m] + (m == 1 && !(yr & 3));
        if (day <= n) break;
        day -= n; m++;
    }
    *y = yr; *mo = m + 1; *d = day;
}
static uint16_t rs = 12345;
uint16_t rnd(void) { rs ^= rs << 7; rs ^= rs >> 9; rs ^= rs << 8; return rs; }
void srnd(uint16_t s) { rs = s ? s : 1; }
void gotoxy(uint8_t x, uint8_t y) { pf(ESC "[%u;%uH", y, x); }

uint8_t fdelete(FCB *f) { return (bdos(19, (uint16_t)f) & 0xFF) == 0xFF; }
static uint8_t rio(uint8_t fn, FCB *f, uint16_t rec, uint8_t *buf)
{
    f->r0 = rec; f->r1 = rec >> 8; f->r2 = 0;
    bdos(26, (uint16_t)buf);
    return bdos(fn, (uint16_t)f) & 0xFF;
}
uint8_t rread(FCB *f, uint16_t rec, uint8_t *buf) { return rio(33, f, rec, buf); }
uint8_t rwrite(FCB *f, uint16_t rec, uint8_t *buf) { return rio(34, f, rec, buf); }

uint8_t glob(const char *spec, NAME12 *out, uint8_t max)
{
    static uint8_t dma[128];
    FCB p; uint8_t n = 0, r, i;
    if (!mkfcb(&p, spec)) return 0;
    bdos(26, (uint16_t)dma);
    r = bdos(17, (uint16_t)&p);
    while (r != 0xFF && n < max) {
        uint8_t *e = dma + (r & 3) * 32;
        out[n][0] = p.dr;
        for (i = 0; i < 11; i++) out[n][i + 1] = e[i + 1] & 0x7F;
        n++;
        r = bdos(18, 0);
    }
    return n;
}
void nm2fcb(NAME12 n, FCB *f)
{
    memset(f, 0, sizeof(FCB));
    f->dr = n[0];
    memcpy(f->f, n + 1, 11);
}
uint8_t ropen(RD *r, FCB *f)
{
    if (f != &r->f) memcpy(&r->f, f, sizeof(FCB));
    r->p = 128; r->eof = 0;
    return fopen(&r->f);
}
int rgetc(RD *r)
{
    if (r->p >= 128) {
        if (r->eof || fread(&r->f, r->b)) { r->eof = 1; return -1; }
        r->p = 0;
    }
    return r->b[r->p++];
}
int32_t mul16(int16_t a, int16_t b)
{
    uint8_t neg = 0; uint16_t ua, ub; uint32_t r;
    if (a < 0) { ua = -a; neg = 1; } else ua = a;
    if (b < 0) { ub = -b; neg ^= 1; } else ub = b;
    r = (uint32_t)ua * ub;
    return neg ? -(int32_t)r : (int32_t)r;
}
uint8_t brk(void) { uint8_t k = getkey(); return k == 3 || k == 27 || (k | 32) == 'q'; }
