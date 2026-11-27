/* AT - corre una orden a una hora (solo ZOS)
   AT hh:mm orden...     hoy, o manana si esa hora ya paso
   AT +n orden...        dentro de n minutos (+nH: n horas)
   AT queda esperando en segundo plano: PS lo muestra y KILL lo cancela.
   La salida de la orden va al final de AT.LOG (en la unidad de ahora),
   salvo que la orden traiga su > o >>. ECHO texto sale en la consola.
   La orden es un programa (.COM), no una orden del shell como DIR.
   (Por dentro: AT -W minuto log orden; el minuto desde el 1/1/2000.)
   (C) OLIVEROS 2026 */
#include <string.h>
#include "cpm.h"
#include "zrun.h"

static char *num(char *p, uint16_t *v)
{
    *v = 0;
    if (*p < '0' || *p > '9') return 0;
    while (*p >= '0' && *p <= '9') *v = *v * 10 + (*p++ - '0');
    return p;
}
static void usage(void)
{
    pstr("Usage: AT hh:mm command    or    AT +n[H] command   (n minutes or hours)\n");
}
/* el minuto (desde 2000) como texto decimal */
static char *u32s(char *o, uint32_t v)
{
    char t[12];
    uint8_t k = 0;
    do { t[k++] = '0' + (uint8_t)(v % 10); v /= 10; } while (v);
    while (k) *o++ = t[--k];
    *o = 0;
    return o;
}
static void runner(char *p)
{
    char *w = nextarg(&p), *log = nextarg(&p), *q;
    uint32_t tg = 0, now;
    static char m[200];
    if (!w || !log) return;
    for (q = w; *q >= '0' && *q <= '9'; q++) tg = tg * 10 + (uint16_t)(*q - '0');
    while (*p == ' ') p++;
    for (;;) {
        if (zr_get()) { bdos(0xDC, 60 * zr_hz); continue; }
        now = zr_abs();
        if (now >= tg) break;
        zr_nextmin();
    }
    if (isecho(p)) {
        pf("\r\nAT: %s\r\n", p[4] ? p + 5 : "");
        return;
    }
    q = zr_stamp(m);
    strcpy(q, "AT: "); strncat(m, p, 150); strcat(m, "\n");
    zr_append(log, m);
    now = zr_run(p, log);
    if (now & 0x100) {
        q = zr_stamp(m);
        strcpy(q, "AT: "); strncat(m, p, 120); strcat(m, ": "); strcat(m, zr_err(now)); strcat(m, "\n");
        zr_append(log, m);
        pf("\r\n%s", m);
    }
}
void main(void)
{
    char *p = args(), *a, *q;
    uint16_t h, mi = 0, r;
    uint32_t now, tg;
    static char cmd[200], log[20];
    if (!zr_iszos()) { pstr("AT: runs on ZOS\n"); return; }
    zr_init();
    while (*p == ' ') p++;
    if (!strncmp(p, "-W ", 3) || !strncmp(p, "-w ", 3)) { runner(p + 3); return; }
    a = nextarg(&p);
    while (*p == ' ') p++;
    if (!a || !*p) { usage(); return; }
    if (zr_get()) { pstr("AT: no clock\n"); return; }
    now = zr_abs();
    if (a[0] == '+') {
        q = num(a + 1, &h);
        if (!q || (*q && (*q | 32) != 'h') || !h) { usage(); return; }
        tg = now + ((*q | 32) == 'h' ? (uint32_t)h * 60 : h);
    } else {
        q = num(a, &h);
        if (!q || *q != ':' || !(q = num(q + 1, &mi)) || *q || h > 23 || mi > 59) { usage(); return; }
        tg = now - (uint16_t)(zr_h * 60 + zr_m) + (uint16_t)(h * 60 + mi);
        if (tg <= now) tg += 1440;
    }
    zr_full(log, "AT.LOG");
    q = cmd;
    strcpy(q, "AT -W "); q = u32s(q + 6, tg);
    *q++ = ' '; strcpy(q, log); strcat(q, " "); strncat(cmd, p, 150);
    cmd[sizeof cmd - 1] = 0;
    /* en segundo plano y sin esperarlo */
    zr_spb[0] = 1;
    strcpy((char *)zr_spb + 1, cmd);
    r = bdos(0xD0, (uint16_t)zr_spb);
    if ((r & 0xFF) == 0xFF) { pf("AT: %s\n", zr_err(r >> 8)); return; }
    /* la hora en que va a correr, y cuanto falta */
    mi = (uint16_t)(tg % 1440);
    h = (uint16_t)(tg - now);
    pf("AT: job %u at %u%u:%u%u, in %u:%u%u (KILL %u cancels it)\n", r & 0xFF,
       mi / 600, mi / 60 % 10, mi % 60 / 10, mi % 10, h / 60, h % 60 / 10, h % 10, r & 0xFF);
}
