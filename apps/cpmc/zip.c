/* ZIP - hace un .ZIP con deflate (LZ77 con ventana de 4 KB y Huffman fijo)
   ZIP [-0] [-T] archivo[.ZIP] archivo...   (admite * y ?)
   -0 sin comprimir; -T texto: cada archivo solo hasta el primer ^Z.
   Si comprimido sale mas grande, lo guarda sin comprimir. El archivo se rellena
   hasta el final del registro con un campo extra del directorio, asi el .ZIP
   termina justo donde termina el archivo de CP/M. */
#include <string.h>
#include "cpm.h"
#include "crc32.h"

#define WSIZE 4096
#define WMASK (WSIZE - 1)
#define MINLA 262
#define NIL 0xFFFF
#define MAXF 64
static uint8_t win[2 * WSIZE];
static uint16_t head[4096], prev[WSIZE];
static uint16_t lookend;
static uint8_t ineof, text, chain = 16;
static FCB inf;
static uint32_t icrc, isize;

/* ---- salida con acceso directo (para volver a la cabecera) */
static FCB zf;
static uint8_t ob[128], oi, odirty, oerr;
static uint16_t orec, ohigh;
static uint32_t opos;
static void oload(void)
{
    if (orec < ohigh) { if (rread(&zf, orec, ob)) oerr = 1; }
    else memset(ob, 0, 128);
    odirty = 0;
}
static void oflush(void)
{
    if (odirty) {
        if (rwrite(&zf, orec, ob)) oerr = 1;
        if (orec >= ohigh) ohigh = orec + 1;
        odirty = 0;
    }
}
static void oseek(uint32_t p)
{
    oflush();
    orec = p >> 7; oi = p & 127; opos = p;
    oload();
}
void putb(uint8_t c)
{
    ob[oi++] = c; odirty = 1; opos++;
    if (oi == 128) { oflush(); orec++; oi = 0; oload(); }
}
static void put2(uint16_t v) { putb(v); putb(v >> 8); }
static void put4(uint32_t v) { put2(v); put2(v >> 16); }

/* ---- bits, el primero el bajo (zip_a.s) */
uint8_t bacc, bcnt;
void pbits(uint16_t v, uint8_t n) __sdcccall(0);
void putbacc(void) { putb(bacc); }
static void palign(void) { if (bcnt) { putb(bacc >> (8 - bcnt)); bacc = bcnt = 0; } }

/* los codigos fijos, ya al reves (Huffman va con el bit alto primero) */
static uint16_t lrev[288];
static uint8_t lcode[256], dsmall[256], dbig[32], drev[24];
static const uint16_t lbase[29] = {3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,
                                   67,83,99,115,131,163,195,227,258};
static const uint8_t lext[29] = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0};
static const uint16_t dbase[24] = {1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,
                                   769,1025,1537,2049,3073};
static const uint8_t dext[24] = {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10};
static uint16_t rev(uint16_t c, uint8_t n)
{
    uint16_t r = 0;
    while (n--) { r = (r << 1) | (c & 1); c >>= 1; }
    return r;
}
static uint8_t llen(uint16_t s) { return s < 144 ? 8 : s < 256 ? 9 : s < 280 ? 7 : 8; }
static void tables(void)
{
    uint16_t s; uint8_t c;
    for (s = 0; s < 288; s++)
        lrev[s] = rev(s < 144 ? 0x30 + s : s < 256 ? 0x190 + s - 144 : s < 280 ? s - 256 : 0xC0 + s - 280, llen(s));
    for (c = 0, s = 3; s <= 258; s++) { while (c < 28 && lbase[c + 1] <= s) c++; lcode[s - 3] = c; }
    for (c = 0, s = 1; s <= 256; s++) { while (c < 23 && dbase[c + 1] <= s) c++; dsmall[s - 1] = c; }
    for (c = 0; c < 24; c++) drev[c] = rev(c, 5);
    for (s = 0; s < 32; s++) { uint16_t d = (s << 7) + 1; c = 0; while (c < 23 && dbase[c + 1] <= d) c++; dbig[s] = c; }
}
static void lit(uint16_t s) { pbits(lrev[s], llen(s)); }
static void match(uint16_t len, uint16_t dist)
{
    uint8_t c = lcode[len - 3];
    pbits(lrev[257 + c], llen(257 + c));
    if (lext[c]) pbits(len - lbase[c], lext[c]);
    c = dist <= 256 ? dsmall[dist - 1] : dbig[(dist - 1) >> 7];
    pbits(drev[c], 5);
    if (dext[c]) pbits(dist - dbase[c], dext[c]);
}

