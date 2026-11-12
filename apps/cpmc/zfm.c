/* ZFM - administrador de archivos de dos paneles, como el Norton Commander: cada panel
   muestra una unidad y un usuario; se copian, mueven, renombran, borran y miran archivos,
   y Enter abre cada uno con su programa (ZBAS, ZCALC, ZDATA, ZWRITE) o lo corre.
   Teclas: flechas, RePag/AvPag, Inicio/Fin, Tab (el otro panel), Espacio (marca), * (todos),
   Enter (abrir), V ver, E editar, C copiar, M mover, R renombrar, D o Supr borrar,
   L unidad, U usuario, I informacion, ? ayuda, Q salir. Tambien F3 F4 F5 F6 F8 F10.
   Los mensajes van en ingles. (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 50000 */
#include <string.h>
#include "cpm.h"

#define MAXF 256                 /* archivos por panel */
#define TOP 3                    /* primera fila de la lista */
#define ROWS 19                  /* filas de la lista */
#define MSGROW 22
#define KEYROW 23
#define INV ESC "[7m"
#define NORM ESC "[0m"
#define EOL ESC "[K"

enum { K_UP = 0x81, K_DOWN, K_RIGHT, K_LEFT, K_PGUP, K_PGDN, K_HOME, K_END, K_DEL,
       K_F1, K_F2, K_F3, K_F4, K_F5, K_F6, K_F7, K_F8, K_F9, K_F10 };

typedef struct { char n[11]; uint8_t tag; uint16_t rec; } fent;   /* rec: registros de 128 */
typedef struct {
    uint8_t drv, usr;            /* unidad (0 = A) y usuario */
    uint16_t n, cur, top, ntag;
    uint16_t freek;              /* KB libres */
    fent f[MAXF];
} panel;
static panel pn[2];
static uint8_t act;              /* el panel activo */
static uint8_t dma[128];
static uint8_t buf[16 * 128];    /* para copiar */
static char line[64];
static uint8_t startu, startd;   /* usuario y unidad de antes */

/* ---------------------------------------------------------------- teclado */
static int keyin(void)
{
    int k = waitkey(), n, c;
    if (k == 127) return K_DEL;
    if (k != 27) return k;
    for (n = 0; n < 300 && !(k = getkey()); n++) ;
    if (!k) return 27;
    if (k == 'O') {                        /* F1-F4: ESC O P..S */
        for (n = 0; n < 300 && !(k = getkey()); n++) ;
        return k >= 'P' && k <= 'S' ? K_F1 + k - 'P' : 0;
    }
    if (k != '[') return 0;
    for (n = 0; n < 300 && !(k = getkey()); n++) ;
    switch (k) {
    case 'A': return K_UP; case 'B': return K_DOWN; case 'C': return K_RIGHT; case 'D': return K_LEFT;
    case 'H': return K_HOME; case 'F': return K_END;
    }
    if (k < '0' || k > '9') return 0;
    c = k - '0';                            /* ESC [ n ~ */
    for (;;) {
        for (n = 0; n < 300 && !(k = getkey()); n++) ;
        if (k >= '0' && k <= '9') c = c * 10 + k - '0'; else break;
    }
    switch (c) {
    case 2: return ' '; case 1: case 7: return K_HOME; case 4: case 8: return K_END; case 3: return K_DEL;
    case 5: return K_PGUP; case 6: return K_PGDN;
    case 11: return K_F1; case 12: return K_F2; case 13: return K_F3; case 14: return K_F4;
    case 15: return K_F5; case 17: return K_F6; case 18: return K_F7; case 19: return K_F8;
    case 20: return K_F9; case 21: return K_F10;
    }
    return 0;
}

