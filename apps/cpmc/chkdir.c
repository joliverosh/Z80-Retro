/* CHKDIR - revisa el directorio de un disco CP/M (no cambia nada)
   CHKDIR [d:] [-V]
   (En ZOS esta tambien la orden CHKDSK del shell, mas corta; esta mira mas
   y corre tambien en CP/M 2.2 y MP/M II.)
   Mira cada entrada: codigo de usuario, nombre, bloques fuera del disco o
   dentro del directorio, bloques que usan dos archivos, extensiones que
   faltan, y cuenta lo usado y lo libre. -V: muestra cada archivo.
   (C) OLIVEROS 2026 */
#include <string.h>
#include "cpm.h"
#include "dskdir.h"

#define MAXF 256
typedef struct { uint8_t user; char nm[11]; uint16_t maxext; uint8_t nent; uint16_t recs; uint16_t extmask[4]; } finfo;
static finfo fl[MAXF];
static uint16_t nf, nbad;
static uint16_t owner[2048];             /* entrada que usa cada bloque, +1 (0: libre) */

static void bad(uint16_t ent, const char *why)
{
    char n[13];
    dd_name(dd_dir + ent * 32, n);
    pf("  entry %u (%u:%s): %s\n", ent, dd_dir[ent * 32], n, why);
    nbad++;
}
static int ffind(uint8_t *e)
{
    uint16_t i;
    for (i = 0; i < nf; i++)
        if (fl[i].user == e[0] && !memcmp(fl[i].nm, e + 1, 11)) return i;
    return -1;
}
void main(void)
{
    char *p = args(), *a;
    uint8_t drv = bdos(25, 0) & 15, verbose = 0, k, r, *e, i, sh;
    uint16_t n, b, used = 0, dirused = 0, ext, nblk;
    int x;
    char nm[13];
    while ((a = nextarg(&p))) {
        if (a[0] == '-' && (a[1] | 32) == 'v') verbose = 1;
        else if (a[1] == ':' && (a[0] | 32) >= 'a' && (a[0] | 32) <= 'p') drv = (a[0] | 32) - 'a';
        else { pstr("Usage: CHKDIR [d:] [-V]\n"); return; }
    }
    r = dd_open(drv);
    if (r) { pstr(r == 1 ? "No such drive\n" : r == 2 ? "Directory too big\n" : "Read error\n"); return; }
    pf("CHKDIR %c:  %u blocks of %u KB, %u directory entries, %u system tracks\n",
       'A' + drv, dd_dsm + 1, (128 << dd_bsh) >> 10, dd_drm + 1, dd_off);
    nblk = dd_nblk();
    for (sh = 0; (1 << sh) <= dd_exm; sh++) ;  /* exm + 1 = 2^sh */
    for (n = 0; n <= dd_drm; n++) {
        e = dd_dir + n * 32;
        if (e[0] == 0xE5) continue;
        dirused++;
        if (e[0] == 0x20 || e[0] == 0x21) continue;      /* etiqueta y fechas de CP/M 3 */
        if (e[0] > 15) { bad(n, "bad user code"); continue; }
        for (i = 1; i < 12; i++) if ((e[i] & 0x7F) < 32) break;
        if (i < 12) bad(n, "bad character in the name");
        if (e[15] > 128) bad(n, "record count over 128");
        ext = dd_ext(e);
        for (k = 0; k < nblk; k++) {
            b = dd_blk(e, k);
            if (!b) continue;
            if (b > dd_dsm) { bad(n, "block past the end of the disk"); continue; }
            if (b < dd_first) { bad(n, "block inside the directory"); continue; }
            if (owner[b]) {
                char o[13];
                dd_name(dd_dir + (owner[b] - 1) * 32, o);
                dd_name(e, nm);
                pf("  block %u: in %u:%s and in %u:%s\n", b, dd_dir[(owner[b] - 1) * 32], o, e[0], nm);
                nbad++;
            } else { owner[b] = n + 1; used++; }
        }
        x = ffind(e);
        if (x < 0 && nf < MAXF) {
            x = nf++;
            fl[x].user = e[0]; memcpy(fl[x].nm, e + 1, 11);
        }
        if (x >= 0) {
            uint16_t j = ext >> sh, r;   /* la entrada: exm + 1 extensiones */
            finfo *q = &fl[x];
            q->nent++;
            if (ext > q->maxext) q->maxext = ext;
            if (j < 64) q->extmask[j >> 4] |= 1 << (j & 15);
            r = (ext & dd_exm) << 7;
            r += e[15];
            q->recs += r;
        }
    }
    /* extensiones que faltan: cada entrada cubre exm + 1 extensiones */
    for (x = 0; x < (int)nf; x++) {
        uint16_t last = fl[x].maxext >> sh, j;
        uint8_t ee[32];
        ee[0] = fl[x].user; memcpy(ee + 1, fl[x].nm, 11);
        dd_name(ee, nm);
        for (j = 0; j <= last && j < 64; j++)
            if (!(fl[x].extmask[j >> 4] & (1 << (j & 15)))) {
                pf("  %u:%s: extent %u is missing\n", fl[x].user, nm, j * (dd_exm + 1));
                nbad++;
                break;
            }
        if (verbose) pf("  %u:%s  %u entries, %u KB\n", fl[x].user, nm, fl[x].nent, (fl[x].recs + 7) >> 3);
    }
    pf("%u files, %u of %u directory entries used\n", nf, dirused, dd_drm + 1);
    pf("%u blocks used, %u free (%u KB free)\n", used, dd_dsm + 1 - dd_first - used,
       (uint16_t)(((uint32_t)(dd_dsm + 1 - dd_first - used) << dd_bsh) >> 3));
    if (nbad) pf("%u problems found\n", nbad); else pstr("No problems found\n");
}
