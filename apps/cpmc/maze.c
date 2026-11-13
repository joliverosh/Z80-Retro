/* MAZE - laberintos en ASCII, como el AMAZING de los libros de BASIC de los 70.
   MAZE                 uno del tamano de la pantalla (26 x 11), para mirar o recorrer
   MAZE w h             w x h casillas (hasta 80 x 60; los grandes, mejor a un archivo)
   MAZE w h ARCHIVO     lo escribe en un archivo de texto (con /S, con la solucion)
   Cada laberinto es perfecto: entre dos casillas hay un solo camino. Se hace con el
   backtracker de siempre (avanzar al azar a una casilla sin visitar; si no hay,
   volver), con una pila propia; el camino de la entrada a la salida es lo que hay en
   la pila cuando se llega a la salida. Mensajes en ingles. (C) OLIVEROS 2026 */
#include <string.h>
#include "cpm.h"

#define MAXW 80
#define MAXH 60
#define E 1                          /* pasa al este */
#define S 2                          /* pasa al sur */
#define V 4                          /* visitada */
#define P 8                          /* en el camino de la solucion */
enum { K_UP = 0x81, K_DOWN, K_RIGHT, K_LEFT };

static uint8_t c[MAXW * MAXH];
static uint16_t st[MAXW * MAXH];
static uint8_t w = 26, h = 11;
static uint16_t plen;                /* casillas del camino */

static void make(void)
{
    uint16_t sp = 0, i, n, nb[4], last = (uint16_t)w * h - 1;
    uint8_t x, y, k;
    memset(c, 0, sizeof c);
    st[sp++] = 0;
    c[0] = V;
    while (sp) {
        i = st[sp - 1];
        x = i % w; y = i / w;
        k = 0;                       /* vecinas sin visitar */
        if (x > 0 && !(c[i - 1] & V)) nb[k++] = i - 1;
        if (x < w - 1 && !(c[i + 1] & V)) nb[k++] = i + 1;
        if (y > 0 && !(c[i - w] & V)) nb[k++] = i - w;
        if (y < h - 1 && !(c[i + w] & V)) nb[k++] = i + w;
        if (!k) { sp--; continue; }
        n = nb[rnd() % k];
        if (n == i + 1) c[i] |= E;
        else if (n == i - 1) c[n] |= E;
        else if (n == i + w) c[i] |= S;
        else c[n] |= S;
        c[n] |= V;
        st[sp++] = n;
        if (n == last) {             /* la salida: la pila es el camino */
            for (plen = 0; plen < sp; plen++) c[st[plen]] |= P;
        }
    }
}

/* ---------------------------------------------------------------- escribir */
static FCB fo;
static uint8_t ob[128], on, tofile, showp;
static void outc(char ch)
{
    if (!tofile) { putch(ch); return; }
    ob[on++] = ch;
    if (on == 128) { fwrite(&fo, ob); on = 0; }
}
static void outs(const char *s) { while (*s) outc(*s++); }
static void nl(void) { if (tofile) outs("\r\n"); else pstr("\n"); }
static void draw(void)
{
    uint8_t x, y;
    uint16_t i;
    outc('+');                       /* arriba, con la entrada en la primera */
    for (x = 0; x < w; x++) outs(x == 0 ? "  +" : "--+");
    nl();
    for (y = 0; y < h; y++) {
        outc('|');
        for (x = 0; x < w; x++) {
            i = (uint16_t)y * w + x;
            outs(showp && (c[i] & P) ? "**" : "  ");
            outc(!(c[i] & E) ? '|' : showp && x < w - 1 && (c[i] & P) && (c[i + 1] & P) ? '*' : ' ');
        }
        nl();
        outc('+');
        for (x = 0; x < w; x++) {
            i = (uint16_t)y * w + x;
            if (y == h - 1) outs(x == w - 1 ? "  +" : "--+");   /* la salida en la ultima */
            else outs(!(c[i] & S) ? "--+" : showp && (c[i] & P) && (c[i + w] & P) ? "**+" : "  +");
        }
        nl();
    }
}

