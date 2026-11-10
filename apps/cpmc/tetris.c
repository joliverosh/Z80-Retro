/* TETRIS - flechas o WASD/IJKL: mover y girar (arriba), abajo baja,
   ESPACIO la deja caer, P pausa, Q sale */
#include <string.h>
#include "cpm.h"
#include "keys.h"
#define BW 10
#define BH 20
#define X0 30                     /* columna del borde izquierdo */
#define Y0 2
static const uint16_t shape[7][4] = {
    {0x0F00, 0x2222, 0x00F0, 0x4444}, {0x44C0, 0x8E00, 0x6440, 0x0E20},
    {0x4460, 0x0E80, 0xC440, 0x2E00}, {0xCC00, 0xCC00, 0xCC00, 0xCC00},
    {0x06C0, 0x8C40, 0x6C00, 0x4620}, {0x0E40, 0x4C40, 0x4E00, 0x4640},
    {0x0C60, 0x4C80, 0xC600, 0x2640}};
static const uint8_t color[8] = {0, 46, 44, 47, 43, 42, 45, 41};
static uint8_t bd[BH][BW], shown[BH][BW];
static uint8_t pc, rot, nxt, lev;
static int8_t px, py;
static uint16_t lines;
static uint32_t score;

static uint8_t fits(uint8_t p, uint8_t r, int8_t x, int8_t y)
{
    uint16_t m = shape[p][r], bit = 0x8000;
    uint8_t i, j;
    for (i = 0; i < 4; i++)
        for (j = 0; j < 4; j++, bit >>= 1)
            if (m & bit) {
                int8_t cx = x + j, cy = y + i;
                if (cx < 0 || cx >= BW || cy >= BH) return 0;
                if (cy >= 0 && bd[cy][cx]) return 0;
            }
    return 1;
}
static void cell(uint8_t x, uint8_t y, uint8_t c)
{
    gotoxy(X0 + 1 + x * 2, Y0 + y);
    if (c) pf(ESC "[%um  " ESC "[0m", color[c]);
    else pstr(" .");
}
static void place(uint8_t put)          /* pone (1) o quita (0) la pieza en bd */
{
    uint16_t m = shape[pc][rot], bit = 0x8000;
    uint8_t i, j;
    for (i = 0; i < 4; i++)
        for (j = 0; j < 4; j++, bit >>= 1)
            if ((m & bit) && py + i >= 0) bd[py + i][px + j] = put ? pc + 1 : 0;
}
static void draw(void)
{
    uint8_t x, y;
    place(1);
    for (y = 0; y < BH; y++)
        for (x = 0; x < BW; x++)
            if (bd[y][x] != shown[y][x]) { shown[y][x] = bd[y][x]; cell(x, y, bd[y][x]); }
    place(0);
    gotoxy(1, 23);
}
static void info(void)
{
    uint16_t m = shape[nxt][0], bit = 0x8000;
    uint8_t i, j;
    gotoxy(X0 + 26, Y0 + 1); pf("Score %lu", score);
    gotoxy(X0 + 26, Y0 + 3); pf("Lines %u", lines);
    gotoxy(X0 + 26, Y0 + 5); pf("Level %u", lev);
    gotoxy(X0 + 26, Y0 + 8); pstr("Next");
    for (i = 0; i < 4; i++) {
        gotoxy(X0 + 26, Y0 + 10 + i);
        for (j = 0; j < 4; j++, bit >>= 1)
            if (m & bit) pf(ESC "[%um  " ESC "[0m", color[nxt + 1]); else pstr("  ");
    }
}
static uint8_t newpiece(void)
{
    pc = nxt; nxt = rnd() % 7; rot = 0; px = 3; py = -1;
    info();
    return fits(pc, rot, px, py);
}
static void land(void)
{
    uint8_t y, n = 0;
    static const uint16_t pts[5] = {0, 40, 100, 300, 1200};
    place(1);
    for (y = 0; y < BH; y++) {
        uint8_t x, full = 1;
        for (x = 0; x < BW; x++) if (!bd[y][x]) full = 0;
        if (full) {
            memmove(bd[1], bd[0], y * BW);
            memset(bd[0], 0, BW);
            n++;
        }
    }
    lines += n;
    score += (uint32_t)pts[n] * (lev + 1);
    lev = lines / 10;
}
void main(void)
{
    uint8_t y, over = 0;
    uint16_t last;
    srnd(ticks() | 1);
    nxt = rnd() % 7;
    pstr(CLS HIDE);
    gotoxy(X0 + 4, 1); pstr(ESC "[1mT E T R I S" ESC "[0m");
    for (y = 0; y < BH; y++) {
        gotoxy(X0, Y0 + y); pstr("|"); gotoxy(X0 + 1 + BW * 2, Y0 + y); pstr("|");
    }
    gotoxy(X0, Y0 + BH); pstr("+--------------------+");
    gotoxy(X0 + 26, Y0 + 16); pstr("Arrows/WASD move");
    gotoxy(X0 + 26, Y0 + 17); pstr("Up rotates, Space drops");
    gotoxy(X0 + 26, Y0 + 18); pstr("P pause, Q quit");
    memset(shown, 0xFF, sizeof shown);
    newpiece();
    draw();
    last = ticks();
    while (!over) {
        int k = key();
        uint8_t moved = 1, spd = lev < 9 ? 48 - lev * 5 : 4;
        if (k == K_LEFT && fits(pc, rot, px - 1, py)) px--;
        else if (k == K_RIGHT && fits(pc, rot, px + 1, py)) px++;
        else if (k == K_UP) {
            uint8_t r = (rot + 1) & 3;
            if (fits(pc, r, px, py)) rot = r;
            else if (fits(pc, r, px - 1, py)) { rot = r; px--; }
            else if (fits(pc, r, px + 1, py)) { rot = r; px++; }
        } else if (k == K_DOWN) {
            if (fits(pc, rot, px, py + 1)) { py++; score++; } else last -= spd;
        } else if (k == ' ') {
            while (fits(pc, rot, px, py + 1)) { py++; score += 2; }
            last -= spd;
        } else if ((k | 32) == 'p') {
            gotoxy(X0 + 6, Y0 + 9); pstr(ESC "[7m PAUSED " ESC "[0m");
            waitkey();
            memset(shown, 0xFF, sizeof shown);
        } else if ((k | 32) == 'q' || k == 3) { over = 2; break; }
        else moved = 0;
        if ((uint16_t)(ticks() - last) >= spd) {
            last = ticks();
            if (fits(pc, rot, px, py + 1)) py++;
            else { land(); if (!newpiece()) over = 1; }
            moved = 1;
        }
        if (moved) draw(); else delay(1);
    }
    gotoxy(X0 + 5, Y0 + 9); pstr(over == 2 ? ESC "[7m   QUIT    " ESC "[0m" : ESC "[7m GAME OVER " ESC "[0m");
    gotoxy(1, 23); pstr(SHOW);
}
