/* LIFE - el juego de la vida de Conway (78 x 22, el borde da la vuelta); cualquier tecla sale */
#include <string.h>
#include "cpm.h"
#define W 78
#define H 22
static uint8_t a[H][W], b[H][W];
void main(void)
{
    uint16_t gen = 0;
    uint8_t x, y;
    srnd(ticks() | 1);
    for (y = 0; y < H; y++) for (x = 0; x < W; x++) a[y][x] = (rnd() & 7) < 2;
    pstr(CLS HIDE ESC "[32m");
    for (;;) {
        pstr(HOME);
        for (y = 0; y < H; y++) {
            for (x = 0; x < W; x++) putch(a[y][x] ? 'O' : ' ');
            pstr("\r\n");
        }
        pf(ESC "[0mGeneration %u   (any key: exit)" ESC "[32m", gen++);
        for (y = 0; y < H; y++) {
            uint8_t ym = y ? y - 1 : H - 1, yp = y < H - 1 ? y + 1 : 0;
            for (x = 0; x < W; x++) {
                uint8_t xm = x ? x - 1 : W - 1, xp = x < W - 1 ? x + 1 : 0;
                uint8_t n = a[ym][xm] + a[ym][x] + a[ym][xp] + a[y][xm] + a[y][xp]
                          + a[yp][xm] + a[yp][x] + a[yp][xp];
                b[y][x] = n == 3 || (n == 2 && a[y][x]);
            }
        }
        memcpy(a, b, sizeof a);
        if (getkey()) break;
    }
    pstr(ESC "[0m" SHOW "\n");
}
