/* CLOCK - la hora en digitos grandes; cualquier tecla sale */
#include "cpm.h"
static const uint8_t font[11][5] = {
 {7,5,5,5,7},{2,6,2,2,7},{7,1,7,4,7},{7,1,7,1,7},{5,5,7,1,1},
 {7,4,7,1,7},{7,4,7,5,7},{7,1,1,1,1},{7,5,7,5,7},{7,5,7,1,7},{0,2,0,2,0}};
static void big(const char *s, uint8_t y)
{
    uint8_t r, i, b;
    for (r = 0; r < 5; r++) {
        gotoxy(9, y + r);
        for (i = 0; s[i]; i++) {
            const uint8_t *g = font[s[i] == ':' ? 10 : s[i] - '0'];
            for (b = 4; b; b >>= 1) pstr(g[r] & b ? ESC "[7m  " ESC "[27m" : "  ");
            pstr("  ");
        }
    }
}
void main(void)
{
    TOD t; uint8_t last = 0xFF;
    char s[9]; uint16_t y; uint8_t mo, d;
    static const char *const mes[] = {"January","February","March","April","May","June",
        "July","August","September","October","November","December"};
    pstr(HIDE CLS);
    for (;;) {
        gettod(&t);
        if (t.s != last) {
            last = t.s;
            s[0] = '0' + (t.h >> 4); s[1] = '0' + (t.h & 15); s[2] = ':';
            s[3] = '0' + (t.m >> 4); s[4] = '0' + (t.m & 15); s[5] = ':';
            s[6] = '0' + (t.s >> 4); s[7] = '0' + (t.s & 15); s[8] = 0;
            pstr(ESC "[36m"); big(s, 6); pstr(ESC "[0m");
            ymd(t.day, &y, &mo, &d);
            gotoxy(30, 14); pf("%s %u, %u   ", mes[mo - 1], d, y);
            gotoxy(26, 20); pstr("MP/M II ZEPHYRUS - any key to exit");
        }
        if (getkey()) break;
        delay(6);
    }
    pstr(CLS SHOW);
}
