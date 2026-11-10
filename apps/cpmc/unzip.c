/* UNZIP - saca los archivos de un .ZIP (guardados o con deflate)
   UNZIP archivo[.ZIP] [d:]     los saca a la unidad d (o a la actual)
   UNZIP -L archivo[.ZIP]       solo la lista
   UNZIP -O ...                 sin preguntar si ya existen
   Los nombres se pasan a 8.3 en mayusculas (sin carpetas); el ultimo
   registro se rellena con ^Z. Se comprueba el CRC-32 de cada uno. */
#include <string.h>
#include "cpm.h"
#include "crc32.h"

/* ---- lectura del .ZIP en cualquier posicion */
static FCB zf;
static uint8_t zb[128];
static uint16_t zrec = 0xFFFF;
static uint32_t zpos, zlen;
uint8_t zerr;
static uint8_t zi = 128;               /* el siguiente de zb; 128: hay que leer */
static void seek(uint32_t p) { zpos = p; zi = 128; }
uint8_t getb(void) __sdcccall(0)        /* (tambien la llama unzip_a.s) */
{
    if (zi >= 128) {
        uint16_t r = zpos >> 7;
        if (r != zrec) {
            zrec = r;
            if (rread(&zf, r, zb)) { zerr = 1; memset(zb, 0, 128); }
        }
        zi = (uint8_t)zpos & 127;
    }
    zpos++;
    return zb[zi++];
}
static uint16_t get2(void) { uint8_t l = getb(); return l | (getb() << 8); }
static uint32_t get4(void) { uint16_t l = get2(); return l | ((uint32_t)get2() << 16); }

/* ---- salida: la ventana de 32 KB es tambien el bufer del archivo */
static uint8_t win[32768];
static uint16_t wp, wf;                 /* donde se escribe y lo ya grabado */
static FCB of;
static uint32_t ocrc, ocount, olimit;
static uint8_t oerr;
static void flushw(void)                /* el ultimo registro, con ^Z */
{
    uint16_t n = (wp - wf) & 0x7FFF;
    if (n) {
        memset(win + wf + n, 0x1A, 128 - n);
        if (fwrite(&of, win + wf)) oerr = 1;
    }
}
static void out(uint8_t c)
{
    win[wp] = c;
    wp = (wp + 1) & 0x7FFF;
    ocount++;
    if (!(wp & 127)) {
        ocrc = crcbuf(ocrc, win + ((wp - 128) & 0x7FFF), 128);
        if (fwrite(&of, win + wf)) oerr = 1;
        wf = wp;
    }
}

/* ---- inflate (como tinf de J. Ibsen, sencillo) */
typedef struct { uint16_t cnt[16]; uint16_t sym[288]; } TREE;
static TREE lt, dt;
static uint8_t lens[288 + 32];
static const uint16_t lbase[29] = {3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,
                                   67,83,99,115,131,163,195,227,258};
static const uint8_t lext[29] = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0};
static const uint16_t dbase[30] = {1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,
                                   769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577};
static const uint8_t dext[30] = {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,
                                 12,12,13,13};
static const uint8_t clord[19] = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15};