/* ---------------------------------------------------------------- jugar */
static int keyin(void)
{
    int k = waitkey(), n;
    if (k != 27) return k;
    for (n = 0; n < 300 && !(k = getkey()); n++) ;
    if (k != '[' && k != 'O') return 27;
    for (n = 0; n < 300 && !(k = getkey()); n++) ;
    switch (k) { case 'A': return K_UP; case 'B': return K_DOWN; case 'C': return K_RIGHT; case 'D': return K_LEFT; }
    return 0;
}
static void at(uint8_t x, uint8_t y, const char *s) { gotoxy(2 + 3 * x, 2 + 2 * y); pstr(s); }
static void status(const char *s) { gotoxy(1, 2 * h + 2); pstr(s); pstr(ESC "[K"); }
static void play(void)
{
    uint8_t x = 0, y = 0, nx, ny;
    uint16_t i, moves = 0;
    int k;
    status("Arrows or h j k l: from the top left to the bottom right. Q: give up");
    for (;;) {
        at(x, y, ESC "[7m@" ESC "[0m");
        gotoxy(2 + 3 * x, 2 + 2 * y);
        if (x == w - 1 && y == h - 1) {
            gotoxy(1, 2 * h + 2);
            pf("Out in %u moves (the shortest way is %u). Press a key." ESC "[K", moves, plen - 1);
            waitkey();
            return;
        }
        k = keyin();
        if (k == 'q' || k == 'Q' || k == 27) return;
        nx = x; ny = y; i = (uint16_t)y * w + x;
        if ((k == K_UP || k == 'k' || k == 'w') && y > 0 && (c[i - w] & S)) ny--;
        else if ((k == K_DOWN || k == 'j' || k == 's') && y < h - 1 && (c[i] & S)) ny++;
        else if ((k == K_LEFT || k == 'h' || k == 'a') && x > 0 && (c[i - 1] & E)) nx--;
        else if ((k == K_RIGHT || k == 'l' || k == 'd') && x < w - 1 && (c[i] & E)) nx++;
        else continue;
        at(x, y, ".");               /* el rastro */
        x = nx; y = ny; moves++;
    }
}

static uint8_t num(char *s, uint8_t max)
{
    uint16_t v = 0;
    if (!s || *s < '0' || *s > '9') return 0;
    while (*s >= '0' && *s <= '9') { v = v * 10 + *s++ - '0'; if (v > max) return 0; }
    return *s ? 0 : v;
}
void main(void)
{
    char *a = args(), *wd, *file = 0;
    uint8_t n = 0, v;
    int k;
    srnd(ticks() ^ (uint16_t)mycons() << 8);
    while ((wd = nextarg(&a)) && *wd) {
        if (wd[0] == '/') { if ((wd[1] | 32) == 's') showp = 1; continue; }
        if (n < 2 && (v = num(wd, n ? MAXH : MAXW))) { if (n++) h = v; else w = v; continue; }
        if (wd[0] >= '0' && wd[0] <= '9') { pstr("Usage: MAZE [w h] [file] [/S]   (w up to 80, h up to 60)\n"); return; }
        file = wd;
    }
    if (w < 2) w = 2;
    if (h < 2) h = 2;
    if (n == 1) h = w * 11 / 26 < 2 ? 2 : w * 11 / 26 > MAXH ? MAXH : w * 11 / 26;
    make();
    if (file) {
        if (!mkfcb(&fo, file) || fmake(&fo)) { pstr("Can't create that file.\n"); return; }
        tofile = 1;
        draw();
        outc(26);
        while (on) outc(26);         /* (llena el ultimo registro) */
        fclose(&fo);
        pf("A %u x %u maze%s written.\n", w, h, showp ? ", with its way out," : "");
        return;
    }
    if (w > 26 || h > 11) {          /* no cabe: se escribe y listo */
        draw();
        return;
    }
    for (;;) {
        pstr(CLS);
        draw();
        status("N: new maze  S: show the way out  P: play  Q: quit");
        k = waitkey();
        if (k >= 'A' && k <= 'Z') k += 32;
        if (k == 'n') { make(); showp = 0; }
        else if (k == 's') showp ^= 1;
        else if (k == 'p') { showp = 0; pstr(CLS); draw(); play(); }
        else if (k == 'q' || k == 27 || k == 3) break;
    }
    gotoxy(1, 2 * h + 2);
    pstr(ESC "[K");
}
