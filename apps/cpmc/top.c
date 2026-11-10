/* TOP - los procesos de MP/M en vivo: estado, consola, banco, prioridad y la CPU */
#include "cpm.h"
static const char *const st[] = {"ready","queue rd","queue wr","polling","flag wait","delayed",
    "swapping","ending","set prio","RUNNING","attaching","detaching","set cons","att LST","det LST"};
void main(void)
{
    uint16_t dp = datapg();
    pstr(HIDE CLS);
    for (;;) {
        TOD t; uint16_t y; uint8_t mo, d, n = 0;
        uint8_t idle = zios(44, 0, 0, 0);    /* FF: un XIOS sin el servicio 44 */
        gettod(&t); ymd(t.day, &y, &mo, &d);
        pstr(HOME);
        if (idle > 60) pstr("TOP - MP/M II ZEPHYRUS   CPU  n/a");
        else pf("TOP - MP/M II ZEPHYRUS   CPU %3u%%", 100 - (uint16_t)idle * 100 / 60);
        pf("   %u-%02u-%02u %02x:%02x:%02x   (any key: exit)" ESC "[K\n\n",
           y, mo, d, t.h, t.m, t.s);
        pf("Process   Cons  Mseg  Prio  State" ESC "[K\n");
        uint16_t run = *(uint16_t *)(dp + 5);
        uint16_t pd = *(uint16_t *)(dp + 17);
        while (pd && n < 18) {
            uint8_t *p = (uint8_t *)pd, i;
            char nm[9];
            for (i = 0; i < 8; i++) nm[i] = p[6 + i] & 0x7F;
            nm[8] = 0;
            uint8_t s = p[2], seg = p[15];
            pf("%s  %3u   ", nm, (p[14] & 15) + 1);
            if (seg == 0xFF) pstr("sys"); else pf("%3u", seg);
            pf("   %3u   %s" ESC "[K\n", p[3], pd == run ? "RUNNING" : (s < 15 ? st[s] : "?"));
            pd = *(uint16_t *)(p + 18);
            n++;
        }
        pstr(ESC "[J");
        for (n = 0; n < 60; n++) { if (getkey()) { pstr(SHOW "\n"); return; } delay(1); }
    }
}