uint8_t bitbuf, bitn;                   /* los usa unzip_a.s */
uint8_t bit(void) __sdcccall(0);        /* unzip_a.s */
uint16_t bits(uint8_t n) __sdcccall(0);
static void build(TREE *t, const uint8_t *l, uint16_t n)
{
    uint16_t offs[16], s, i;
    memset(t->cnt, 0, sizeof t->cnt);
    for (i = 0; i < n; i++) t->cnt[l[i]]++;
    t->cnt[0] = 0;
    for (s = 0, i = 0; i < 16; i++) { offs[i] = s; s += t->cnt[i]; }
    for (i = 0; i < n; i++) if (l[i]) t->sym[offs[l[i]]++] = i;
}
uint16_t decode(TREE *t) __sdcccall(0);  /* unzip_a.s */
static void fixed(void)
{
    uint16_t i;
    for (i = 0; i < 144; i++) lens[i] = 8;
    for (; i < 256; i++) lens[i] = 9;
    for (; i < 280; i++) lens[i] = 7;
    for (; i < 288; i++) lens[i] = 8;
    build(&lt, lens, 288);
    for (i = 0; i < 30; i++) lens[i] = 5;
    build(&dt, lens, 30);
}
static uint8_t dynamic(void)
{
    uint16_t hlit = bits(5) + 257, hdist = bits(5) + 1, i, n;
    uint8_t hclen = bits(4) + 4;
    memset(lens, 0, 19);
    for (i = 0; i < hclen; i++) lens[clord[i]] = bits(3);
    build(&lt, lens, 19);
    for (n = 0; n < hlit + hdist; ) {
        uint16_t s = decode(&lt);
        uint8_t rep, v;
        if (zerr) return 1;
        if (s < 16) { lens[n++] = s; continue; }
        if (s == 16) { if (!n) return 1; v = lens[n - 1]; rep = 3 + bits(2); }
        else if (s == 17) { v = 0; rep = 3 + bits(3); }
        else { v = 0; rep = 11 + bits(7); }
        if (n + rep > hlit + hdist) return 1;
        while (rep--) lens[n++] = v;
    }
    build(&lt, lens, hlit);
    build(&dt, lens + hlit, hdist);
    return 0;
}
static uint8_t inflate(void)
{
    uint8_t final;
    bitn = 0;
    do {
        uint8_t type;
        final = bit();
        type = bits(2);
        if (type == 0) {
            uint16_t len;
            bitn = 0;
            len = get2(); get2();
            while (len--) out(getb());
        } else if (type == 3) return 1;
        else {
            if (type == 1) fixed(); else if (dynamic()) return 1;
            for (;;) {
                uint16_t s = decode(&lt);
                if (zerr) return 1;
                if (s < 256) out(s);
                else if (s == 256) break;
                else {
                    uint16_t len, dist, from;
                    s -= 257;
                    if (s >= 29) return 1;
                    len = lbase[s] + bits(lext[s]);
                    s = decode(&dt);
                    if (s >= 30) return 1;
                    dist = dbase[s] + bits(dext[s]);
                    from = wp - dist;
                    while (len--) { out(win[from & 0x7FFF]); from++; }
                }
                if (ocount > olimit) return 1;
            }
        }
        if (brk()) return 2;
    } while (!final);
    return 0;
}

/* ---- nombres */
static uint8_t bad(char c)
{
    return c <= ' ' || c > '~' || strchr("<>.,;:=?*[]%|()/\\\"", c);
}
static void to83(const char *s, char *o)
{
    const char *b = s, *dot = 0, *p;
    uint8_t i;
    for (p = s; *p; p++) if (*p == '/' || *p == '\\') b = p + 1;
    for (p = b; *p; p++) if (*p == '.') dot = p;
    for (i = 0, p = b; *p && p != dot && i < 8; p++) {
        char c = *p >= 'a' && *p <= 'z' ? *p - 32 : *p;
        o[i++] = bad(c) ? '_' : c;
    }
    if (!i) o[i++] = '_';
    if (dot) {
        uint8_t j = 0;
        o[i++] = '.';
        for (p = dot + 1; *p && j < 3; p++, j++) {
            char c = *p >= 'a' && *p <= 'z' ? *p - 32 : *p;
            o[i++] = bad(c) ? '_' : c;
        }
        if (!j) i--;
    }
    o[i] = 0;
}