/* ---------------------------------------------------------------- disco */
static void setuser(uint8_t u) { bdos(32, u); }
static void fcbof(FCB *f, uint8_t drv, const char *n)
{
    memset(f, 0, sizeof(FCB));
    f->dr = drv + 1;
    memcpy(f->f, n, 11);
}
static int cmpn(const char *a, const char *b)
{
    uint8_t i;
    for (i = 0; i < 11; i++) if (a[i] != b[i]) return (uint8_t)a[i] - (uint8_t)b[i];
    return 0;
}
/* Una sola pasada por todo el directorio (BDOS 17 con '?' en la unidad: todas las
   entradas, de todos los usuarios): los archivos del usuario del panel y los bloques
   ocupados, para los KB libres. (El vector de asignacion de BDOS 27 no sirve en MP/M
   II: esta en el banco del sistema.) */
static void scan(panel *p)
{
    FCB f;
    uint8_t r, *e, *dpb, bsh, big;
    uint16_t i, j, rec, dsm, used;
    char nm[11];
    p->n = 0; p->ntag = 0;
    bdos(14, p->drv);
    dpb = (uint8_t *)bdos(31, 0);
    bsh = dpb[2];
    dsm = dpb[5] | dpb[6] << 8;
    big = dsm > 255;
    used = 0;                                   /* los bloques del directorio (AL0 AL1) */
    for (i = 0; i < 16; i++) if ((i < 8 ? dpb[9] : dpb[10]) & (0x80 >> (i & 7))) used++;
    memset(&f, '?', sizeof f);
    bdos(26, (uint16_t)dma);
    r = bdos(17, (uint16_t)&f);
    while (r != 0xFF) {
        e = dma + (r & 3) * 32;
        if (e[0] < 16) {
            for (i = 16; i < 32; i++)
                if (big) { if (e[i] | e[i + 1]) used++; i++; }
                else if (e[i]) used++;
        }
        if (e[0] == p->usr) {
            for (i = 0; i < 11; i++) nm[i] = e[i + 1] & 0x7F;
            rec = (uint16_t)((e[14] & 0x3F) * 32 + (e[12] & 0x1F)) * 128 + e[15];
            for (i = 0; i < p->n; i++) if (!cmpn(p->f[i].n, nm)) break;
            if (i < p->n) { if (rec > p->f[i].rec) p->f[i].rec = rec; }
            else if (p->n < MAXF) {
                for (j = p->n; j > 0 && cmpn(p->f[j - 1].n, nm) > 0; j--) p->f[j] = p->f[j - 1];
                memcpy(p->f[j].n, nm, 11);
                p->f[j].rec = rec; p->f[j].tag = 0;
                p->n++;
            }
        }
        r = bdos(18, 0);
    }
    used = dsm + 1 - used;                      /* los libres */
    p->freek = bsh >= 3 ? used << (bsh - 3) : used >> (3 - bsh);
    bdos(14, startd);
    if (p->cur >= p->n) p->cur = p->n ? p->n - 1 : 0;
    if (p->top > p->cur) p->top = p->cur;
}
static void nmtext(char *o, const char *n)   /* "NOMBRE.EXT" */
{
    uint8_t i;
    for (i = 0; i < 8 && n[i] != ' '; i++) *o++ = n[i];
    if (n[8] != ' ') { *o++ = '.'; for (i = 8; i < 11 && n[i] != ' '; i++) *o++ = n[i]; }
    *o = 0;
}
static uint8_t parsenm(const char *s, char *n)   /* "nombre.ext" -> 11 letras; 0 si no sirve */
{
    uint8_t i = 0, c;
    memset(n, ' ', 11);
    while (*s && *s != '.' && i < 8) {
        c = *s++; if (c >= 'a' && c <= 'z') c -= 32;
        if (c <= ' ' || c == '*' || c == '?' || c == ':' || c == ',') return 0;
        n[i++] = c;
    }
    if (!i) return 0;
    while (*s && *s != '.') s++;
    if (*s == '.') {
        s++; i = 8;
        while (*s && i < 11) {
            c = *s++; if (c >= 'a' && c <= 'z') c -= 32;
            if (c <= ' ' || c == '*' || c == '?' || c == ':' || c == '.') return 0;
            n[i++] = c;
        }
    }
    return 1;
}

