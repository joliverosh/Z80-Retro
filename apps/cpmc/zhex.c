/* ZHEX - editor hexadecimal de archivos y de los registros de un disco
   ZHEX ARCH          un archivo (del tamano que sea: va por registros)
   ZHEX -D B: [reg]   el disco B: entero, registro por registro, por la BIOS
                      (reg: el registro con que empieza; D = el directorio)

   Teclas: flechas o ^E ^X ^S ^D mueven; ^R ^C una pantalla; Home/End;
   TAB pasa de la columna hex a la de texto; en hex se escriben las cifras,
   en texto los caracteres. ^G va a un desplazamiento (hex); ^F busca texto
   (o bytes en hex si empieza con $: $C3 00 01); ^L busca otra vez;
   ^W escribe lo cambiado; ^U deshace lo no escrito del registro; ^Q sale
   (pregunta si hay cambios sin escribir).
   No agranda ni achica el archivo. En el modo disco, escribir pide que se
   confirme, y al salir se vuelve a leer el disco (BDOS 37).
   (C) OLIVEROS 2026 */
#include <string.h>
#include "cpm.h"

#define WREC 16                  /* registros en memoria */
#define ROWS 18                  /* lineas de 16 bytes en pantalla */
#define TOP 3                    /* primera linea de los datos */

#define KUP 0x81
#define KDOWN 0x82
#define KRIGHT 0x83
#define KLEFT 0x84
#define KHOME 0x85
#define KEND 0x86
#define KPGUP 0x87
#define KPGDN 0x88

static FCB f;
static uint8_t disk, drv, dirty_any;
static uint16_t nrec;            /* registros del archivo o del disco */
static uint16_t spt, off;        /* disco: sectores por pista y pistas reservadas */
static uint8_t win[WREC][128], wdirty[WREC];
static uint8_t orig[128];        /* el registro del cursor como se leyo (^U) */
static uint16_t worig = 0xFFFF;
static uint16_t wbase = 0xFFFF;  /* el primer registro en win[] */
static uint32_t cur, top;        /* desplazamientos en bytes */
static uint8_t inasc, half;      /* columna de texto; en hex: falta la 2da cifra */
static char name[16], msgb[60], ib[40];
static uint8_t fb[32], fn;       /* lo que se busca */
static uint8_t pb[4], npb;

/* ------------------------------------------------------------ teclas */
static uint8_t rawk(void)
{
    int k;
    if (npb) return pb[--npb];
    oflush();
    while (!(k = getkey())) delay(1);
    return k;
}
static uint8_t soon(void)
{
    uint8_t n; int k;
    if (npb) return pb[--npb];
    for (n = 0; n < 60; n++) { if ((k = getkey())) return k; delay(1); }
    return 0;
}
static uint8_t key(void)
{
    uint8_t k = rawk(), k2;
    if (k != 27) return k == 127 ? 8 : k;
    k2 = soon();
    if (k2 != '[' && k2 != 'O') { if (k2) pb[npb++] = k2; return 27; }
    k = soon();
    switch (k) {
    case 'A': return KUP;
    case 'B': return KDOWN;
    case 'C': return KRIGHT;
    case 'D': return KLEFT;
    case 'H': return KHOME;
    case 'F': return KEND;
    }
    if (k >= '1' && k <= '6' && soon() == '~') {
        if (k == '1') return KHOME;
        if (k == '4') return KEND;
        if (k == '5') return KPGUP;
        if (k == '6') return KPGDN;
    }
    return 0;
}

