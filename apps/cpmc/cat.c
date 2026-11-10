/* CAT - muestra uno o mas archivos de texto seguidos, hasta el ^Z de cada uno
   CAT archivo...   (admite * y ?; ^C, Q o ESC para) */
#include "cpm.h"
static NAME12 nm[64];
static RD r;
void main(void)
{
    char *p = args(), *a, s[16];
    if (!*p) { pstr("Usage: CAT file...\n"); return; }
    while ((a = nextarg(&p))) {
        uint8_t n = glob(a, nm, 64), i;
        if (!n) { pf("%s: not found\n", a); continue; }
        for (i = 0; i < n; i++) {
            int ch;
            uint8_t k = 0;
            nm2fcb(nm[i], &r.f);
            fname(&r.f, s);
            if (ropen(&r, &r.f)) { pf("%s: cannot open\n", s); continue; }
            while ((ch = rgetc(&r)) >= 0 && ch != 0x1A) {
                putch(ch);
                if (!++k && brk()) { fclose(&r.f); return; }
            }
            fclose(&r.f);
        }
    }
}