/* ---------------------------------------------------------------- pantalla */
static void msg(const char *s) { gotoxy(1, MSGROW); pstr(EOL); pstr(s); }
static void keyline(void)
{
    gotoxy(1, KEYROW);
    pstr(INV "Tab" NORM " panel " INV "Spc" NORM " mark " INV "Enter" NORM " open " INV "V" NORM "iew "
         INV "E" NORM "dit " INV "C" NORM "opy " INV "M" NORM "ove " INV "R" NORM "en " INV "D" NORM "el "
         INV "L" NORM "drive " INV "U" NORM "ser " INV "?" NORM " " INV "Q" NORM "uit" EOL);
}
static void drawent(uint8_t k, uint16_t i)
{
    panel *p = &pn[k];
    fent *f;
    char t[13];
    uint8_t x = k ? 42 : 1, row = TOP + (i - p->top), j;
    uint16_t kb;
    gotoxy(x, row);
    if (i >= p->n) { for (j = 0; j < 39; j++) putch(' '); return; }
    f = &p->f[i];
    if (k == act && i == p->cur) pstr(INV);
    putch(f->tag ? '*' : ' ');
    for (j = 0; j < 8; j++) putch(f->n[j]);
    putch(' ');
    for (j = 8; j < 11; j++) putch(f->n[j]);
    kb = (f->rec + 7) >> 3;
    pf(" %6uK ", kb);
    (void)t;
    /* lo que no cabe en la columna: espacios */
    for (j = 0; j < 17; j++) putch(' ');
    pstr(NORM);
}
static void drawpanel(uint8_t k)
{
    panel *p = &pn[k];
    uint8_t x = k ? 42 : 1, j;
    uint16_t i;
    gotoxy(x, 2);
    if (k == act) pstr(INV);
    pf(" %c%u:  %u files", 'A' + p->drv, p->usr, p->n);
    pf(", %uK free ", p->freek);
    pstr(NORM);
    pstr(EOL);
    if (k == 0) { gotoxy(41, 2); putch('|'); }
    for (j = 0; j < ROWS; j++) {
        i = p->top + j;
        drawent(k, i);
        gotoxy(41, TOP + j); putch('|');
    }
}
static void info(void)
{
    panel *p = &pn[act];
    fent *f;
    char t[13];
    uint32_t b;
    if (!p->n) { msg("No files here."); return; }
    f = &p->f[p->cur];
    nmtext(t, f->n);
    b = (uint32_t)f->rec * 128;
    gotoxy(1, MSGROW); pstr(EOL);
    pf("%c%u:%s  %lu bytes (%u records)", 'A' + p->drv, p->usr, t, b, f->rec);
    if (p->ntag) pf("   %u marked", p->ntag);
}
static void drawall(void)
{
    pstr(CLS HIDE);
    gotoxy(1, 1);
    pstr(INV " ZFM - file manager                                        (C) OLIVEROS 2026 " NORM);
    drawpanel(0); drawpanel(1);
    keyline();
    info();
}
static void fixtop(panel *p)
{
    if (p->cur < p->top) p->top = p->cur;
    if (p->cur >= p->top + ROWS) p->top = p->cur - ROWS + 1;
}
static void moveto(uint16_t nc)
{
    panel *p = &pn[act];
    uint16_t old = p->cur, ot = p->top;
    if (!p->n) return;
    if ((int16_t)nc < 0) nc = 0;
    if (nc >= p->n) nc = p->n - 1;
    p->cur = nc;
    fixtop(p);
    if (p->top != ot) drawpanel(act);
    else { drawent(act, old); drawent(act, nc); }
    info();
}
static uint8_t input(const char *prompt, const char *init)   /* 0 si ESC */
{
    uint8_t n;
    int k;
    uint8_t first = 1;
    strcpy(line, init);
    n = strlen(line);
    gotoxy(1, MSGROW); pstr(EOL); pstr(prompt); pstr(line); pstr(SHOW);
    for (;;) {
        k = waitkey();
        if (first && k >= ' ' && k < 127) while (n) { n--; pstr("\b \b"); }   /* lo que se escribe reemplaza */
        first = 0;
        if (k == 27) { pstr(HIDE); msg(""); return 0; }
        if (k == 13 || k == 10) break;
        if ((k == 8 || k == 127) && n) { n--; pstr("\b \b"); continue; }
        if (k >= ' ' && k < 127 && n < 40) { line[n++] = k; putch(k); }
    }
    line[n] = 0;
    pstr(HIDE);
    return 1;
}
static uint8_t yes(const char *q)
{
    int k;
    msg(q); pstr(" (Y/N) ");
    k = waitkey() | 32;
    msg("");
    return k == 'y';
}

