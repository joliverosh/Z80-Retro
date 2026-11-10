/* MORE - muestra un archivo de texto por pantallas
   MORE archivo...   ESPACIO: otra pantalla, RETURN: otra linea, Q: salir */
#include "cpm.h"
static NAME12 nm[32];
static RD r;
static uint8_t row;
static uint8_t page = 23;
static uint8_t ask(void)          /* 0 seguir, 1 salir */
{
    int k;
    pstr(ESC "[7m-- More -- (SPACE page, RETURN line, Q quit)" ESC "[0m");
    k = waitkey();
    pstr("\r" ESC "[K");
    if (k == 3 || (k | 32) == 'q' || k == 27) return 1;
    row = (k == '\r' || k == '\n') ? page - 1 : 0;
    return 0;
}
static uint8_t nl(void) { pstr("\r\n"); return ++row >= page ? ask() : 0; }
void main(void)
{
    char *p = args(), *a, s[16];
    if (!*p) { pstr("Usage: MORE file...\n"); return; }
    while ((a = nextarg(&p))) {
        uint8_t n = glob(a, nm, 32), i;
        if (!n) { pf("%s: not found\n", a); continue; }
        for (i = 0; i < n; i++) {
            uint8_t col = 0; int ch;
            nm2fcb(nm[i], &r.f);
            fname(&r.f, s);
            if (ropen(&r, &r.f)) continue;
            if (n > 1 || *p) {
                pf(ESC "[1m::::: %s :::::" ESC "[0m", s);
                if (nl()) return;
            }
            while ((ch = rgetc(&r)) >= 0 && ch != 0x1A) {
                if (ch == '\r') continue;
                if (ch == '\n') { col = 0; if (nl()) return; continue; }
                if (ch == '\t') {
                    do { putch(' '); col++; } while (col & 7 && col < 80);
                } else if (ch == '\f') {
                    col = 0; if (nl()) return; continue;
                } else { putch(ch < 32 || ch > 126 ? '.' : ch); col++; }
                if (col >= 80) { col = 0; row++; if (row >= page && ask()) return; }
            }
            fclose(&r.f);
            if (col && nl()) return;
        }
    }
}
