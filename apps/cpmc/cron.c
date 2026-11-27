/* CRON - corre ordenes a sus horas, segun un archivo (solo ZOS)
   CRON [archivo] [-L log]      archivo CRONTAB y log CRON.LOG por omision
   Revisa el archivo y se queda en segundo plano (PS lo muestra, KILL lo para).
   Lo vuelve a leer cada minuto, asi que se puede cambiar sin pararlo.
   Cada linea:  minuto hora dia mes dia_de_la_semana orden...
     cada campo: *, n, n-m o una lista a,b,c; /k despues de * o de n-m salta
     de k en k (semana: 0-6, 0 y 7 domingo)
     si dia y semana no son *, basta con que case uno (como el cron de Unix)
   @reboot orden...   una vez, al arrancar CRON
   # comentario
   La salida de cada orden va al final del log, con una linea con la fecha y
   la orden antes; las ordenes son programas (.COM), una tras otra.
   ECHO texto escribe el texto en el log.
   (Por dentro: CRON -W archivo log.) (C) OLIVEROS 2026 */
#include <string.h>
#include "cpm.h"
#include "zrun.h"

static char tab[2048];
static char tname[20], lname[20];
static uint16_t lineno;
static uint8_t nerr;

/* carga el archivo a tab; 0 bien */
static uint8_t load(void)
{
    FCB f;
    uint16_t k = 0, i;
    uint8_t g;
    static uint8_t rb[1024];
    tab[0] = 0;
    if (!mkfcb(&f, tname) || fopen(&f)) return 1;
    while ((g = freadn(&f, rb, 8)) != 0) {
        for (i = 0; i < (uint16_t)g << 7; i++) {
            if (rb[i] == 0x1A || k >= sizeof tab - 1) goto fin;
            tab[k++] = rb[i];
        }
    }
fin:
    fclose(&f);
    tab[k] = 0;
    return 0;
}
static char *num(char *p, uint8_t *v)
{
    uint16_t x = 0;
    if (*p < '0' || *p > '9') return 0;
    while (*p >= '0' && *p <= '9') { x = x * 10 + (*p++ - '0'); if (x > 255) return 0; }
    *v = (uint8_t)x;
    return p;
}
/* el campo s (terminado en 0) casa con v? 0 no, 1 si, 2 esta mal */
static uint8_t field(char *s, uint8_t v, uint8_t lo, uint8_t hi)
{
    uint8_t a, b, st, any = 0, w;
    for (;;) {
        st = 1;
        if (*s == '*') { a = lo; b = hi; s++; }
        else {
            if (!(s = num(s, &a))) return 2;
            b = a;
            if (*s == '-' && !(s = num(s + 1, &b))) return 2;
        }
        if (*s == '/' && (!(s = num(s + 1, &st)) || !st)) return 2;
        if (a < lo || b > hi || a > b) return 2;
        for (w = a; w <= b; w += st) {
            if (w == v || (hi == 7 && w == 7 && v == 0)) any = 1;
            if (w + st > 255) break;
        }
        if (!*s) return any;
        if (*s++ != ',') return 2;
    }
}
/* toma la palabra que sigue de p (la deja terminada en 0) */
static char *word(char **p)
{
    char *s = *p, *w;
    while (*s == ' ' || *s == '\t') s++;
    if (!*s) return 0;
    w = s;
    while (*s && *s != ' ' && *s != '\t') s++;
    if (*s) *s++ = 0;
    while (*s == ' ' || *s == '\t') s++;
    *p = s;
    return w;
}
static void bad(char *why)
{
    pf("%s line %u: %s\n", tname, lineno, why);
    nerr++;
}
static void runit(char *cmd)
{
    static char m[200];
    char *q;
    uint16_t r;
    q = zr_stamp(m);
    if (!strncmp(cmd, "ECHO ", 5) || !strncmp(cmd, "echo ", 5)) {
        strncat(m, cmd + 5, 150); strcat(m, "\n");
        zr_append(lname, m);
        return;
    }
    strcpy(q, "CRON: "); strncat(m, cmd, 150); strcat(m, "\n");
    zr_append(lname, m);
    r = zr_run(cmd, lname);
    if (r & 0x100) {
        q = zr_stamp(m);
        strcpy(q, "CRON: "); strncat(m, cmd, 120); strcat(m, ": "); strcat(m, zr_err(r)); strcat(m, "\n");
        zr_append(lname, m);
    }
}
/* recorre tab: chk = 1 solo revisa; boot = 1 las @reboot; si no, las que tocan ahora */
static void scan(uint8_t chk, uint8_t boot)
{
    char *p = tab, *e, *f[5], *cmd;
    static char ln[200];
    uint8_t i, k, r[5], ok;
    uint16_t n;
    lineno = 0;
    while (*p) {
        for (e = p; *e && *e != '\n'; e++) ;
        n = e - p;
        if (n > sizeof ln - 1) n = sizeof ln - 1;
        memcpy(ln, p, n); ln[n] = 0;
        p = *e ? e + 1 : e;
        lineno++;
        for (k = 0; ln[k]; k++) if (ln[k] == '\r' || ln[k] == 0x1A) ln[k] = 0;
        cmd = ln;
        while (*cmd == ' ' || *cmd == '\t') cmd++;
        if (!*cmd || *cmd == '#') continue;
        if (!strncmp(cmd, "@reboot", 7) || !strncmp(cmd, "@REBOOT", 7)) {
            cmd += 7;
            while (*cmd == ' ' || *cmd == '\t') cmd++;
            if (!*cmd) { if (chk) bad("no command"); continue; }
            if (boot && !chk) runit(cmd);
            continue;
        }
        for (i = 0; i < 5; i++) if (!(f[i] = word(&cmd))) break;
        if (i < 5 || !*cmd) { if (chk) bad("needs 5 fields and a command"); continue; }
        r[0] = field(f[0], zr_m, 0, 59);
        r[1] = field(f[1], zr_h, 0, 23);
        r[2] = field(f[2], zr_d, 1, 31);
        r[3] = field(f[3], zr_mo, 1, 12);
        r[4] = field(f[4], zr_dow, 0, 7);
        for (i = 0; i < 5 && r[i] != 2; i++) ;
        if (i < 5) { if (chk) bad("bad field"); continue; }
        if (chk || boot) continue;
        ok = r[0] && r[1] && r[3];
        if (f[2][0] != '*' && f[4][0] != '*') ok = ok && (r[2] || r[4]);
        else ok = ok && r[2] && r[4];
        if (ok) runit(cmd);
    }
}
static void runner(char *p)
{
    char *a = nextarg(&p), *b = nextarg(&p);
    uint32_t last, now;
    static char m[60];
    if (!a || !b) return;
    strcpy(tname, a); strcpy(lname, b);
    zr_get();
    strcpy(zr_stamp(m), "CRON: started\n");
    zr_append(lname, m);
    if (!load()) scan(0, 1);
    zr_get();
    last = zr_abs();
    for (;;) {
        zr_nextmin();
        if (zr_get()) continue;
        now = zr_abs();
        if (now == last) continue;
        last = now;
        if (load()) continue;                /* (el archivo no esta: espera) */
        scan(0, 0);
    }
}
void main(void)
{
    char *p = args(), *a;
    uint16_t r;
    static char cmd[80];
    if (!zr_iszos()) { pstr("CRON: runs on ZOS\n"); return; }
    zr_init();
    while (*p == ' ') p++;
    if (!strncmp(p, "-W ", 3) || !strncmp(p, "-w ", 3)) { runner(p + 3); return; }
    zr_full(tname, "CRONTAB");
    zr_full(lname, "CRON.LOG");
    while ((a = nextarg(&p)) != 0) {
        if (a[0] == '-' && (a[1] | 32) == 'l' && !a[2]) {
            if (!(a = nextarg(&p))) break;
            zr_full(lname, a);
        } else if (a[0] == '-') {
            pstr("Usage: CRON [file] [-L log]   (CRONTAB and CRON.LOG)\n");
            return;
        } else zr_full(tname, a);
    }
    if (strlen(tname) > 14 || strlen(lname) > 14) { pstr("CRON: name too long\n"); return; }
    if (load()) { pf("CRON: no %s\n", tname); return; }
    zr_get();
    scan(1, 0);
    if (nerr) return;
    strcpy(cmd, "CRON -W "); strcat(cmd, tname); strcat(cmd, " "); strcat(cmd, lname);
    zr_spb[0] = 1;
    strcpy((char *)zr_spb + 1, cmd);
    r = bdos(0xD0, (uint16_t)zr_spb);
    if ((r & 0xFF) == 0xFF) { pf("CRON: %s\n", zr_err(r >> 8)); return; }
    pf("CRON: running as job %u, log %s (KILL %u stops it)\n", r & 0xFF, lname, r & 0xFF);
}
