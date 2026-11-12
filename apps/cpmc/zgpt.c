/* ZGPT - un GPT de verdad en el Z80: un transformer de 2 capas (dimension 32, 4 cabezas,
   48 letras de memoria, 25 838 parametros) que escribe letra por letra a la manera de
   El Quijote, con el que se entreno. Los pesos van en ZGPT.BIN, en bytes con signo con
   una escala por fila; las cuentas son enteras y dan lo mismo que la referencia en
   Python (export.py). El producto escalar esta en zgpt_a.s.
   ZGPT                     pregunta un comienzo y sigue escribiendo
   ZGPT [/Tn] [/Ln] texto   escribe una vez a partir de texto y vuelve
   /T temperatura en decimas (0 = siempre la mas probable; 7 al empezar), /L letras.
   (C) OLIVEROS 2026 */
#include <string.h>
#include "cpm.h"

#define D 32
#define NL 2
#define NH 4
#define HD 8
#define FF 96
#define T 48
#define NV 46
#define NEXP 192
#define BINMAX 27520

void dotinit(uint8_t page) __sdcccall(0);
int32_t dot8(const uint8_t *w, uint8_t n, uint8_t x0) __sdcccall(0);
void dotk(const uint8_t *k, int32_t *out, uint8_t npos, uint8_t x0) __sdcccall(0);
uint32_t umul16(uint16_t a, uint16_t b) __sdcccall(0);
int32_t smul16(int16_t a, int16_t b) __sdcccall(0);

typedef struct { const uint8_t *w; const int16_t *m, *b; } lin;
typedef struct { uint16_t ke; lin q, k, v, o, f1, f2; } layer;

static uint8_t bin[BINMAX];
static uint8_t area[6 * 256 + 255];
static uint8_t *pg, *xs, *xd;
static uint8_t et, ep;
static const uint8_t *ch, *exp7, *tokw, *posw;
static layer ly[NL];
static lin head;
static uint8_t kc[NL][T][D];        /* K de cada posicion, como byte + 80h */
static uint8_t vt[NL][D][T];        /* V, traspuesta */
static int16_t r[D];
static int8_t z[D], q[D], o[D], hbuf[FF];
static int32_t y[FF];
static int32_t sc[T];
static uint8_t pr[T];
static int32_t logit[NV];
static uint16_t tpos;               /* cuantas letras lleva */