/* ---------------------------------------------------------------- ver un texto */
#define VBUF 20480
static uint8_t vb[VBUF];
static void view(void)
{
    panel *p = &pn[act];
    FCB f;
    uint16_t len = 0, pos, top = 0, i, l;
    uint8_t k, r, c, row, col, more = 0;
    char t[13];
    if (!p->n) return;
    fcbof(&f, p->drv, p->f[p->cur].n);
    setuser(p->usr);
    if (fopen(&f)) { setuser(startu); msg("Can't open it."); return; }
    while (len + 2048 <= VBUF && (r = freadn(&f, vb + len, 16))) len += (uint16_t)r << 7;
    if (len + 2048 > VBUF && freadn(&f, buf, 1)) more = 1;
    fclose(&f);
    setuser(startu);
    for (i = 0; i < len; i++) if (vb[i] == 26) { len = i; break; }
    nmtext(t, p->f[p->cur].n);
    for (;;) {
        pstr(CLS);
        pos = 0;                            /* la linea top */
        for (l = 0; l < top && pos < len; pos++) if (vb[pos] == '\n') l++;
        for (row = 1; row <= 22; row++) {
            gotoxy(1, row);
            col = 0;
            while (pos < len && vb[pos] != '\n') {
                c = vb[pos++];
                if (c == '\r') continue;
                if (c == 9) { do putch(' '); while (++col & 7 && col < 80); continue; }
                if (col < 80) { putch(c >= ' ' && c < 127 ? c : '.'); col++; }
            }
            if (pos < len) pos++;
            else if (row > 1 || !len) break;
        }
        gotoxy(1, 23);
        pf(INV " %s  line %u%s   arrows, PgUp/PgDn, Home/End; Q or ESC: back " NORM EOL, t, top + 1,
           more ? "  (first 18K only)" : "");
        k = keyin();
        if (k == 'q' || k == 'Q' || k == 27 || k == K_F3 || k == K_F10) break;
        switch (k) {
        case K_UP: if (top) top--; break;
        case K_DOWN: if (pos < len) top++; break;
        case K_PGUP: top = top > 21 ? top - 21 : 0; break;
        case K_PGDN: case ' ': if (pos < len) top += 21; break;
        case K_HOME: top = 0; break;
        case K_END:
            for (l = 0, i = 0; i < len; i++) if (vb[i] == '\n') l++;
            top = l > 20 ? l - 20 : 0;
            break;
        }
    }
    drawall();
}

