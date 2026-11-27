/* zrun.h - lo comun de AT y CRON (solo ZOS): la fecha en minutos, dormir,
   correr una orden como proceso y anotar en un archivo.
   (C) OLIVEROS 2026 */
static uint8_t zr_t[7];          /* del reloj (D7h): seg min hora dsem dia mes anio, BCD */
static uint8_t zr_db[32];
static uint8_t zr_hz = 125;      /* tics por segundo (de D4h) */
static uint16_t zr_day;          /* dias desde el 1/1/2000 */
static uint8_t zr_h, zr_m, zr_s, zr_d, zr_mo, zr_y, zr_dow;   /* dow 0 = domingo */
static uint16_t zr_cum[12] = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 };

static uint8_t zr_iszos(void)
{
    return *(char *)0xFFDC == 'Z' && *(char *)0xFFDD == 'O' && *(char *)0xFFDE == 'S';
}
static void zr_init(void)
{
    bdos(26, (uint16_t)zr_db);
    bdos(0xD4, 0);                       /* sysinfo: +2 tics por segundo */
    bdos(26, 0x80);
    if (zr_db[2]) zr_hz = zr_db[2];
}
/* la fecha y la hora; 0 bien */
static uint8_t zr_get(void)
{
    uint16_t r;
    bdos(26, (uint16_t)zr_t);
    r = bdos(0xD7, 0);
    bdos(26, 0x80);
    if (r == 0xFFFF) return 1;
    zr_s = bcd(zr_t[0] & 0x7F); zr_m = bcd(zr_t[1]); zr_h = bcd(zr_t[2] & 0x3F);
    zr_d = bcd(zr_t[4]); zr_mo = bcd(zr_t[5]); zr_y = bcd(zr_t[6]);
    if (zr_mo < 1 || zr_mo > 12) zr_mo = 1;
    if (zr_d < 1) zr_d = 1;
    zr_day = 365 * zr_y + (zr_y + 3) / 4 + zr_cum[zr_mo - 1] + zr_d - 1;
    if (!(zr_y & 3) && zr_mo > 2) zr_day++;
    zr_dow = (zr_day + 6) % 7;           /* el 1/1/2000 fue sabado */
    return 0;
}
/* el minuto de ahora, contado desde el 1/1/2000 */
static uint32_t zr_abs(void)
{
    uint32_t a = zr_day;
    return a * 1440 + (uint16_t)(zr_h * 60 + zr_m);
}
/* duerme hasta el minuto que sigue (un poco despues del segundo 0) */
static void zr_nextmin(void)
{
    uint16_t s = 60 - zr_s;
    bdos(0xDC, s * zr_hz + zr_hz / 4);
}
/* "dd/mm hh:mm " a o */
static char *zr_2(char *o, uint8_t v) { *o++ = '0' + v / 10; *o++ = '0' + v % 10; return o; }
static char *zr_stamp(char *o)
{
    o = zr_2(o, zr_d); *o++ = '/'; o = zr_2(o, zr_mo); *o++ = ' ';
    o = zr_2(o, zr_h); *o++ = ':'; o = zr_2(o, zr_m); *o++ = ' ';
    *o = 0;
    return o;
}

/* agrega el texto al final de un archivo de texto (\n -> CR LF); lo crea si no esta */
static uint8_t zr_rec[128];
static void zr_put(FCB *f, uint16_t *n, uint8_t *i, char c)
{
    zr_rec[(*i)++] = c;
    if (*i == 128) { rwrite(f, (*n)++, zr_rec); memset(zr_rec, 0x1A, 128); *i = 0; }
}
static void zr_append(char *name, char *s)
{
    FCB f;
    uint16_t n = 0;
    uint8_t i = 0;
    if (!mkfcb(&f, name)) return;
    memset(zr_rec, 0x1A, 128);
    if (fopen(&f)) {
        if (fmake(&f)) return;
    } else if ((n = fsize(&f)) != 0) {
        n--;
        if (rread(&f, n, zr_rec)) memset(zr_rec, 0x1A, 128);
        for (i = 0; i < 128 && zr_rec[i] != 0x1A; i++) ;
        if (i == 128) { n++; i = 0; memset(zr_rec, 0x1A, 128); }
    }
    for (; *s; s++) {
        if (*s == '\n') zr_put(&f, &n, &i, '\r');
        zr_put(&f, &n, &i, *s);
    }
    if (i) rwrite(&f, n, zr_rec);
    fclose(&f);
}

/* corre la orden (con > >> < al final) en segundo plano y la espera. Sin
   redireccion de salida y con log, la salida va al final de log.
   Devuelve el codigo, o 100h + el error de spawn (3 = no esta) */
static uint8_t zr_spb[200];
static uint16_t zr_run(char *line, char *log)
{
    char *p, *s, *of = 0, *inf = 0, c;
    uint8_t fl = 1, n = 1;
    uint16_t r;
    static char b[160];
    strncpy(b, line, sizeof b - 1); b[sizeof b - 1] = 0;
    for (s = b; *s; s++) {
        if (*s == '>' || *s == '<') {
            c = *s;
            *s++ = 0;
            if (c == '>' && *s == '>') { s++; fl |= 8; }
            while (*s == ' ') s++;
            if (c == '>') { of = s; fl |= 2; } else { inf = s; fl |= 4; }
            while (*s && *s != ' ' && *s != '<' && *s != '>') s++;
            if (*s == ' ') *s++ = 0;
            s--;
        }
    }
    if (!of && log) { of = log; fl |= 2 | 8; }
    for (p = b; *p == ' '; p++) ;
    for (; *p && n < sizeof zr_spb - 40; ) zr_spb[n++] = *p++;
    while (n > 1 && zr_spb[n - 1] == ' ') n--;
    zr_spb[n++] = 0;
    if (of) { for (p = of; *p && n < sizeof zr_spb - 20; ) zr_spb[n++] = *p++; zr_spb[n++] = 0; }
    if (inf) { for (p = inf; *p && n < sizeof zr_spb - 2; ) zr_spb[n++] = *p++; zr_spb[n++] = 0; }
    zr_spb[0] = fl;
    r = bdos(0xD0, (uint16_t)zr_spb);            /* spawn */
    if ((r & 0xFF) == 0xFF) return 0x100 | (r >> 8);
    r = bdos(0xD1, r & 0xFF);                    /* wait */
    return r >> 8;
}
static char *zr_err(uint16_t r)
{
    r &= 0xFF;
    return r == 3 ? "not found" : r == 2 ? "not enough memory" : r == 1 ? "too many processes" : "cannot run it";
}
/* la orden es ECHO (sola o con texto)? */
static uint8_t isecho(char *s)
{
    return (s[0] | 32) == 'e' && (s[1] | 32) == 'c' && (s[2] | 32) == 'h' && (s[3] | 32) == 'o'
        && (s[4] == ' ' || !s[4]);
}
/* "D:NOMBRE" con la unidad actual si no la trae */
static void zr_full(char *o, char *n)
{
    if (n[0] && n[1] == ':') { strcpy(o, n); return; }
    o[0] = 'A' + (bdos(25, 0) & 15); o[1] = ':';
    strcpy(o + 2, n);
}
