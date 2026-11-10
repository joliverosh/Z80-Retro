/* TALK n mensaje - escribe un mensaje en la pantalla de otra consola (1-5) */
#include "cpm.h"
static void out(uint8_t c, char ch) { zios(45, 0, ((uint16_t)c << 8) | (uint8_t)ch, 0); }
static void outs(uint8_t c, const char *s) { while (*s) out(c, *s++); }
void main(void)
{
    char *a = args(), *n = nextarg(&a);
    uint8_t to, me = mycons(), i;
    char buf[4];
    if (!n || n[0] < '1' || n[0] > '5' || n[1] || !*a) {
        pstr("Usage: TALK n message   (n = console 1-5)\n");
        return;
    }
    to = n[0] - '1';
    outs(to, "\r\n" ESC "[7m TALK from console ");
    buf[0] = '1' + me; buf[1] = 0; outs(to, buf);
    outs(to, ": " ESC "[0m ");
    for (i = 0; a[i]; i++) out(to, a[i]);
    outs(to, "\r\n");
    pf("Sent to console %u.\n", to + 1);
}