/* ---------------------------------------------------------------- copiar, mover, borrar */
static uint8_t copy1(panel *s, fent *e, panel *d, const char *dn)   /* 0 bien */
{
    FCB fs, fd;
    uint8_t r, err = 0;
    fcbof(&fs, s->drv, e->n);
    fcbof(&fd, d->drv, dn);
    setuser(s->usr);
    if (fopen(&fs)) { setuser(startu); return 1; }
    setuser(d->usr);
    if (fmake(&fd)) { setuser(s->usr); fclose(&fs); setuser(startu); return 2; }
    for (;;) {
        setuser(s->usr);
        if (!(r = freadn(&fs, buf, 16))) break;
        setuser(d->usr);
        if (fwriten(&fd, buf, r)) { err = 3; break; }
        if (r < 16) break;
        if (brk()) { err = 4; break; }
    }
    setuser(d->usr); fclose(&fd);
    if (err) fdelete(&fd);
    setuser(s->usr); fclose(&fs);
    setuser(startu);
    return err;
}
static void delete1(panel *p, fent *e)
{
    FCB f;
    fcbof(&f, p->drv, e->n);
    setuser(p->usr);
    fdelete(&f);
    setuser(startu);
}
/* los marcados, o el del cursor */
static uint16_t nsel(panel *p) { return p->ntag ? p->ntag : (p->n ? 1 : 0); }
static uint8_t issel(panel *p, uint16_t i) { return p->ntag ? p->f[i].tag : i == p->cur; }
static void copymove(uint8_t mv)
{
    panel *s = &pn[act], *d = &pn[act ^ 1];
    uint16_t i, n = nsel(s), done = 0;
    uint8_t e;
    char t[13];
    if (!n) return;
    if (s->drv == d->drv && s->usr == d->usr) {
        if (mv) { msg("Same drive and user on both sides: use R to rename."); return; }
        msg("Same drive and user on both sides."); return;
    }
    gotoxy(1, MSGROW); pstr(EOL);
    pf("%s %u file%s to %c%u: ?", mv ? "Move" : "Copy", n, n > 1 ? "s" : "", 'A' + d->drv, d->usr);
    if ((waitkey() | 32) != 'y') { msg(""); return; }
    for (i = 0; i < s->n; i++) {
        if (!issel(s, i)) continue;
        nmtext(t, s->f[i].n);
        gotoxy(1, MSGROW); pstr(EOL); pf("%s %s...", mv ? "Moving" : "Copying", t);
        e = copy1(s, &s->f[i], d, s->f[i].n);
        if (e) {
            gotoxy(1, MSGROW); pstr(EOL);
            pf("%s: %s", t, e == 1 ? "can't open it" : e == 2 ? "can't create it (disk full or read only?)" :
               e == 3 ? "disk full" : "stopped");
            waitkey();
            break;
        }
        if (mv) delete1(s, &s->f[i]);
        done++;
    }
    scan(s); scan(d);
    drawall();
    gotoxy(1, MSGROW); pstr(EOL); pf("%u file%s %s.", done, done == 1 ? "" : "s", mv ? "moved" : "copied");
}
static void del(void)
{
    panel *p = &pn[act];
    uint16_t i, n = nsel(p), done = 0;
    char t[13], q[48];
    if (!n) return;
    if (n == 1 && !p->ntag) { nmtext(t, p->f[p->cur].n); strcpy(q, "Delete "); strcat(q, t); strcat(q, "?"); }
    else { strcpy(q, "Delete the marked files?"); }
    if (!yes(q)) return;
    for (i = 0; i < p->n; i++) if (issel(p, i)) { delete1(p, &p->f[i]); done++; }
    scan(p);
    if (pn[0].drv == pn[1].drv && pn[0].usr == pn[1].usr) scan(&pn[act ^ 1]);
    drawall();
    gotoxy(1, MSGROW); pstr(EOL); pf("%u file%s deleted.", done, done == 1 ? "" : "s");
}
static void ren(void)
{
    panel *p = &pn[act];
    FCB f[2];
    char t[13], nn[11];
    if (!p->n) return;
    nmtext(t, p->f[p->cur].n);
    if (!input("New name: ", t)) return;
    if (!parsenm(line, nn)) { msg("That name won't do."); return; }
    fcbof(&f[0], p->drv, p->f[p->cur].n);
    fcbof(&f[1], p->drv, nn);
    setuser(p->usr);
    if ((bdos(17, (uint16_t)&f[1]) & 0xFF) != 0xFF) { setuser(startu); msg("There is already a file with that name."); return; }
    fcbof(&f[1], p->drv, nn);
    memcpy((uint8_t *)&f[0] + 16, (uint8_t *)&f[1], 12);
    bdos(23, (uint16_t)&f[0]);
    setuser(startu);
    scan(p);
    if (pn[0].drv == pn[1].drv && pn[0].usr == pn[1].usr) scan(&pn[act ^ 1]);
    drawall();
}

