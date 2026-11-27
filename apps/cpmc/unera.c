/* UNERA - recupera archivos borrados, si nada pisó sus bloques
   UNERA [d:]nombre.ext [usuario]   (admite * y ?)
   UNERA [d:]                       lista los borrados y si se pueden recuperar
   Un archivo borrado sigue en el directorio con E5h en lugar del usuario;
   sus bloques quedan libres y el proximo que se escriba los puede usar.
   UNERA lo devuelve al usuario dado (o al actual) solo si ninguno de sus
   bloques lo usa otro archivo, y si no hay ya uno con ese nombre.
   (C) OLIVEROS 2026 */
#include <string.h>
#include "cpm.h"
#include "dskdir.h"

static uint8_t pat[11];
static uint8_t match(uint8_t *e)
{
    uint8_t i;
    for (i = 0; i < 11; i++)
        if (pat[i] != '?' && (e[1 + i] & 0x7F) != pat[i]) return 0;
    return 1;
}
/* todos los bloques de la entrada libres (ni de un archivo vivo ni ya tomados) */
static uint8_t blocksfree(uint8_t *e)
{
    uint8_t k, n = dd_nblk();
    uint16_t b;
    for (k = 0; k < n; k++) {
        b = dd_blk(e, k);
        if (!b) continue;
        if (b > dd_dsm || b < dd_first || dd_test(b)) return 0;
    }
    return 1;
}
static void take(uint8_t *e)
{
    uint8_t k, n = dd_nblk();
    uint16_t b;
    for (k = 0; k < n; k++) if ((b = dd_blk(e, k)) && b <= dd_dsm) dd_set(b);
}
/* hay un archivo vivo de ese usuario con ese nombre? */
static uint8_t alive(uint8_t user, uint8_t *e)
{
    uint16_t n;
    uint8_t *f;
    for (n = 0; n <= dd_drm; n++) {
        f = dd_dir + n * 32;
        if (f[0] == user && !memcmp(f + 1, e + 1, 11)) return 1;
    }
    return 0;
}
void main(void)
{
    char *p = args(), *a = nextarg(&p), *u = nextarg(&p), nm[13];
    uint8_t drv = bdos(25, 0) & 15, user = bdos(32, 0xFF) & 15, r, *e, list = 0, ok, i;
    uint16_t n, m, got = 0, cant = 0, xs[64], xi[64], maxx;
    uint8_t nx, sh;
    static uint8_t save[sizeof dd_map];
    FCB f;
    if (!a) { pstr("Usage: UNERA [d:]name.ext [user]   or   UNERA d:   (list)\n"); return; }
    if (a[1] == ':' && !a[2]) {
        drv = (a[0] | 32) - 'a';
        list = 1;
        memset(pat, '?', 11);
    } else {
        if (!mkfcb(&f, a)) { pstr("Bad name\n"); return; }
        if (f.dr) drv = f.dr - 1;
        memcpy(pat, f.f, 11);
    }
    if (u) { user = 0; while (*u >= '0' && *u <= '9') user = user * 10 + (*u++ - '0'); if (user > 15) { pstr("User 0-15\n"); return; } }
    if (drv > 15) { pstr("Bad drive\n"); return; }
    r = dd_open(drv);
    for (sh = 0; (1 << sh) <= dd_exm; sh++) ;
    if (r) { pstr(r == 1 ? "No such drive\n" : r == 2 ? "Directory too big\n" : "Read error\n"); return; }
    /* los bloques de los vivos */
    for (n = 0; n <= dd_drm; n++) {
        e = dd_dir + n * 32;
        if (e[0] <= 15) take(e);
    }
    for (n = 0; n <= dd_drm; n++) {
        e = dd_dir + n * 32;
        if (e[0] != 0xE5 || !match(e)) continue;
        for (i = 1; i < 12 && (e[i] & 0x7F) >= 32 && (e[i] & 0x7F) < 127; i++) ;
        if (i < 12 || (e[1] == 0xE5 && e[2] == 0xE5)) continue;   /* nunca se uso */
        /* las entradas del mismo nombre que vienen despues van con la primera */
        for (m = 0; m < n; m++) if (dd_dir[m * 32] == 0xE5 && !memcmp(dd_dir + m * 32 + 1, e + 1, 11)) break;
        if (m < n) continue;
        dd_name(e, nm);
        /* una entrada libre por cada numero de extension, de la 0 en
           adelante y sin huecos; los bloques se toman al probar */
        ok = !alive(user, e);
        memcpy(save, dd_map, sizeof save);
        nx = 0; maxx = 0;
        for (m = n; m <= dd_drm && ok; m++) {
            uint8_t *x = dd_dir + m * 32, k;
            uint16_t xe;
            if (x[0] != 0xE5 || memcmp(x + 1, e + 1, 11)) continue;
            xe = dd_ext(x) >> sh;
            for (k = 0; k < nx && xs[k] != xe; k++) ;
            if (k < nx || !blocksfree(x) || nx >= sizeof xs / 2) continue;
            xs[nx] = xe; xi[nx++] = m;
            if (xe > maxx) maxx = xe;
            take(x);
        }
        if (ok && nx != maxx + 1) ok = 0;    /* falta una extension */
        if (list || !ok) memcpy(dd_map, save, sizeof save);
        if (list) { pf("  %s%s\n", nm, ok ? "" : "   (cannot: blocks in use)"); continue; }
        if (!ok) { pf("%s: cannot (its blocks are in use, or there is one with that name)\n", nm); cant++; continue; }
        for (m = 0; m < nx; m++) dd_dir[xi[m] * 32] = user;
        pf("%s: recovered (user %u)\n", nm, user);
        got++;
    }
    if (list) return;
    if (!got) { if (!cant) pstr("No erased file with that name\n"); return; }
    if (dd_write()) pstr("Write error!\n");
}
