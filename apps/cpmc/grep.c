/* GREP - busca un patron en archivos de texto (sin distinguir mayusculas)
   GREP [-N] [-V] [-C] [-L] patron archivo...
   El patron: . cualquier caracter, x* cero o mas x, ^ al principio, $ al final,
   \ quita el sentido especial. CP/M pasa la linea en mayusculas y sin comillas,
   asi que el patron no puede tener espacios (usar . en su lugar). */
#include "cpm.h"
static NAME12 nm[64];
static RD r;
static char line[256];
static char *pat;
static uint8_t up(uint8_t c) { return c >= 'a' && c <= 'z' ? c - 32 : c; }
static uint8_t matchhere(const char *re, const char *t);
static uint8_t one(const char *re, const char *t)
{
    if (!*t) return 0;
    if (*re == '.') return 1;
    if (*re == '\\') re++;
    return up(*re) == up(*t);
}
static uint8_t len1(const char *re) { return *re == '\\' && re[1] ? 2 : 1; }
static uint8_t matchstar(const char *c, const char *re, const char *t)
{
    do { if (matchhere(re, t)) return 1; } while (one(c, t++));
    return 0;
}
static uint8_t matchhere(const char *re, const char *t)
{
    for (;;) {
        uint8_t l;
        if (!*re) return 1;
        l = len1(re);
        if (re[l] == '*') return matchstar(re, re + l + 1, t);
        if (re[0] == '$' && !re[1]) return !*t;
        if (!one(re, t)) return 0;
        re += l; t++;
    }
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
        pstr("Usage: GREP [-N] [-V] [-C] [-L] pattern file...\n"
             "  -N line numbers, -V lines that do not match, -C count, -L file names\n"
             "  pattern: . any char, x* zero or more x, ^ start, $ end (no spaces: use .)\n");
        return;
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