/* ---------------------------------------------------------------- abrir */
static const char *const assoc[] = {           /* extension, programa */
    "BAS", "ZBAS", "ZC ", "ZCALC", "WKS", "ZCALC", "WK1", "ZCALC", "CSV", "ZCALC",
    "DBF", "ZDATA", "MD ", "ZWRITE", "TXT", "ZWRITE", "DOC", "ZWRITE", "SUB", "SUBMIT", 0 };
/* corre la orden (BDOS 47, Chain To Program); el panel queda como unidad y usuario */
static void chain(const char *cmd)
{
    panel *p = &pn[act];
    pstr(CLS SHOW);
    oflush();
    bdos(14, p->drv);
    setuser(p->usr);
    strcpy((char *)0x80, cmd);
    bdos(47, 0xFF);
    /* si volvio, no se pudo */
    setuser(startu); bdos(14, startd);
    drawall();
    msg("Can't run it (this needs MP/M II or CP/M 3).");
}
static void open_(uint8_t edit)
{
    panel *p = &pn[act];
    fent *f;
    char t[13], cmd[40];
    uint8_t i;
    if (!p->n) return;
    f = &p->f[p->cur];
    nmtext(t, f->n);
    if (edit) { strcpy(cmd, "ZWRITE "); strcat(cmd, t); chain(cmd); return; }
    if (!memcmp(f->n + 8, "COM", 3) || !memcmp(f->n + 8, "PRL", 3)) {
        for (i = 0; i < 8 && f->n[i] != ' '; i++) cmd[i] = f->n[i];
        cmd[i] = 0;
        if (!input("Run: ", cmd)) return;
        chain(line);
        return;
    }
    for (i = 0; assoc[i]; i += 2)
        if (!memcmp(f->n + 8, assoc[i], 3)) {
            strcpy(cmd, assoc[i + 1]); strcat(cmd, " "); strcat(cmd, t);
            chain(cmd);
            return;
        }
    view();
}

