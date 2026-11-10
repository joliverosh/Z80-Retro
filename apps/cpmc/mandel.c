/* MANDEL - el conjunto de Mandelbrot en caracteres y colores ANSI (punto fijo 4.12) */
#include "cpm.h"
#define F 12
#define MAXI 32
/* (int32_t)a * b con int16_t falla en SDCC 4.2 para algunos valores (-2048 * -2048
   da -264241152): se multiplica sin signo y se corrige */
static const char ch[] = " .,:;=+*%#@";
static const uint8_t col[] = {34,34,36,36,32,32,33,33,31,35,37};
void main(void)
{
    int16_t x, y, cx, cy;
    uint16_t t0 = ticks(), t;
    uint8_t lastc = 0;
    pstr(CLS HIDE);
    for (y = 0; y < 23; y++) {
        cy = -4505 + (int16_t)y * 409 + ((int16_t)y * 13) / 22;   /* sin mult. de 32 bits (SDCC) */           /* -1,1 .. 1,1 */
        for (x = 0; x < 79; x++) {
            int16_t zx = 0, zy = 0; int32_t x2 = 0, y2 = 0;
            uint8_t i;
            cx = -8602 + (int16_t)x * 136 + (int16_t)x / 2;       /* -2,1 .. 0,5 */
            for (i = 0; i < MAXI; i++) {
                zy = (int16_t)(mul16(zx, zy) >> (F - 1)) + cy;
                zx = (int16_t)(x2 - y2) + cx;
                x2 = mul16(zx, zx) >> F;
                y2 = mul16(zy, zy) >> F;
                if (x2 + y2 > (4L << F)) break;
            }
            uint8_t k = i == MAXI ? 0 : 1 + (i * 9) / MAXI;
            if (k) {
                if (col[k] != lastc) { lastc = col[k]; pf(ESC "[%um", lastc); }
                putch(ch[k]);
            } else putch(' ');
            if (getkey()) { pstr(ESC "[0m" SHOW "\n"); return; }
        }
        pstr("\r\n");
    }
    t = ticks() - t0;
    pf(ESC "[0m" SHOW "%u.%u s", t / tps(), (t % tps()) * 10 / tps());
}