/* ------------------------------------------------------------ registros */
static uint8_t diskio(uint8_t wr, uint16_t r, uint8_t *b)
{
    biosc(9, drv, 0);
    biosc(10, r / spt, 0);
    biosc(11, r % spt, 0);
    biosc(12, (uint16_t)b, 0);
    biosc(wr ? 14 : 13, 1, 0);
    return biosa;
}
static uint8_t recio(uint8_t wr, uint16_t r, uint8_t *b)
{
    if (disk) return diskio(wr, r, b);
    return wr ? rwrite(&f, r, b) : rread(&f, r, b);
}
static uint8_t flush(void)
{
    uint8_t i, e = 0;
    for (i = 0; i < WREC; i++)
        if (wdirty[i]) {
            if (recio(1, wbase + i, win[i])) e = 1;
            else wdirty[i] = 0;
        }
    if (!e) dirty_any = 0;
    return e;
}
/* que el registro r este en win[]; devuelve su indice */
static uint8_t need(uint16_t r)
{
    uint8_t i, any = 0;
    if (wbase != 0xFFFF && r >= wbase && r < wbase + WREC) return r - wbase;
    for (i = 0; i < WREC; i++) any |= wdirty[i];
    if (any) {                   /* lo cambiado de la ventana vieja queda en el disco */
        uint8_t keep = dirty_any;
        flush();
        dirty_any = keep;
    }
    wbase = r >= WREC / 2 ? r - WREC / 2 : 0;
    if (nrec > WREC && wbase > nrec - WREC) wbase = nrec - WREC;
    for (i = 0; i < WREC; i++) {
        if (wbase + i >= nrec || recio(0, wbase + i, win[i])) memset(win[i], 0x1A, 128);
        wdirty[i] = 0;
    }
    return r - wbase;
}
static uint8_t *bp(uint32_t o)
{
    uint8_t i = need((uint16_t)(o >> 7));
    return &win[i][(uint8_t)o & 127];
}

/* ------------------------------------------------------------ pantalla */
static const char hx[] = "0123456789ABCDEF";
static void phex(uint32_t v, uint8_t n)
{
    while (n--) putch(hx[(v >> (n * 4)) & 15]);
}
static void status(void)
{
    gotoxy(1, 1);
    pf(ESC "[7m ZHEX %s  ", name);
    if (disk) pf("record %u (track %u, sector %u)  ", (uint16_t)(cur >> 7), (uint16_t)(cur >> 7) / spt, (uint16_t)(cur >> 7) % spt);
    pstr("offset "); phex(cur, 6);
    pf("  of %u records%s " ESC "[0m" ESC "[K", nrec, dirty_any ? "  (changed)" : "");
    gotoxy(1, 2);
    if (msgb[0]) { pf("%s", msgb); msgb[0] = 0; }
    pstr(ESC "[K");
}
static void draw(void)
{
    uint8_t r, c, b;
    uint32_t o;
    for (r = 0; r < ROWS; r++) {
        o = top + ((uint16_t)r << 4);
        gotoxy(1, TOP + r);
        if ((uint16_t)(o >> 7) >= nrec) { pstr(ESC "[K"); continue; }
        phex(o, 6); pstr("  ");
        for (c = 0; c < 16; c++) {
            b = *bp(o + (uint16_t)c);
            if (o + (uint16_t)c == cur && !inasc) pstr(ESC "[7m");
            putch(hx[b >> 4]); putch(hx[b & 15]);
            if (o + (uint16_t)c == cur && !inasc) pstr(ESC "[0m");
            putch(c == 7 ? '-' : ' ');
        }
        putch(' ');
        for (c = 0; c < 16; c++) {
            b = *bp(o + (uint16_t)c);
            if (o + (uint16_t)c == cur && inasc) pstr(ESC "[7m");
            putch(b >= 32 && b < 127 ? b : '.');
            if (o + (uint16_t)c == cur && inasc) pstr(ESC "[0m");
        }
        pstr(ESC "[K");
    }
    gotoxy(1, TOP + ROWS + 1);
    pstr("^W write  ^Q quit  TAB hex/text  ^G go to  ^F find  ^L again  ^U undo" ESC "[K");
    status();
    gotoxy(inasc ? 59 + ((uint8_t)cur & 15) : 9 + 3 * ((uint8_t)cur & 15) + half, TOP + (uint8_t)((cur - top) >> 4));
}
static uint8_t ask(const char *q)
{
    uint8_t n = 0, c;
    gotoxy(1, 2); pf("%s", q); pstr(ESC "[K");
    for (;;) {
        c = rawk();
        if (c == 27 || c == 3) { ib[0] = 0; return 0; }
        if (c == '\r') break;
        if ((c == 8 || c == 127) && n) { n--; pstr("\b \b"); continue; }
        if (c >= 32 && c < 127 && n < sizeof ib - 1) { ib[n++] = c; putch(c); }
    }
    ib[n] = 0;
    return n;
}