/* ---------------------------------------------------------------- lo demas */
static void help(void)
{
    pstr(CLS);
    pstr("ZFM - file manager\n\n"
         "  Up/Down PgUp/PgDn Home/End  move in the list\n"
         "  Tab (or Left/Right)         the other panel\n"
         "  Space or Ins                mark or unmark a file;  *  mark all / none\n"
         "  Enter                       open: .BAS with ZBAS; .ZC .WKS .CSV with ZCALC;\n"
         "                              .DBF with ZDATA; .MD .TXT with ZWRITE; .SUB with\n"
         "                              SUBMIT; .COM .PRL run; anything else is shown\n"
         "  V or F3                     view a text file\n"
         "  E or F4                     edit it with ZWRITE\n"
         "  C or F5                     copy the marked files (or this one) across\n"
         "  M or F6                     move them across\n"
         "  R                           rename this file\n"
         "  D, Del or F8                delete the marked files (or this one)\n"
         "  L / U                       change the drive (A-P) / user (0-15) of the panel\n"
         "  S                           read both directories again\n"
         "  Q, ESC or F10               quit\n\n"
         "  A program started from ZFM runs in the drive and user of the panel;\n"
         "  when it ends you are at the prompt (type ZFM to come back).\n\n"
         "--press a key--");
    waitkey();
    drawall();
}
static void tagall(void)
{
    panel *p = &pn[act];
    uint16_t i;
    uint8_t on = p->ntag != p->n;
    for (i = 0; i < p->n; i++) p->f[i].tag = on;
    p->ntag = on ? p->n : 0;
    drawpanel(act); info();
}
static void tag(void)
{
    panel *p = &pn[act];
    fent *f;
    if (!p->n) return;
    f = &p->f[p->cur];
    f->tag ^= 1;
    if (f->tag) p->ntag++; else p->ntag--;
    moveto(p->cur + 1);
    drawent(act, p->cur ? p->cur - 1 : 0);
}
void main(void)
{
    int k;
    uint8_t n;
    char *a, *w;
    startd = bdos(25, 0) & 0xFF;
    startu = bdos(32, 0xFF) & 0xFF;
    pn[0].drv = pn[1].drv = startd;
    pn[0].usr = pn[1].usr = startu;
    a = args();                             /* ZFM [unidad: [unidad:]] */
    for (n = 0; n < 2 && (w = nextarg(&a)) && *w; n++) {
        k = *w | 32;
        if (k >= 'a' && k <= 'p') pn[n].drv = k - 'a';
        if (w[1] >= '0' && w[1] <= '9') pn[n].usr = (w[1] - '0') * (w[2] >= '0' && w[2] <= '9' ? 10 : 1) + (w[2] >= '0' && w[2] <= '9' ? w[2] - '0' : 0);
    }
    if (n == 1 && pn[1].drv == pn[0].drv) pn[1].drv = startd;
    scan(&pn[0]); scan(&pn[1]);
    bdos(14, startd);
    drawall();
    for (;;) {
        panel *p = &pn[act];
        k = keyin();
        switch (k) {
        case K_UP: moveto(p->cur - 1); break;
        case K_DOWN: moveto(p->cur + 1); break;
        case K_PGUP: moveto(p->cur > ROWS ? p->cur - ROWS : 0); break;
        case K_PGDN: moveto(p->cur + ROWS); break;
        case K_HOME: moveto(0); break;
        case K_END: moveto(p->n ? p->n - 1 : 0); break;
        case 9: case K_LEFT: case K_RIGHT:
            act ^= 1; drawpanel(0); drawpanel(1); info(); break;
        case ' ': case K_F7: tag(); break;
        case '*': tagall(); break;
        case 13: case 10: open_(0); break;
        case 'v': case 'V': case K_F3: view(); break;
        case 'e': case 'E': case K_F4: open_(1); break;
        case 'c': case 'C': case K_F5: copymove(0); break;
        case 'm': case 'M': case K_F6: copymove(1); break;
        case 'r': case 'R': ren(); break;
        case 'd': case 'D': case K_DEL: case K_F8: del(); break;
        case 'l': case 'L':
            if (input("Drive (A-P): ", "")) {
                n = line[0] | 32;
                if (n >= 'a' && n <= 'p') { p->drv = n - 'a'; p->cur = p->top = 0; scan(p); }
                bdos(14, startd);
                drawall();
            }
            break;
        case 'u': case 'U':
            if (input("User (0-15): ", "")) {
                n = line[0] - '0';
                if (line[1] >= '0' && line[1] <= '9') n = n * 10 + line[1] - '0';
                if (n <= 15) { p->usr = n; p->cur = p->top = 0; scan(p); }
                bdos(14, startd);
                drawall();
            }
            break;
        case 's': case 'S': scan(&pn[0]); scan(&pn[1]); bdos(14, startd); drawall(); break;
        case 'i': case 'I': case K_F2: info(); break;
        case '?': case K_F1: help(); break;
        case 'q': case 'Q': case 27: case K_F10:
            setuser(startu); bdos(14, startd);
            pstr(CLS SHOW);
            oflush();
            return;
        }
    }
}