/* ---- entrada */
static void fill(void)
{
    while (!ineof && lookend + 128 <= 2 * WSIZE) {
        uint8_t n = 128;
        if (fread(&inf, win + lookend)) { ineof = 1; break; }
        if (text) {
            uint8_t *z = memchr(win + lookend, 0x1A, 128);
            if (z) { n = z - (win + lookend); ineof = 1; }
        }
        icrc = crcbuf(icrc, win + lookend, n);
        isize += n;
        lookend += n;
    }
}
void slidetab(uint16_t *p, uint16_t n) __sdcccall(0);    /* zip_a.s */
uint16_t mlen(uint8_t *a, uint8_t *b, uint16_t lim) __sdcccall(0);
static void slide(void)
{
    memcpy(win, win + WSIZE, WSIZE);
    lookend -= WSIZE;
    slidetab(head, 4096);
    slidetab(prev, WSIZE);
}
#define HASH(p) ((((uint16_t)win[p] << 4) ^ ((uint16_t)win[(p) + 1] << 2) ^ win[(p) + 2] \
                 ^ ((uint16_t)win[p] << 8)) & 4095)
static uint8_t deflate(void)
{
    uint16_t s = 0;
    memset(head, 0xFF, sizeof head);
    lookend = 0; ineof = 0;
    fill();
    pbits(1, 1); pbits(1, 2);                 /* el ultimo bloque, Huffman fijo */
    while (s < lookend) {
        uint16_t avail, best = 0, bdist = 0;
        if (!ineof && lookend - s < MINLA) {
            if (lookend == 2 * WSIZE) { slide(); s -= WSIZE; }
            fill();
        }
        avail = lookend - s;
        if (avail >= 3) {
            uint16_t h = HASH(s), c = head[h], lim = avail > 258 ? 258 : avail;
            uint8_t n = chain;
            prev[s & WMASK] = c; head[h] = s;
            while (c != NIL && c < s && s - c < WSIZE && n--) {
                uint8_t *a = win + c, *b = win + s;
                if (a[best] == b[best] && a[0] == b[0]) {
                    uint16_t l = mlen(a, b, lim);
                    if (l > best) { best = l; bdist = s - c; if (l == lim) break; }
                }
                {
                    uint16_t nx = prev[c & WMASK];
                    if (nx >= c) break;
                    c = nx;
                }
            }
        }
        if (best >= 3) {
            uint16_t e = s + best;
            match(best, bdist);
            for (s++; s < e; s++)
                if (lookend - s >= 3) { uint16_t h = HASH(s); prev[s & WMASK] = head[h]; head[h] = s; }
        } else lit(win[s++]);
        if (oerr) return 1;
        if (!(s & 1023) && brk()) return 2;
    }
    lit(256);
    palign();
    return 0;
}