static void prepx(const int8_t *x, uint8_t n)
{
    uint8_t i, u;
    for (i = 0; i < n; i++) { u = (uint8_t)x[i] ^ 0x80; xs[i] = u; xd[i] = -u; }
}
static int32_t mulsh(int32_t acc, int16_t m)   /* piso(acc * m / 65536) */
{
    return smul16((int16_t)(acc >> 16), m) + (int32_t)(umul16((uint16_t)acc, m) >> 16);
}
static void matvec(const lin *l, const int8_t *x, uint8_t nin, uint8_t nout, int32_t *out)
{
    uint8_t i;
    const uint8_t *w = l->w;
    prepx(x, nin);
    for (i = 0; i < nout; i++, w += nin) out[i] = mulsh(dot8(w, nin, 0), l->m[i]) + l->b[i];
}
static uint16_t isqrt32(uint32_t n)
{
    uint32_t res = 0, bit = 1UL << 30;
    while (bit > n) bit >>= 2;
    while (bit) {
        if (n >= res + bit) { n -= res + bit; res = (res >> 1) + bit; }
        else res >>= 1;
        bit >>= 2;
    }
    return res;
}
static uint32_t sq(int16_t d) { uint16_t u = d < 0 ? -d : d; return umul16(u, u); }
static void pu(uint16_t v) { if (v >= 10) pu(v / 10); putch('0' + v % 10); }
static int8_t c8(int32_t v) { return v > 127 ? 127 : v < -127 ? -127 : v; }
static void norm(void)
{
    int32_t s = 0, var = 0;
    int16_t mean, d, inv;
    uint16_t sd;
    uint8_t i;
    for (i = 0; i < D; i++) s += r[i];
    mean = s >> 5;
    for (i = 0; i < D; i++) { d = r[i] - mean; var += sq(d) >> 5; }
    sd = isqrt32(var);
    if (sd < 32) sd = 32;
    inv = 1048576L / sd;                 /* 32 / sd, en Q15 */
    for (i = 0; i < D; i++) { d = r[i] - mean; z[i] = c8(smul16(d, inv) >> 15); }
}
static void addr(void)
{
    uint8_t i;
    int32_t v;
    for (i = 0; i < D; i++) {
        v = r[i] + y[i];
        r[i] = v > 16383 ? 16383 : v < -16383 ? -16383 : v;
    }
}
/* una letra adentro; deja los logits (Q8) de la siguiente */
static void step(uint8_t c)
{
    uint8_t p = tpos % T, n = tpos < T ? tpos + 1 : T, l, h, i, j, idx;
    int32_t mx, zs, num;
    layer *L;
    for (i = 0; i < D; i++)
        r[i] = ((int16_t)(int8_t)tokw[c * D + i] << et) + ((int16_t)(int8_t)posw[p * D + i] << ep);
    for (l = 0; l < NL; l++) {
        L = &ly[l];
        norm();
        matvec(&L->q, z, D, D, y);
        for (i = 0; i < D; i++) q[i] = c8(y[i]);
        matvec(&L->k, z, D, D, y);
        for (i = 0; i < D; i++) kc[l][p][i] = (uint8_t)c8(y[i]) ^ 0x80;
        matvec(&L->v, z, D, D, y);
        for (i = 0; i < D; i++) vt[l][i][p] = (uint8_t)c8(y[i]) ^ 0x80;
        for (h = 0; h < NH; h++) {
            prepx(q, D);
            mx = -0x7FFFFFFFL;
            dotk(&kc[l][0][h * HD], sc, n, h * HD);
            for (j = 0; j < n; j++) if (sc[j] > mx) mx = sc[j];
            zs = 0;
            for (j = 0; j < n; j++) {
                num = mx - sc[j];
                if (num > 32767) idx = NEXP - 1;
                else { num = umul16(num, L->ke) >> 16; idx = num > NEXP - 1 ? NEXP - 1 : num; }
                pr[j] = exp7[idx];
                zs += pr[j];
            }
            prepx((int8_t *)pr, n);
            for (i = h * HD; i < h * HD + HD; i++) o[i] = dot8(vt[l][i], n, 0) / zs;
        }
        matvec(&L->o, o, D, D, y);
        addr();
        norm();
        matvec(&L->f1, z, D, FF, y);
        for (i = 0; i < FF; i++) hbuf[i] = y[i] < 0 ? 0 : y[i] > 127 ? 127 : y[i];
        matvec(&L->f2, hbuf, FF, D, y);
        addr();
    }
    norm();
    prepx(z, D);
    for (i = 0; i < NV; i++) logit[i] = mulsh(dot8(head.w + i * D, D, 0), head.m[i]) + head.b[i];
    tpos++;
}
static uint8_t pick(uint8_t temp)   /* temp en decimas; 0 = la mas probable */
{
    int32_t mx = logit[0], dl, kt;
    uint16_t sum = 0, rr;
    uint8_t i, best = 0, pp[NV];
    for (i = 1; i < NV; i++) if (logit[i] > mx) { mx = logit[i]; best = i; }
    if (!temp) return best;
    kt = 81920L / temp;
    for (i = 0; i < NV; i++) {
        dl = mx - logit[i];
        if (dl > 8191) dl = 8191;
        dl = (dl * kt) >> 16;
        pp[i] = exp7[dl > NEXP - 1 ? NEXP - 1 : dl];
        sum += pp[i];
    }
    rr = rnd() % sum;
    for (i = 0; i < NV; i++) { if (rr < pp[i]) return i; rr -= pp[i]; }
    return best;
}

/* ---------------------------------------------------------------- texto */
static uint8_t cap, col;
static void outc(uint8_t c)          /* Latin-1 a UTF-8 */
{
    if (c < 0x80) putch(c);
    else if (c < 0xC0) { putch(0xC2); putch(c); }
    else { putch(0xC3); putch(c - 0x40); }
}
static void say(uint8_t c)           /* con mayusculas al empezar y lineas de 72 */
{
    if (c == '\n') { pstr("\n"); col = 0; cap = 1; return; }
    if (c == ' ' && col >= 72) { pstr("\n"); col = 0; return; }
    if (c == ' ' && !col) return;
    if (cap && ((c >= 'a' && c <= 'z') || c >= 0xE0)) { c -= 32; cap = 0; }
    if (c == '.' || c == '?' || c == '!') cap = 1;
    outc(c);
    col++;
}
static int8_t code(uint8_t c)        /* la letra en el vocabulario, o -1 */
{
    uint8_t i;
    if (c >= 'A' && c <= 'Z') c += 32;
    else if (c >= 0xC0 && c <= 0xDE) c += 32;
    if (c == 'k') c = 'c';
    if (c == 'w') c = 'v';
    for (i = 0; i < NV; i++) if (ch[i] == c) return i;
    return -1;
}

