/* WC - lineas, palabras y caracteres (hasta el ^Z) de uno o mas archivos
   WC archivo...   (admite * y ?) */
#include "cpm.h"
static NAME12 nm[64];
static RD r;
void main(void)
{
    char *p = args(), *a, s[16];
    uint32_t tl = 0, tw = 0, tc = 0;
    uint8_t nf = 0;
    if (!*p) { pstr("Usage: WC file...  (lines, words, chars; wildcards allowed)\n"); return; }
    while ((a = nextarg(&p))) {
        uint8_t n = glob(a, nm, 64), i;
        if (!n) { pf("%s: not found\n", a); continue; }
        for (i = 0; i < n; i++) {
            uint32_t l = 0, w = 0, c = 0; uint8_t in = 0; int ch;
            nm2fcb(nm[i], &r.f);
            fname(&r.f, s);
            if (ropen(&r, &r.f)) { pf("%s: cannot open\n", s); continue; }
            while ((ch = rgetc(&r)) >= 0 && ch != 0x1A) {
                c++;
                if (ch == '\n') l++;
                if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n') in = 0;
                else if (!in) { in = 1; w++; }
            }
            fclose(&r.f);
            pf("%7lu %7lu %7lu %s\n", l, w, c, s);
            tl += l; tw += w; tc += c; nf++;
            if (brk()) return;
        }
    }
    if (nf > 1) pf("%7lu %7lu %7lu total\n", tl, tw, tc);
}
