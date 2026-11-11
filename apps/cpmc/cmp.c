/* CMP - compara dos archivos byte a byte
   CMP archivo1 archivo2   (muestra hasta 16 diferencias) */
#include "cpm.h"
static FCB f1, f2;
static uint8_t b1[1024], b2[1024];     /* 8 registros por llamada al BDOS */
void main(void)
{
    char *p = args(), *a1 = nextarg(&p), *a2 = nextarg(&p);
    uint32_t off = 0, nd = 0;
    uint8_t n1, n2;
    uint16_t i, len;
    if (!a2) { pstr("Usage: CMP file1 file2\n"); return; }
    if (!mkfcb(&f1, a1) || fopen(&f1)) { pf("%s: not found\n", a1); return; }
    if (!mkfcb(&f2, a2) || fopen(&f2)) { pf("%s: not found\n", a2); return; }
    for (;;) {
        n1 = freadn(&f1, b1, 8);
        n2 = freadn(&f2, b2, 8);
        len = (uint16_t)(n1 < n2 ? n1 : n2) << 7;
        for (i = 0; i < len; i++, off++)
            if (b1[i] != b2[i]) {
                if (++nd <= 16) pf("%06lX: %02X %02X\n", off, b1[i], b2[i]);
            }
        if (n1 != n2 || n1 < 8) break;
        if (brk()) { pstr("Stopped\n"); return; }
    }
    if (n1 != n2) {
        pf("%s is shorter (%lu bytes, %u records)\n", n1 < n2 ? a1 : a2, off, (uint16_t)(off >> 7));
        if (!nd) return;
    }
    if (nd) pf("%lu bytes differ\n", nd);
    else pf("Files are identical (%lu bytes)\n", off);
}