static uint8_t load(void)
{
    static const char *const names[] = { "ZGPT.BIN", "A:ZGPT.BIN" };
    FCB f;
    uint8_t k, i, *b;
    uint16_t len = 0;
    for (k = 0; k < 2; k++) {
        if (!mkfcb(&f, names[k]) || fopen(&f)) continue;
        while (len < BINMAX && !fread(&f, bin + len)) len += 128;
        fclose(&f);
        break;
    }
    if (len < 1000 || memcmp(bin, "ZGPT", 4) || bin[4] != NV || bin[5] != D || bin[6] != NL ||
        bin[7] != NH || bin[8] != FF || bin[9] != T) return 1;
    et = bin[10]; ep = bin[11];
    b = bin + 12;
    ch = b; b += NV;
    exp7 = b; b += NEXP;
    tokw = b; b += NV * D;
    posw = b; b += T * D;
#define LIN(x, nin, nout) x.w = b; b += (nin) * (nout); x.m = (int16_t *)b; b += 2 * (nout); x.b = (int16_t *)b; b += 2 * (nout);
    for (i = 0; i < NL; i++) {
        ly[i].ke = b[0] | b[1] << 8; b += 2;
        LIN(ly[i].q, D, D) LIN(ly[i].k, D, D) LIN(ly[i].v, D, D) LIN(ly[i].o, D, D)
        LIN(ly[i].f1, D, FF) LIN(ly[i].f2, FF, D)
    }
    LIN(head, D, NV)
    return b > bin + len;
}
static void tables(void)
{
    uint16_t k, v;
    int16_t d;
    pg = (uint8_t *)(((uint16_t)area + 255) & 0xFF00);
    xs = pg + 4 * 256; xd = pg + 5 * 256;
    for (k = 0; k < 512; k++) {
        d = (int16_t)k - 256;
        v = sq(d) >> 2;
        pg[k] = v; pg[512 + k] = v >> 8;
    }
    dotinit((uint16_t)pg >> 8);
}

static uint8_t temp = 7;
static uint16_t nlet = 400;
static char line[80];
/* escribe a partir de lo que hay; 1 si se detuvo con una tecla */
static uint8_t write(void)
{
    uint16_t i, t0 = ticks();
    uint8_t c;
    for (i = 0; i < nlet; i++) {
        c = pick(temp);
        say(ch[c]);
        oflush();
        step(c);
        if (getkey()) { i++; break; }
    }
    t0 = ticks() - t0;
    pstr("\n" ESC "[2m["); pu(i); pstr(" letters in "); pu(t0 / tps()); putch('.');
    pu((t0 % tps()) * 10 / tps()); pstr(" s]" ESC "[0m\n");
    return 0;
}
static void feed(const char *s)      /* el comienzo (en Latin-1 o UTF-8), letra por letra */
{
    uint8_t c;
    int8_t k;
    tpos = 0; cap = 1; col = 0;
    step(code('\n'));                /* un parrafo nuevo */
    while ((c = *s++)) {
        if (c == 0xC2 && *s) c = *s++;
        else if (c == 0xC3 && *s) c = *s++ + 0x40;
        if ((k = code(c)) < 0) continue;
        say(ch[k]);
        step(k);
    }
    oflush();
}
static uint8_t readline(void)        /* 0 si ESC o ^C */
{
    uint8_t n = 0;
    int k;
    pstr("\n> ");
    for (;;) {
        k = waitkey();
        if (k == 27 || k == 3) return 0;
        if (k == 13 || k == 10) break;
        if ((k == 8 || k == 127) && n) {
            n--; pstr("\b \b");
            while (n && ((uint8_t)line[n] & 0xC0) == 0x80) n--;   /* (una letra de UTF-8) */
            continue;
        }
        if (k >= ' ' && n < sizeof line - 1) { line[n++] = k; putch(k); }
    }
    line[n] = 0;
    pstr("\n");
    return 1;
}
static uint8_t option(char *w)       /* /Tn /Ln */
{
    uint16_t v = 0;
    char *p;
    if (w[0] != '/' || !w[1]) return 0;
    for (p = w + 2; *p >= '0' && *p <= '9'; p++) v = v * 10 + *p - '0';
    if ((w[1] | 32) == 't' && v <= 30) temp = v;
    else if ((w[1] | 32) == 'l' && v) nlet = v;
    return 1;
}
void main(void)
{
    char *a = args(), *w;
    uint8_t once = 0;
    srnd(ticks());
    tables();
    if (load()) { pstr("Can't read ZGPT.BIN (it goes on this drive or on A:).\n"); return; }
    while (*a == ' ') a++;
    while (*a == '/') { w = nextarg(&a); option(w); while (*a == ' ') a++; }
    if (*a) { once = 1; strncpy(line, a, sizeof line - 1); }
    if (once) {
        for (w = line; *w; w++) if (*w >= 'A' && *w <= 'Z') *w += 32;
        feed(line); write(); return;
    }
    pstr("ZGPT - a tiny GPT that writes like Don Quixote   (C) OLIVEROS 2026\n"
         "2 layers, 25 838 parameters, 48 letters of memory, trained on the whole novel.\n"
         "Type how it starts (Enter alone: from nothing). A key stops it. /T0../T20 sets\n"
         "the temperature, /L how many letters; ESC quits.\n");
    while (readline()) {
        w = line;
        while (*w == ' ') w++;
        if (*w == '/') { while (*w == '/') { char *x = nextarg(&w); option(x); while (*w == ' ') w++; }
                         pstr("Temperature "); pu(temp / 10); putch('.'); pu(temp % 10);
                         pstr(", "); pu(nlet); pstr(" letters.\n"); continue; }
        feed(w);
        write();
    }
}