/* ------------------------------------------------------------ mover */
static uint32_t size(void) { return (uint32_t)nrec << 7; }
static void moveto(uint32_t o)
{
    if ((int32_t)o < 0) o = 0;
    if (o >= size()) o = size() - 1;
    if ((cur >> 7) != (o >> 7)) worig = 0xFFFF;
    cur = o; half = 0;
    if (cur < top) top = cur & ~(uint32_t)15;
    if (cur >= top + ROWS * 16) top = (cur & ~(uint32_t)15) - (ROWS - 1) * 16;
}
static uint8_t hexd(uint8_t c)
{
    if (c >= '0' && c <= '9') return c - '0';
    c |= 32;
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return 0xFF;
}
static void setb(uint8_t v)
{
    uint16_t r = (uint16_t)(cur >> 7);
    uint8_t i = need(r);
    if (worig != r) { memcpy(orig, win[i], 128); worig = r; }
    win[i][(uint8_t)cur & 127] = v;
    wdirty[i] = 1; dirty_any = 1;
}
static void find(void)
{
    uint32_t o;
    uint8_t k;
    uint16_t lastr = 0xFFFF;
    if (!fn) { strcpy(msgb, "Nothing to find (^F)"); return; }
    for (o = cur + 1; o + (uint16_t)fn <= size(); o++) {
        if ((uint16_t)(o >> 7) != lastr) {
            lastr = (uint16_t)(o >> 7);
            if (!(lastr & 63) && brk()) { strcpy(msgb, "Stopped"); return; }
        }
        for (k = 0; k < fn && *bp(o + (uint16_t)k) == fb[k]; k++) ;
        if (k == fn) { moveto(o); return; }
    }
    strcpy(msgb, "Not found");
}
static void setfind(void)
{
    char *p = ib;
    uint8_t a, b;
    if (!ask("Find (text, or $ and hex bytes): ")) return;
    fn = 0;
    if (*p == '$') {
        for (p++; *p && fn < sizeof fb; ) {
            while (*p == ' ') p++;
            if (!*p) break;
            a = hexd(*p++); b = hexd(*p);
            if (a == 0xFF) { strcpy(msgb, "Bad hex"); fn = 0; return; }
            if (b != 0xFF) { p++; fb[fn++] = (a << 4) | b; } else fb[fn++] = a;
        }
    } else
        for (; *p && fn < sizeof fb; p++) fb[fn++] = *p;
    find();
}
static uint16_t atou(char *s)
{
    uint16_t v = 0;
    while (*s == ' ') s++;
    while (*s >= '0' && *s <= '9') v = v * 10 + (*s++ - '0');
    return v;
}
static void goto_(void)
{
    uint32_t v = 0;
    char *p = ib;
    uint8_t d;
    if (!ask("Go to offset (hex; R and a number: record): ")) return;
    if ((*p | 32) == 'r') { moveto((uint32_t)(uint16_t)atou(p + 1) << 7); return; }
    for (; (d = hexd(*p)) != 0xFF; p++) v = (v << 4) | d;
    moveto(v);
}
static uint8_t writeall(void)
{
    if (!dirty_any) { strcpy(msgb, "Nothing to write"); return 0; }
    if (disk) {
        if (!ask("Write the changed records to the DISK? (Y/N) ") || (ib[0] | 32) != 'y') { strcpy(msgb, "Not written"); return 1; }
    }
    if (flush()) { strcpy(msgb, "Write error"); return 1; }
    worig = 0xFFFF;
    strcpy(msgb, "Written");
    return 0;
}