/* ---- el archivo */
typedef struct { char n[12]; uint8_t meth; uint32_t crc, csz, usz, ofs; } ENT;
static ENT ent[MAXF];
static NAME12 nm[MAXF];
static uint16_t dtime, ddate;
static uint8_t znlen(ENT *e) { return strlen(e->n); }
static void lhead(ENT *e)
{
    put4(0x04034B50UL); put2(20); put2(0); put2(e->meth); put2(dtime); put2(ddate);
    put4(e->crc); put4(e->csz); put4(e->usz); put2(znlen(e)); put2(0);
    { char *p = e->n; while (*p) putb(*p++); }
}
static void store(void)                   /* copia el archivo sin comprimir */
{
    static uint8_t r[128];
    uint32_t left = isize;
    inf.ex = inf.s2 = inf.cr = 0;
    fopen(&inf);
    while (left && !fread(&inf, r)) {
        uint8_t n = left > 128 ? 128 : left, i;
        for (i = 0; i < n; i++) putb(r[i]);
        left -= n;
    }
}
void main(void)
{
    char *p = args(), *a, *arch = 0, s[16];
    uint8_t nn = 0, i, nf = 0, raw = 0;
    uint32_t cd, cdsz, tu = 0, tc = 0;
    while ((a = nextarg(&p))) {
        if (*a == '-') {
            for (a++; *a; a++)
                if (*a == '0') raw = 1; else if (*a == 'T') text = 1;
                else if (*a == '9') chain = 64; else if (*a == '1') chain = 4;
        } else if (!arch) arch = a;
        else {
            uint8_t n = glob(a, nm + nn, MAXF - nn);
            if (!n) pf("%s: not found\n", a);
            nn += n;
            if (nn == MAXF) { pf("Only %u files\n", MAXF); break; }
        }
    }
    if (!arch || !nn) {
        pstr("Usage: ZIP [-0] [-1] [-9] [-T] archive[.ZIP] file...\n"
             "  -0 store only, -1 faster, -9 smaller, -T text: stop at ^Z\n");
        return;
    }
    if (!mkfcb(&zf, arch)) { pstr("Bad name\n"); return; }
    if (zf.f[8] == ' ') memcpy(zf.f + 8, "ZIP", 3);
    if (ismpm()) {
        TOD t; uint16_t y; uint8_t mo, d;
        gettod(&t);
        ymd(t.day, &y, &mo, &d);
        dtime = (bcd(t.h) << 11) | (bcd(t.m) << 5) | (bcd(t.s) >> 1);
        ddate = ((y - 1980) << 9) | (mo << 5) | d;
    } else { dtime = 0; ddate = (0 << 9) | (1 << 5) | 1; }
    crcinit();
    tables();
    if (fmake(&zf)) { pstr("Cannot create the archive (directory full?)\n"); return; }
    ohigh = 0; orec = 0; oi = 0; opos = 0; oload();
    for (i = 0; i < nn; i++) {
        ENT *e = ent + nf;
        uint32_t hdr, dat;
        uint8_t r;
        nm2fcb(nm[i], &inf);
        if ((inf.dr == zf.dr || !inf.dr || !zf.dr) && !memcmp(inf.f, zf.f, 11)) continue;
        fname(&inf, s);
        { char *q = s[1] == ':' ? s + 2 : s; strcpy(e->n, q); }
        if (fopen(&inf)) { pf("%s: cannot open\n", s); continue; }
        pf("  adding: %s", e->n);
        hdr = opos;
        e->ofs = hdr; e->meth = raw ? 0 : 8; e->crc = e->csz = e->usz = 0;
        lhead(e);
        dat = opos;
        icrc = 0xFFFFFFFFUL; isize = 0;
        if (raw) {
            lookend = 0; ineof = 0;
            for (;;) {
                fill();
                { uint16_t j; for (j = 0; j < lookend; j++) putb(win[j]); }
                if (ineof) break;
                lookend = 0;
                if (brk()) { r = 2; goto stop; }
            }
            r = 0;
        } else r = deflate();
    stop:
        if (r == 2) { pstr("\nStopped\n"); fclose(&inf); oflush(); fclose(&zf); fdelete(&zf); return; }
        e->crc = ~icrc; e->usz = isize; e->csz = opos - dat;
        if (e->meth == 8 && e->csz >= e->usz) {         /* no gano: sin comprimir */
            oseek(dat);
            store();
            e->meth = 0; e->csz = opos - dat;
        }
        fclose(&inf);
        {
            uint32_t end = opos;
            oseek(hdr + 8); put2(e->meth);
            oseek(hdr + 14); put4(e->crc); put4(e->csz); put4(e->usz);
            oseek(end);
        }
        if (oerr) { pstr("\nWrite error (disk full?)\n"); fclose(&zf); return; }
        if (e->meth) pf(" (deflated %u%%)\n", e->usz ? (uint8_t)(100 - e->csz * 100 / e->usz) : 0);
        else pstr(" (stored 0%)\n");
        tu += e->usz; tc += e->csz;
        nf++;
    }
    if (!nf) { pstr("Nothing to add\n"); fclose(&zf); fdelete(&zf); return; }
    /* el directorio central; el relleno va en un campo extra del ultimo */
    cd = opos; cdsz = 0;
    for (i = 0; i < nf; i++) cdsz += 46 + znlen(ent + i);
    {
        uint32_t end = cd + cdsz + 4 + 22, tgt = (end + 127) & ~127UL;
        uint16_t pad;
        if ((uint32_t)ohigh << 7 > tgt) tgt = (uint32_t)ohigh << 7;
        pad = tgt - end;
        for (i = 0; i < nf; i++) {
            ENT *e = ent + i;
            uint8_t last = i == nf - 1;
            put4(0x02014B50UL); put2(20); put2(20); put2(0); put2(e->meth);
            put2(dtime); put2(ddate); put4(e->crc); put4(e->csz); put4(e->usz);
            put2(znlen(e)); put2(last ? 4 + pad : 0); put2(0); put2(0); put2(0);
            put4(0x20); put4(e->ofs);
            { char *q = e->n; while (*q) putb(*q++); }
            if (last) { uint16_t j; put2(0x5A50); put2(pad); for (j = 0; j < pad; j++) putb(0); }
        }
        cdsz += 4 + pad;
    }
    put4(0x06054B50UL); put2(0); put2(0); put2(nf); put2(nf); put4(cdsz); put4(cd); put2(0);
    oflush();
    fclose(&zf);
    if (oerr) { pstr("Write error (disk full?)\n"); return; }
    pf("%u files, %lu -> %lu bytes\n", nf, tu, opos);
}