static char zname[256];
void main(void)
{
    char *p = args(), *a, *arch = 0, *drv = 0, nm[16];
    uint8_t list = 0, over = 0, i, all = 0;
    uint16_t nent, e, ok = 0, bad_ = 0;
    uint32_t cdpos, end;
    while ((a = nextarg(&p))) {
        if (*a == '-') { for (a++; *a; a++) if (*a == 'L') list = 1; else if (*a == 'O') over = 1; }
        else if (!arch) arch = a;
        else drv = a;
    }
    if (!arch) {
        pstr("Usage: UNZIP [-L] [-O] file[.ZIP] [d:]\n"
             "  -L list only, -O overwrite without asking, d: where to put the files\n");
        return;
    }
    if (!mkfcb(&zf, arch)) { pstr("Bad name\n"); return; }
    if (zf.f[8] == ' ') memcpy(zf.f + 8, "ZIP", 3);
    if (fopen(&zf)) { pf("%s: not found\n", arch); return; }
    zlen = (uint32_t)fsize(&zf) << 7;
    if ((uint16_t)(*(uint16_t *)6) < (uint16_t)(win + sizeof win) + 256) { pstr("Not enough memory\n"); return; }
    /* el final del directorio: PK 5 6, buscando hacia atras */
    end = zlen < 1200 ? 0 : zlen - 1200;
    for (cdpos = zlen - 22; ; cdpos--) {
        seek(cdpos);
        if (getb() == 'P' && getb() == 'K' && getb() == 5 && getb() == 6) break;
        if (cdpos <= end || zerr) { pstr("Not a ZIP file (or the comment is too long)\n"); return; }
    }
    get2(); get2(); get2();
    nent = get2();
    get4();
    cdpos = get4();
    crcinit();
    if (list) pstr("  Length  Method    Size  Ratio   Date    Time   CRC-32   Name\n"
                   " -------  ------  ------  -----  --------  -----  --------  ----\n");
    for (e = 0; e < nent; e++) {
        uint16_t flags, meth, tim, dat, nl, xl, cl, k;
        uint32_t crc, csz, usz, lofs;
        seek(cdpos);
        if (get4() != 0x02014B50UL) { pstr("Bad central directory\n"); return; }
        get2(); get2();
        flags = get2(); meth = get2(); tim = get2(); dat = get2();
        crc = get4(); csz = get4(); usz = get4();
        nl = get2(); xl = get2(); cl = get2();
        get2(); get2(); get4();
        lofs = get4();
        for (k = 0; k < nl; k++) { uint8_t c = getb(); if (k < 255) zname[k] = c; }
        zname[nl < 255 ? nl : 255] = 0;
        cdpos = zpos + xl + cl;
        if (list) {
            uint8_t r = usz ? 100 - (uint8_t)(csz * 100 / usz > 100 ? 100 : csz * 100 / usz) : 0;
            pf("%8lu  %s %8lu  %3u%%  %02u-%02u-%02u  %02u:%02u  %08lx  %s\n",
               usz, meth == 8 ? "Defl:N" : meth ? "Other " : "Stored", csz, r,
               (dat >> 5) & 15, dat & 31, ((dat >> 9) + 80) % 100, tim >> 11, (tim >> 5) & 63,
               crc, zname);
            continue;
        }
        if (nl && zname[nl - 1] == '/') continue;          /* carpeta */
        to83(zname, nm);
        pf("%s", zname);
        if (strcmp(zname, nm)) pf(" -> %s", nm);
        if (flags & 1) { pstr(": encrypted, skipped\n"); bad_++; continue; }
        if (meth != 0 && meth != 8) { pf(": method %u not supported, skipped\n", meth); bad_++; continue; }
        if (usz > 0x7FFFFFUL) { pstr(": too large\n"); bad_++; continue; }
        /* el archivo de salida */
        {
            char full[20];
            if (drv && drv[1] == ':') { full[0] = drv[0]; full[1] = ':'; strcpy(full + 2, nm); }
            else strcpy(full, nm);
            mkfcb(&of, full);
        }
        if (!over && !all && !fopen(&of)) {
            int k2;
            fclose(&of);
            pstr(": exists. Overwrite? (Y/N/A=all) ");
            k2 = waitkey() | 32;
            pf("%c\n", k2 - 32);
            if (k2 == 'a') all = 1;
            else if (k2 != 'y') continue;
            pf("%s", nm);
        }
        if (fmake(&of)) { pstr(": cannot create (directory full?)\n"); bad_++; continue; }
        seek(lofs + 26);
        k = get2();
        k += get2();
        seek(lofs + 30 + k);
        wp = wf = 0; ocrc = 0xFFFFFFFFUL; ocount = 0; oerr = 0; zerr = 0;
        olimit = usz;
        i = 0;
        if (meth == 0) { uint32_t n = usz; while (n--) out(getb()); }
        else i = inflate();
        /* lo que falta del CRC: lo que no llego a 128 */
        {
            uint16_t n = (wp - wf) & 0x7FFF;
            ocrc = crcbuf(ocrc, win + wf, n);
        }
        flushw();
        fclose(&of);
        if (i == 2) { pstr(": stopped\n"); fdelete(&of); return; }
        if (i || zerr) pstr(": bad compressed data\n");
        else if (oerr) pstr(": write error (disk full?)\n");
        else if (~ocrc != crc || ocount != usz) pf(": CRC error (%08lx, should be %08lx)\n", ~ocrc, crc);
        else { pf("  %lu bytes OK\n", usz); ok++; continue; }
        bad_++;
    }
    if (!list) pf("%u extracted, %u with errors\n", ok, bad_);
}
