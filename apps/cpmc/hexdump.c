/* HEXDUMP - el contenido de un archivo en hexadecimal y ASCII
   HEXDUMP archivo [desde]   (desde en hexadecimal; ESPACIO sigue, Q sale) */
#include "cpm.h"
static FCB f;
static uint8_t b[128];
static uint32_t hex(const char *s)
{
    uint32_t v = 0;
    for (; *s; s++) {
        char c = *s;
        if (c >= '0' && c <= '9') c -= '0';
        else if (c >= 'A' && c <= 'F') c -= 'A' - 10;
        else break;
        v = (v << 4) | c;
    }
    return v;
}
void main(void)
{
    char *p = args(), *a = nextarg(&p), *o = nextarg(&p);
    uint32_t off = 0;
    uint16_t rec;
    uint8_t row = 0, i, j;
    if (!a) { pstr("Usage: HEXDUMP file [hex-offset]\n"); return; }
    if (!mkfcb(&f, a) || fopen(&f)) { pf("%s: not found\n", a); return; }
    if (o) off = hex(o) & ~15UL;
    rec = off >> 7;
    i = off & 127;
    while (!rread(&f, rec++, b)) {
        for (; i < 128; i += 16, off += 16) {
            pf("%06lX  ", off);
            for (j = 0; j < 16; j++) pf(j == 8 ? " %02X " : "%02X ", b[i + j]);
            putch(' ');
            for (j = 0; j < 16; j++) { uint8_t c = b[i + j]; putch(c < 32 || c > 126 ? '.' : c); }
            pstr("\r\n");
            if (++row >= 23) {
                int k;
                pstr(ESC "[7m-- More -- (SPACE page, RETURN line, Q quit)" ESC "[0m");
                k = waitkey();
                pstr("\r" ESC "[K");
                if (k == 3 || k == 27 || (k | 32) == 'q') return;
                row = (k == '\r') ? 22 : 0;
            } else if (brk()) return;
        }
        i = 0;
    }
}
