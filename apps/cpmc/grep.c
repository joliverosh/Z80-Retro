/* GREP - busca un patron en archivos de texto
   GREP [-N] [-V] [-C] [-L] patron archivo...
   GREP [-N] [-V] [-C] [-L] ? archivo...       el patron se escribe despues
   El patron (el motor de grep-milla de Semilla): . cualquier caracter,
   x* x+ x? (cero o mas, uno o mas, cero o uno), ^ $ (principio y fin),
   [abc] [a-z] [^...] (clases), \c (c literal). CP/M pasa la linea en
   mayusculas y sin comillas: un patron escrito ahi no distingue mayusculas y
   no puede tener espacios (usar .). Con ? se pide por teclado, con espacios,
   y ahi si distingue mayusculas. */
#include "cpm.h"
static NAME12 nm[64];
static RD r;
static char line[256];
static char *pat;
static char pbuf[130];
static uint8_t icase = 1;
static uint8_t low(uint8_t c) { return c >= 'A' && c <= 'Z' ? c + 32 : c; }
/* largo del atomo que empieza en re: 2 si \c, el corchete entero si [..], si no 1 */
static uint8_t atomlen(const char *re)
{
    uint8_t n;
    if (re[0] == '\\' && re[1]) return 2;
    if (re[0] == '[') {
        n = 1;
        if (re[n] == '^') n++;
        if (re[n] == ']') n++;              /* un ] al principio es literal */
        while (re[n] && re[n] != ']') n++;
        return re[n] == ']' ? n + 1 : n;
    }
    return 1;
}
/* el caracter c contra el atomo (re, de largo L) */
static uint8_t atom1(const char *re, uint8_t L, uint8_t c)
{
    uint8_t i, neg, ok;
    if (re[0] == '\\') return (uint8_t)re[1] == c;
    if (re[0] == '.') return 1;
    if (re[0] == '[') {
        i = 1; neg = 0;
        if (re[i] == '^') { neg = 1; i++; }
        ok = 0;
        while (i < L - 1) {                 /* L-1 es el ] final */
            if (re[i + 1] == '-' && i + 2 < L - 1) {
                if (c >= (uint8_t)re[i] && c <= (uint8_t)re[i + 2]) ok = 1;
                i += 3;
            } else {
                if ((uint8_t)re[i] == c) ok = 1;
                i++;
            }
        }
        return neg ? !ok : ok;
    }
    return (uint8_t)re[0] == c;
}
static uint8_t matchatom(const char *re, uint8_t L, uint8_t c)
{
    if (!c) return 0;
    if (!icase) return atom1(re, L, c);
    if (c >= 'a' && c <= 'z') return atom1(re, L, c) || atom1(re, L, c - 32);
    if (c >= 'A' && c <= 'Z') return atom1(re, L, c) || atom1(re, L, c + 32);
    return atom1(re, L, c);
}
static uint8_t matchhere(const char *re, const char *text);
/* atomo (re,L) repetido, luego el resto: minimo min veces */
static uint8_t matchrep(const char *re, uint8_t L, const char *resto, const char *text, uint8_t min)
{
    const char *t = text;
    int16_t n = 0;
    while (matchatom(re, L, *t)) { t++; n++; }   /* lo mas posible */
    while (n >= min) {                            /* y vuelve hasta que case el resto */
        if (matchhere(resto, text + n)) return 1;
        n--;
    }
    return 0;
}
static uint8_t matchhere(const char *re, const char *text)
{
    uint8_t L;
    if (re[0] == '\0') return 1;
    if (re[0] == '$' && re[1] == '\0') return *text == '\0';
    L = atomlen(re);
    if (re[L] == '*') return matchrep(re, L, re + L + 1, text, 0);
    if (re[L] == '+') return matchrep(re, L, re + L + 1, text, 1);
    if (re[L] == '?') {
        if (*text && matchatom(re, L, *text) && matchhere(re + L + 1, text + 1)) return 1;
        return matchhere(re + L + 1, text);
    }
    if (matchatom(re, L, *text)) return matchhere(re + L, text + 1);
    return 0;
}
static uint8_t match(const char *t)
{
    if (*pat == '^') return matchhere(pat + 1, t);
    do { if (matchhere(pat, t)) return 1; } while (*t++);
    return 0;
}
void main(void)
{
    char *p = args(), *a, s[16];
    uint8_t on = 0, ov = 0, oc = 0, ol = 0, many, nn = 0, i;
    NAME12 *q = nm;
    uint32_t tot = 0;
    while ((a = nextarg(&p)) && *a == '-') {
        for (a++; *a; a++)
            if (*a == 'N') on = 1; else if (*a == 'V') ov = 1;
            else if (*a == 'C') oc = 1; else if (*a == 'L') ol = 1;
    }
    pat = a;
    if (!pat || !*p) {
        pstr("Usage: GREP [-N] [-V] [-C] [-L] pattern|? file...\n"
             "  -N line numbers, -V lines that do not match, -C count, -L file names\n"
             "  pattern: . any char, x* x+ x? repeat, ^ start, $ end, [a-z] [^...] classes,\n"
             "  \\c literal c. No spaces and no case on the command line (use .);\n"
             "  ? asks for the pattern: spaces allowed and case matters.\n");
        return;
    }
    if (pat[0] == '?' && !pat[1]) {          /* el patron por teclado */
        pstr("Pattern: ");
        pbuf[0] = 127; pbuf[1] = 0;
        bdos(10, (uint16_t)pbuf);
        pstr("\r\n");
        pbuf[2 + (uint8_t)pbuf[1]] = 0;
        pat = pbuf + 2;
        icase = 0;
    }
    while ((a = nextarg(&p)) && nn < 64) {
        uint8_t n = glob(a, q, 64 - nn);
        if (!n) pf("%s: not found\n", a);
        q += n; nn += n;
    }
    many = nn > 1;
    for (i = 0; i < nn; i++) {
        uint16_t ln = 0; uint32_t cnt = 0; uint8_t k = 0, end = 0;
        nm2fcb(nm[i], &r.f);
        fname(&r.f, s);
        if (ropen(&r, &r.f)) continue;
        while (!end) {
            int ch = rgetc(&r);
            if (ch < 0 || ch == 0x1A) { end = 1; if (!k) break; }
            else if (ch == '\r') continue;
            else if (ch != '\n') { if (k < 255) line[k++] = ch; continue; }
            line[k] = 0; k = 0; ln++;
            if (match(line) != ov) {
                cnt++;
                if (ol) break;
                if (!oc) {
                    if (many) pf("%s:", s);
                    if (on) pf("%u:", ln);
                    pstr(line); pstr("\r\n");
                }
            }
            if (brk()) return;
        }
        fclose(&r.f);
        if (ol && cnt) pf("%s\n", s);
        if (oc) { if (many) pf("%s:", s); pf("%lu\n", cnt); }
        tot += cnt;
    }
}
