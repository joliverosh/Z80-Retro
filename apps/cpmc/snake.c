/* SNAKE - flechas o WASD/IJKL; come los * y no choques. P pausa, Q sale */
#include <string.h>
#include "cpm.h"
#include "keys.h"
#define FW 60
#define FH 20
#define X0 10
#define Y0 2
#define MAXL 600
static uint8_t sx[MAXL], sy[MAXL];
static uint8_t occ[FH][FW];
static uint16_t head, len, grow;
static uint8_t fx, fy;
static void at(uint8_t x, uint8_t y, const char *s) { gotoxy(X0 + 1 + x, Y0 + 1 + y); pstr(s); }
static void food(void)
{
    do { fx = rnd() % FW; fy = rnd() % FH; } while (occ[fy][fx]);
    at(fx, fy, ESC "[1;31m*" ESC "[0m");
}
void main(void)
{
    static const int8_t dx[5] = {0, 0, 0, 1, -1}, dy[5] = {0, -1, 1, 0, 0};
    uint8_t d = K_RIGHT, nd, x, y, spd = 8, quit = 0;
    uint16_t last, score = 0, tail;
    srnd(ticks() | 1);
    pstr(CLS HIDE);
    gotoxy(X0 + 25, 1); pstr(ESC "[1mS N A K E" ESC "[0m");
    gotoxy(X0, Y0); putch('+'); for (x = 0; x < FW; x++) putch('-'); putch('+');
    for (y = 1; y <= FH; y++) { gotoxy(X0, Y0 + y); putch('|'); gotoxy(X0 + FW + 1, Y0 + y); putch('|'); }
    gotoxy(X0, Y0 + FH + 1); putch('+'); for (x = 0; x < FW; x++) putch('-'); putch('+');
    for (len = 0; len < 4; len++) {
        sx[len] = 10 + len; sy[len] = 10; occ[10][10 + len] = 1;
        at(sx[len], 10, ESC "[32mo" ESC "[0m");
    }
    head = 3; tail = 0; grow = 0;
    food();
    last = ticks();
    for (;;) {
        int k = key();
        if (k >= K_UP && k <= K_LEFT) {
            nd = k;
            if (!((nd == K_UP && d == K_DOWN) || (nd == K_DOWN && d == K_UP) ||
                  (nd == K_LEFT && d == K_RIGHT) || (nd == K_RIGHT && d == K_LEFT))) d = nd;
        } else if ((k | 32) == 'p') {
            gotoxy(X0 + 26, Y0 + FH + 1); pstr(ESC "[7m PAUSED " ESC "[0m");
            waitkey();
            gotoxy(X0 + 26, Y0 + FH + 1); pstr("---------");
        } else if ((k | 32) == 'q' || k == 3) { quit = 1; break; }
        if ((uint16_t)(ticks() - last) < spd) { delay(1); continue; }
        last = ticks();
        x = sx[head] + dx[d & 7]; y = sy[head] + dy[d & 7];
        if (x >= FW || y >= FH) break;               /* (uint8_t: -1 = 255) */
        if (grow) grow--;
        else {                                       /* la cola avanza */
            occ[sy[tail]][sx[tail]] = 0;
            at(sx[tail], sy[tail], " ");
            tail = tail + 1 == MAXL ? 0 : tail + 1;
            len--;
        }
        if (occ[y][x]) break;
        at(sx[head], sy[head], ESC "[32mo" ESC "[0m");
        head = head + 1 == MAXL ? 0 : head + 1;
        sx[head] = x; sy[head] = y; occ[y][x] = 1; len++;
        at(x, y, ESC "[1;32m@" ESC "[0m");
        if (x == fx && y == fy) {
            score += 10; grow += 3;
            if (spd > 2 && !(score % 50)) spd--;
            if (len + grow >= MAXL - 4) break;
            food();
        }
        gotoxy(X0, 1); pf("Score %u  ", score);
        gotoxy(1, 23);
    }
    gotoxy(X0 + 25, Y0 + FH / 2); pstr(quit ? ESC "[7m   QUIT    " ESC "[0m" : ESC "[7m GAME OVER " ESC "[0m");
    gotoxy(X0 + 25, Y0 + FH / 2 + 1); pf(ESC "[7m Score %4u  " ESC "[0m", score);
    gotoxy(1, 23); pstr(SHOW);
}