/* ------------------------------------------------------------ disco */
static uint8_t opendisk(char *a, char *rs)
{
    uint16_t dph, dpb, dsm;
    uint8_t bsh;
    uint32_t n;
    if (!a || a[1] != ':' || (a[0] | 32) < 'a' || (a[0] | 32) > 'p') return 1;
    drv = (a[0] | 32) - 'a';
    dph = biosc(9, drv, 0);
    if (!dph) { pstr("No such drive\n"); return 2; }
    dpb = *(uint16_t *)(dph + 10);
    spt = *(uint16_t *)dpb;
    bsh = *(uint8_t *)(dpb + 2);
    dsm = *(uint16_t *)(dpb + 5);
    off = *(uint16_t *)(dpb + 13);
    /* las pistas reservadas y DSM + 1 bloques de 2^BSH registros */
    n = (uint32_t)off * spt + ((uint32_t)(dsm + 1) << bsh);
    nrec = n > 65535L ? 65535 : (uint16_t)n;
    disk = 1;
    name[0] = a[0] & ~32; name[1] = ':'; name[2] = 0;
    if (rs) {
        if ((*rs | 32) == 'd') cur = (uint32_t)off * spt << 7;
        else cur = (uint32_t)atou(rs) << 7;
    }
    return 0;
}

void main(void)
{
    char *p = args(), *a = nextarg(&p);
    uint8_t k, d, quit = 0;
    if (!a) { pstr("Usage: ZHEX file   or   ZHEX -D drive: [record | D]\n"); return; }
    if (a[0] == '-' && (a[1] | 32) == 'd') {
        a = nextarg(&p);
        if ((k = opendisk(a, nextarg(&p)))) { if (k == 1) pstr("Usage: ZHEX -D B: [record | D]\n"); return; }
    } else {
        if (!mkfcb(&f, a) || fopen(&f)) { pf("ZHEX: no %s\n", a); return; }
        nrec = fsize(&f);
        fname(&f, name);
        if (!nrec) { pf("ZHEX: %s is empty\n", name); return; }
    }
    if (cur >= size()) cur = 0;
    top = cur & ~(uint32_t)15;
    pstr(CLS);
    while (!quit) {
        draw();
        k = key();
        switch (k) {
        case KUP: case 5: moveto(cur - 16); break;
        case KDOWN: case 24: moveto(cur + 16); break;
        case KLEFT: case 19: if (half) half = 0; else moveto(cur - 1); break;
        case KRIGHT: case 4: moveto(cur + 1); break;
        case KPGUP: case 18: top = top >= ROWS * 16 ? top - ROWS * 16 : 0; moveto(cur >= ROWS * 16 ? cur - ROWS * 16 : 0); break;
        case KPGDN: case 3:
            if (cur + ROWS * 16 < size()) { top += ROWS * 16; moveto(cur + ROWS * 16); }
            else moveto(size() - 1);
            break;
        case KHOME: moveto(0); break;
        case KEND: moveto(size() - 1); break;
        case 9: inasc ^= 1; half = 0; break;
        case 7: goto_(); break;
        case 6: setfind(); break;
        case 12: find(); break;
        case 23: writeall(); break;
        case 21:
            if (worig == (uint16_t)(cur >> 7)) {
                memcpy(win[need(worig)], orig, 128);
                strcpy(msgb, "Record restored");
            }
            break;
        case 17:
            if (dirty_any) {
                if (!ask("There are changes. Write them? (Y/N, ESC: stay) ")) break;
                if ((ib[0] | 32) == 'y' && writeall()) break;
            }
            quit = 1;
            break;
        default:
            if (inasc) {
                if (k >= 32 && k < 127) { setb(k); moveto(cur + 1); }
            } else if ((d = hexd(k)) != 0xFF) {
                uint8_t *b = bp(cur);
                if (!half) { setb((*b & 15) | (d << 4)); half = 1; }
                else { setb((*b & 0xF0) | d); moveto(cur + 1); }
            }
        }
    }
    if (disk) bdos(37, 0xFFFF); else fclose(&f);
    pstr(CLS);
}
