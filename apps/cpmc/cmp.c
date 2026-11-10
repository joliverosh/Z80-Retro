/* CMP - compara dos archivos byte a byte
   CMP archivo1 archivo2   (muestra hasta 16 diferencias) */
#include "cpm.h"
static FCB f1, f2;
static uint8_t b1[128], b2[128];
void main(void)
{
    char *p = args(), *a1 = nextarg(&p), *a2 = nextarg(&p);
    uint32_t off = 0, nd = 0;
    uint8_t e1, e2, i;
    if (!a2) { pstr("Usage: CMP file1 file2\n"); return; }
    if (!mkfcb(&f1, a1) || fopen(&f1)) { pf("%s: not found\n", a1); return; }
    if (!mkfcb(&f2, a2) || fopen(&f2)) { pf("%s: not found\n", a2); return; }
    for (;;) {
        e1 = fread(&f1, b1);
        e2 = fread(&f2, b2);
        if (e1 || e2) break;
        for (i = 0; i < 128; i++, off++)
            if (b1[i] != b2[i]) {
                if (++nd <= 16) pf("%06lX: %02X %02X\n", off, b1[i], b2[i]);
            }
        if (brk()) { pstr("Stopped\n"); return; }
    }
    if (e1 != e2) {
        pf("%s is shorter (%lu bytes, %u records)\n", e1 ? a1 : a2, off, (uint16_t)(off >> 7));
        if (!nd) return;
    }
    if (nd) pf("%lu bytes differ\n", nd);
    else pf("Files are identical (%lu bytes)\n", off);
}
