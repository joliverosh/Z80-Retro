/* BENCH - mide la CPU, la aritmetica, la consola y el disco
   BENCH [d:]   (el disco: escribe y lee un archivo de 64 KB, BENCH.$$$, y lo borra) */
#include <string.h>
#include "cpm.h"
static uint8_t flags[8191];
static uint8_t buf[1024];
static FCB f;
static uint16_t t0;
static uint8_t tk;

/* n vueltas de 3356 ciclos (B=0: DJNZ 256 veces = 3323, mas 33 de la vuelta) */
static void spin(uint16_t n) __sdcccall(0) __naked
{
    (void)n;
    __asm
        pop     hl
        pop     de
        push    de
        push    hl
    00001$:
        ld      b,#0
    00002$:
        djnz    00002$
        dec     de
        ld      a,d
        or      e
        jr      nz,00001$
        ret
    __endasm;
}
static void start(void) { uint16_t t = ticks(); while ((t0 = ticks()) == t) ; }
static uint16_t stop(void) { return ticks() - t0; }        /* tics */
/* x / tics * tps con un decimal; v en decimas */
static void dec1(uint32_t v) { pf("%lu.%lu", v / 10, v % 10); }
static uint32_t rate(uint32_t units, uint16_t t) { return t ? units * 10 * tk / t : 0; }

static uint16_t sieve(void)
{
    uint16_t i, k, prime, count = 0;
    memset(flags, 1, sizeof flags);
    for (i = 0; i < 8191; i++)
        if (flags[i]) {
            prime = i + i + 3;
            for (k = i + prime; k < 8191; k += prime) flags[k] = 0;
            count++;
        }
    return count;
}
void main(void)
{
    char *p = args(), *a = nextarg(&p);
    uint16_t t, i, n;
    uint32_t s32;
    tk = tps();
    pf("BENCH - Z80 speed test (%u ticks per second)\n", tk);
    pf("  TPA top: %04Xh (%u KB free)\n\n", *(uint16_t *)6, (*(uint16_t *)6 - 0x100) >> 10);

    pstr("  CPU clock (estimate)    ");
    start(); spin(1000); t = stop();
    /* MHz = 3356000 * tk / t / 1e6; en centesimas */
    { uint32_t c = 3356UL * tk / t / 10; pf("%lu.%02lu MHz\n", c / 100, c % 100); }

    pstr("  Sieve 8190 x 10         ");
    start(); for (i = 0; i < 10; i++) n = sieve(); t = stop();
    dec1(rate(10, t) * 10 / 10); pf(" /s  (%u primes, ", n); dec1((uint32_t)t * 10 / tk); pstr(" s)\n");

    pstr("  32-bit adds and shifts  ");
    s32 = 1;
    start(); for (i = 0; i < 20000; i++) { s32 += s32 << 3; s32 ^= s32 >> 7; } t = stop();
    dec1(rate(20000, t) / 1000); pf(" K loops/s  (%08lX)\n", s32);

    pstr("  16-bit multiply/divide  ");
    n = 0;
    start(); for (i = 1; i < 20000; i++) n += (i * 7) / (i & 15 | 1); t = stop();
    dec1(rate(20000, t) / 1000); pstr(" K ops/s\n");

    pstr("  Console output          ");
    start();
    for (i = 0; i < 100; i++) { pstr("\r"); for (n = 0; n < 50; n++) putch('*'); }
    t = stop();
    pstr("\r" ESC "[K  Console output          ");
    dec1(rate(5100, t)); pstr(" chars/s\n");

    if (!a) a = (char *)"BENCH.$$$";
    else {
        static char nm[16];
        nm[0] = a[0]; nm[1] = ':'; strcpy(nm + 2, "BENCH.$$$");
        a = nm;
    }
    mkfcb(&f, a);
    pf("  Disk write 64 KB (%c:)   ", f.dr ? '@' + f.dr : '@' + (bdos(25, 0) & 15) + 1);
    if (fmake(&f)) { pstr("cannot create the file\n"); return; }
    for (i = 0; i < 128; i++) buf[i] = i;
    start();
    for (i = 0; i < 512; i++) if (fwrite(&f, buf)) { pstr("disk full\n"); fclose(&f); fdelete(&f); return; }
    fclose(&f);
    t = stop();
    dec1(rate(64, t)); pstr(" KB/s\n");
    pstr("  Disk read 64 KB         ");
    fopen(&f);
    start();
    for (i = 0; i < 512; i++) if (fread(&f, buf)) break;
    t = stop();
    fclose(&f);
    dec1(rate(64, t)); pstr(" KB/s\n");
    pstr("  Disk read, 1 KB per call ");
    fopen(&f);
    start();
    for (i = 0; i < 64; i++) if (freadn(&f, buf, 8) < 8) break;
    t = stop();
    fclose(&f);
    fdelete(&f);
    dec1(rate(64, t)); pstr(" KB/s\n");
    pstr("  Disk write, 1 KB per call ");
    if (fmake(&f)) { pstr("cannot create the file\n"); return; }
    start();
    for (i = 0; i < 64; i++) if (fwriten(&f, buf, 8)) { pstr("disk full\n"); fclose(&f); fdelete(&f); return; }
    fclose(&f);
    t = stop();
    fdelete(&f);
    dec1(rate(64, t)); pstr(" KB/s\n");
}
