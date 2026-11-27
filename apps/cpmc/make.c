/* MAKE - rehace lo que cambio, segun las reglas de MAKEFILE
   MAKE [-F arch] [-N] [-K] [-A] [-U objetivo] [objetivo...]

   CP/M no guarda la fecha de los archivos, asi que MAKE lleva la cuenta el
   mismo: en MAKE.DAT guarda el CRC de cada dependencia la ultima vez que el
   objetivo salio bien. Un objetivo se rehace si no existe, si una dependencia
   cambio (otro CRC) o si se acaba de rehacer una dependencia.

   El archivo de reglas:
       # comentario
       CF = -N -O                      variable; se usa con $(CF)
       HOLA.COM: HOLA.C CPM.LIB        objetivo: dependencias
               C $(CF) HOLA.C CPM.LIB  ordenes (empiezan con espacio o TAB)
   En las ordenes: $@ el objetivo, $< la 1ra dependencia, $^ todas, $* el
   objetivo sin la extension. Ordenes propias: ERA arch, REN nuevo=viejo y
   ECHO texto; lo demas son programas. > arch, >> arch y < arch como en el shell.

   En ZOS cada orden corre como un proceso y MAKE espera su codigo. Antes de
   rehacer un objetivo lo borra; si una orden falla o al final no esta el
   objetivo, para (-K: sigue con lo que no depende de el).
   En CP/M 2.2 escribe las ordenes en A:$$$.SUB y sale: las corre el CCP, y
   despues de las de cada objetivo va un MAKE -U que anota los CRC.
   -N: solo muestra lo que haria. -A: rehace todo.
   (C) OLIVEROS 2026 */
#include <string.h>
#include "cpm.h"

#define MAXR 64                  /* reglas */
#define MAXD 12                  /* dependencias por regla */
#define MAXV 24                  /* variables */
#define MAXS 160                 /* lineas de MAKE.DAT */
#define NML 15                   /* "A:NOMBRE.EXT" y el 0 */

typedef struct {
    char t[NML];                 /* objetivo */
    uint8_t nd, done, busy, made;
    uint8_t d[MAXD];             /* dependencias: indices en dn[] */
    uint16_t cmd;                /* desplazamiento de la 1ra orden en txt[] */
    uint8_t ncmd;
} rule;
static rule rl[MAXR];
static uint8_t nr;
static char dn[MAXR * 4][NML];   /* nombres de las dependencias */
static uint16_t ndn;
static char vname[MAXV][9];
static char *vval[MAXV];
static uint8_t nv;
static char txt[6144];           /* el archivo de reglas, lineas terminadas en 0 */
static uint16_t ntxt;
typedef struct { char t[NML], d[NML]; uint16_t crc; } stamp;
static stamp st[MAXS];
static uint8_t nst, stdirty;
static uint8_t dryrun, keep, all, zos, nerr;
static char mkname[NML] = "MAKEFILE";
static uint8_t rb[1024];
static char line[256], word[NML];
static FCB sf;                   /* $$$.SUB en CP/M 2.2 */
static uint8_t subn, subrec[60][128];

static void upname(char *d, const char *s)
{
    uint8_t i;
    for (i = 0; i < NML - 1 && s[i] && s[i] != ' ' && s[i] != '\t'; i++)
        d[i] = s[i] >= 'a' && s[i] <= 'z' ? s[i] - 32 : s[i];
    d[i] = 0;
}

/* ------------------------------------------------------------ archivos */
/* CRC-16 (CCITT) de un archivo entero; *ok = 0 si no esta */
static uint16_t fcrc(const char *name, uint8_t *ok)
{
    FCB f; uint16_t c = 0xFFFF, i; uint8_t g, b, k;
    *ok = 0;
    if (!mkfcb(&f, name) || fopen(&f)) return 0;
    *ok = 1;
    while ((g = freadn(&f, rb, 8))) {
        for (i = 0; i < (uint16_t)g << 7; i++) {
            b = rb[i];
            c ^= (uint16_t)b << 8;
            for (k = 0; k < 8; k++) c = c & 0x8000 ? (c << 1) ^ 0x1021 : c << 1;
        }
    }
    fclose(&f);
    return c;
}
static uint8_t exists(const char *name)
{
    FCB f;
    if (!mkfcb(&f, name)) return 0;
    return !fopen(&f);
}
/* lee un archivo de texto entero a d (max n bytes); devuelve cuantos o -1 */
static int loadtext(const char *name, char *d, uint16_t n)
{
    FCB f; uint16_t k = 0; uint8_t g; uint16_t i;
    if (!mkfcb(&f, name) || fopen(&f)) return -1;
    while ((g = freadn(&f, rb, 8))) {
        for (i = 0; i < (uint16_t)g << 7; i++) {
            if (rb[i] == 0x1A) { fclose(&f); return k; }
            if (k >= n) { fclose(&f); return -2; }
            d[k++] = rb[i];
        }
    }
    fclose(&f);
    return k;
}

/* ------------------------------------------------------------ MAKE.DAT */
static uint8_t hexv(char c) { return c <= '9' ? c - '0' : (c | 32) - 'a' + 10; }
static void stload(void)
{
    static char b[MAXS * 34];
    int n = loadtext("MAKE.DAT", b, sizeof b - 1);
    char *p, *q;
    uint8_t i;
    if (n < 0) return;
    b[n] = 0;
    for (p = b; *p && nst < MAXS; p = q) {
        for (q = p; *q && *q != '\n'; q++) ;
        if (*q) *q++ = 0;
        if (*p == '\r' || !*p) continue;
        upname(st[nst].t, p);
        while (*p && *p != ' ') p++;
        while (*p == ' ') p++;
        upname(st[nst].d, p);
        while (*p && *p != ' ') p++;
        while (*p == ' ') p++;
        st[nst].crc = 0;
        for (i = 0; i < 4 && *p > ' '; i++, p++) st[nst].crc = (st[nst].crc << 4) | hexv(*p);
        if (st[nst].t[0] && st[nst].d[0]) nst++;
    }
}
static uint8_t wbuf[128], wn;
static FCB wf;
static void wputc(char c)
{
    wbuf[wn++] = c;
    if (wn == 128) { fwrite(&wf, wbuf); wn = 0; }
}
static void wputs(const char *s) { while (*s) wputc(*s++); }
static void stsave(void)
{
    uint8_t i, k;
    char h[6];
    static const char hx[] = "0123456789ABCDEF";
    if (!stdirty || dryrun) return;
    if (!mkfcb(&wf, "MAKE.DAT") || fmake(&wf)) { pstr("MAKE: cannot write MAKE.DAT\n"); return; }
    wn = 0;
    for (i = 0; i < nst; i++) {
        wputs(st[i].t); wputc(' '); wputs(st[i].d); wputc(' ');
        for (k = 0; k < 4; k++) h[k] = hx[(st[i].crc >> (12 - 4 * k)) & 15];
        h[4] = 0; wputs(h); wputs("\r\n");
    }
    wputc(0x1A);
    while (wn) wputc(0x1A);
    fclose(&wf);
}
static int stfind(const char *t, const char *d)
{
    uint8_t i;
    for (i = 0; i < nst; i++) if (!strcmp(st[i].t, t) && !strcmp(st[i].d, d)) return i;
    return -1;
}
static void stset(const char *t, const char *d, uint16_t crc)
{
    int i = stfind(t, d);
    if (i < 0) {
        if (nst >= MAXS) return;
        i = nst++;
        strcpy(st[i].t, t); strcpy(st[i].d, d);
    }
    st[i].crc = crc;
    stdirty = 1;
}

/* ------------------------------------------------------------ las reglas */
static char *getvar(const char *n)
{
    uint8_t i;
    for (i = 0; i < nv; i++) if (!strcmp(vname[i], n)) return vval[i];
    return "";
}
static int findrule(const char *t)
{
    uint8_t i;
    for (i = 0; i < nr; i++) if (!strcmp(rl[i].t, t)) return i;
    return -1;
}
static uint8_t isdrv(const char *w, const char *c) { return c == w + 1; }  /* "A:" */
/* expande $(VAR), $@, $<, $^ y $* de s en line (r: la regla, o 0) */
static void expand(const char *s, rule *r)
{
    uint16_t n = 0; uint8_t k;
    char vn[9], *v;
    while (*s && n < sizeof line - 1) {
        if (*s != '$') { line[n++] = *s++; continue; }
        s++;
        v = "";
        if (*s == '(') {
            s++;
            for (k = 0; *s && *s != ')' && k < 8; s++) vn[k++] = *s >= 'a' && *s <= 'z' ? *s - 32 : *s;
            vn[k] = 0;
            if (*s == ')') s++;
            v = getvar(vn);
        } else if (*s == '$') { s++; v = "$"; }
        else if (r && *s == '@') { s++; v = r->t; }
        else if (r && *s == '<') { s++; v = r->nd ? dn[r->d[0]] : ""; }
        else if (r && *s == '*') {
            s++;
            for (k = 0; r->t[k] && r->t[k] != '.' && n < sizeof line - 1; k++) line[n++] = r->t[k];
            continue;
        } else if (r && *s == '^') {
            s++;
            for (k = 0; k < r->nd; k++) {
                if (k && n < sizeof line - 1) line[n++] = ' ';
                for (v = dn[r->d[k]]; *v && n < sizeof line - 1; v++) line[n++] = *v;
            }
            continue;
        }
        while (*v && n < sizeof line - 1) line[n++] = *v++;
    }
    line[n] = 0;
}
static uint8_t parse(void)
{
    char *p = txt, *e = txt + ntxt, *q, *c, *eq;
    uint16_t ln = 0;
    rule *cur = 0;
    uint8_t k;
    while (p < e) {
        for (q = p; q < e && *q != '\n'; q++) ;
        if (q > p && q[-1] == '\r') q[-1] = 0;
        *q = 0;
        ln++;
        if (*p == ' ' || *p == '\t') {               /* una orden */
            while (*p == ' ' || *p == '\t') p++;
            if (*p && *p != '#') {
                if (!cur) { pf("MAKE: line %u: a command without a rule\n", ln); return 1; }
                if (!cur->ncmd) cur->cmd = p - txt;
                cur->ncmd++;
                /* las ordenes de una regla quedan seguidas: marcar las otras */
            } else *p = 0;
        } else if (*p && *p != '#') {
            /* variable: NOMBRE = valor (el = antes que cualquier :) */
            eq = strchr(p, '=');
            for (c = p; *c && *c != ':'; c++) ;
            while (*c == ':' && c > p && isdrv(p, c)) { for (c++; *c && *c != ':'; c++) ; }
            if (eq && (!*c || eq < c)) {
                *eq = 0;
                for (c = eq - 1; c >= p && (*c == ' ' || *c == '\t'); c--) *c = 0;
                if (nv < MAXV) {
                    for (k = 0; p[k] && k < 8; k++) vname[nv][k] = p[k] >= 'a' && p[k] <= 'z' ? p[k] - 32 : p[k];
                    vname[nv][k] = 0;
                    for (eq++; *eq == ' ' || *eq == '\t'; eq++) ;
                    vval[nv++] = eq;
                }
                cur = 0;
            } else {
                /* regla: el ':' que no es de una unidad */
                char *w = p;
                for (c = p; *c; c++) {
                    if (*c == ' ' || *c == '\t') w = c + 1;
                    if (*c == ':' && c != w + 1) break;
                }
                if (!*c) { pf("MAKE: line %u: no ':'\n", ln); return 1; }
                *c = 0;
                if (nr >= MAXR) { pstr("MAKE: too many rules\n"); return 1; }
                cur = &rl[nr++];
                expand(p, 0);
                upname(cur->t, line[0] == ' ' ? line + 1 : line);
                expand(c + 1, 0);
                for (c = line; *c; ) {
                    while (*c == ' ' || *c == '\t') c++;
                    if (!*c) break;
                    if (cur->nd >= MAXD || ndn >= sizeof dn / NML) { pstr("MAKE: too many dependencies\n"); return 1; }
                    upname(dn[ndn], c);
                    cur->d[cur->nd++] = ndn++;
                    while (*c && *c != ' ' && *c != '\t') c++;
                }
            }
        } else if (*p == '#') *p = 0;
        p = q + 1;
    }
    return 0;
}
/* la orden k de la regla r (las vacias y los comentarios no cuentan) */
static char *cmdline(rule *r, uint8_t k)
{
    char *p = txt + r->cmd;
    for (;;) {
        while (*p == ' ' || *p == '\t') p++;
        if (*p && *p != '#') { if (!k) return p; k--; }
        while (*p) p++;
        p++;
        while (*p == ' ' || *p == '\t') p++;
    }
}

/* ------------------------------------------------------------ correr */
static uint8_t spb[300];
static uint8_t era(char *a)
{
    FCB f;
    if (!a || !mkfcb(&f, a)) { pstr("ERA: no name\n"); return 1; }
    fdelete(&f);
    return 0;
}
static uint8_t ren(char *a)
{
    FCB f; char *eq = a ? strchr(a, '=') : 0;
    uint8_t r[16];
    if (!eq) { pstr("REN: use REN new=old\n"); return 1; }
    *eq = 0;
    if (!mkfcb(&f, eq + 1)) return 1;
    memcpy(r, &f, 16);
    if (!mkfcb(&f, a)) return 1;
    memcpy((uint8_t *)&f + 16, &f, 16);
    memcpy(&f, r, 16);
    return (bdos(23, (uint16_t)&f) & 0xFF) == 0xFF;
}
/* corre una orden (ya expandida en line); 0 bien */
static uint8_t run(void)
{
    char *p = line, *a, *w;
    char *ofile = 0, *ifile = 0;
    uint8_t fl = 0;
    uint16_t r, n = 0;
    pf("  %s\n", line);
    if (dryrun) return 0;
    while (*p == ' ') p++;
    w = p;
    for (a = p; *a && *a != ' '; a++) ;
    if (*a) *a++ = 0;
    while (*a == ' ') a++;
    upname(word, w);
    if (!strcmp(word, "ECHO")) { pf("%s\n", a); return 0; }
    if (!strcmp(word, "ERA") || !strcmp(word, "DEL")) return era(nextarg(&a));
    if (!strcmp(word, "REN")) return ren(nextarg(&a));
    /* > >> < del final */
    {
        char *s;
        for (s = a; *s; s++) {
            if (*s == '>' || *s == '<') {
                char c = *s;
                *s++ = 0;
                if (c == '>' && *s == '>') { s++; fl |= 8; }
                while (*s == ' ') s++;
                if (c == '>') { ofile = s; fl |= 2; } else { ifile = s; fl |= 4; }
                while (*s && *s != ' ' && *s != '<' && *s != '>') s++;
                if (*s == ' ') *s++ = 0;
                s--;
            }
        }
    }
    spb[n++] = fl;
    for (p = w; *p && n < sizeof spb - 30; ) spb[n++] = *p++;
    if (*a) { spb[n++] = ' '; for (p = a; *p && n < sizeof spb - 30; ) spb[n++] = *p++; }
    while (n > 1 && spb[n - 1] == ' ') n--;
    spb[n++] = 0;
    if (ofile) { for (p = ofile; *p && n < sizeof spb - 15; ) spb[n++] = *p++; spb[n++] = 0; }
    if (ifile) { for (p = ifile; *p && n < sizeof spb - 2; ) spb[n++] = *p++; spb[n++] = 0; }
    r = bdos(0xD0, (uint16_t)spb);               /* spawn */
    if ((r & 0xFF) == 0xFF) {
        pf("MAKE: %s: %s\n", w, (r >> 8) == 3 ? "not found" : (r >> 8) == 2 ? "no memory" : "cannot run it");
        return 1;
    }
    r = bdos(0xD1, r & 0xFF);                    /* wait */
    return r >> 8;
}
/* CP/M 2.2: una linea mas para $$$.SUB (van al reves: la ultima primero) */
static void subadd(const char *s)
{
    uint8_t n = strlen(s), i;
    if (subn >= sizeof subrec / 128) { pstr("MAKE: too many commands for $$$.SUB\n"); nerr++; return; }
    if (n > 125) n = 125;
    subrec[subn][0] = n;
    for (i = 0; i < n; i++) subrec[subn][1 + i] = s[i] >= 'a' && s[i] <= 'z' ? s[i] - 32 : s[i];
    subrec[subn][1 + n] = 0;
    subn++;
}
static void subwrite(void)
{
    uint8_t i;
    if (!subn || dryrun) return;
    if (!mkfcb(&sf, "A:$$$.SUB") || fmake(&sf)) { pstr("MAKE: cannot write A:$$$.SUB\n"); return; }
    for (i = subn; i; i--) fwrite(&sf, subrec[i - 1]);
    fclose(&sf);
}

/* ------------------------------------------------------------ hacer */
static uint8_t make(const char *t, uint8_t depth);
static void record(rule *r)
{
    uint8_t k, ok; uint16_t c;
    for (k = 0; k < r->nd; k++) {
        c = fcrc(dn[r->d[k]], &ok);
        if (ok) stset(r->t, dn[r->d[k]], c);
    }
    if (!r->nd) stset(r->t, "-", 0);
}
/* 0 bien, 1 error; deja r->made si se rehizo */
static uint8_t make(const char *t, uint8_t depth)
{
    int i = findrule(t);
    rule *r;
    uint8_t k, ok, out = 0, e = 0, phony;
    uint16_t c;
    int s;
    if (i < 0) {
        if (exists(t)) return 0;
        pf("MAKE: don't know how to make %s\n", t);
        return 1;
    }
    r = &rl[i];
    if (r->done) return r->done == 2;
    if (r->busy) { pf("MAKE: %s depends on itself\n", t); return 1; }
    r->busy = 1;
    for (k = 0; k < r->nd; k++) {
        if (make(dn[r->d[k]], depth + 1)) { e = 1; if (!keep) break; }
        else {
            s = findrule(dn[r->d[k]]);
            if (s >= 0 && rl[s].made) out = 1;
        }
    }
    r->busy = 0;
    if (e) { r->done = 2; return 1; }
    phony = !strchr(r->t, '.');          /* sin extension: no es un archivo (TODO) */
    if (all || phony || !exists(r->t)) out = 1;
    for (k = 0; k < r->nd && !out; k++) {
        c = fcrc(dn[r->d[k]], &ok);
        s = stfind(r->t, dn[r->d[k]]);
        if (!ok || s < 0 || st[s].crc != c) out = 1;
    }
    if (out && r->ncmd) {
        pf("%s:\n", r->t);
        /* el viejo se borra antes: los compiladores no siempre dicen que
           fallaron, y asi se sabe si las ordenes lo hicieron */
        if (zos && !dryrun && !phony) { FCB f; if (mkfcb(&f, r->t)) fdelete(&f); }
        for (k = 0; k < r->ncmd; k++) {
            expand(cmdline(r, k), r);
            if (!zos) { subadd(line); continue; }
            if (run()) { pf("MAKE: %s: the command failed\n", r->t); r->done = 2; nerr++; return 1; }
        }
        if (!zos) {
            strcpy(line, "MAKE -U "); strcat(line, r->t);
            if (strcmp(mkname, "MAKEFILE")) { strcat(line, " -F "); strcat(line, mkname); }
            subadd(line);
        } else if (!dryrun && !phony) {
            if (!exists(r->t)) { pf("MAKE: the commands did not make %s\n", r->t); r->done = 2; nerr++; return 1; }
            record(r);
        }
        r->made = 1;
    } else if (out && !r->ncmd && !dryrun && zos && !phony) record(r);
    r->done = 1;
    return 0;
}

void main(void)
{
    char *p = args(), *a;
    char *targ[8], *upd = 0;
    static char tb[NML];
    uint8_t nt = 0, i, e = 0;
    int n;
    zos = *(char *)0xFFDC == 'Z' && *(char *)0xFFDD == 'O' && *(char *)0xFFDE == 'S';
    while ((a = nextarg(&p))) {
        if (a[0] == '-') {
            switch (a[1] | 32) {
            case 'f': if ((a = nextarg(&p))) upname(mkname, a); break;
            case 'n': dryrun = 1; break;
            case 'k': keep = 1; break;
            case 'a': all = 1; break;
            case 'u': upd = nextarg(&p); break;
            default: pstr("Usage: MAKE [-F file] [-N] [-K] [-A] [target...]\n"); return;
            }
        } else if (nt < 8) targ[nt++] = a;
    }
    if (!zos && (bdos(12, 0) & 0xFFF0) != 0x20) { pstr("MAKE: runs on ZOS or CP/M 2.2\n"); return; }
    n = loadtext(mkname, txt, sizeof txt - 1);
    if (n < 0) { pf(n == -1 ? "MAKE: no %s\n" : "MAKE: %s is too big\n", mkname); return; }
    ntxt = n; txt[ntxt] = 0;
    if (parse()) return;
    if (!nr) { pstr("MAKE: no rules\n"); return; }
    stload();
    if (upd) {                                   /* MAKE -U: anota los CRC */
        upname(word, upd);
        n = findrule(word);
        if (n >= 0) { record(&rl[n]); stsave(); }
        return;
    }
    if (!nt) { targ[0] = rl[0].t; nt = 1; }
    /* (los nombres de los objetivos se copian: line se usa al expandir) */
    for (i = 0; i < nt; i++) {
        upname(tb, targ[i]);
        if (make(tb, 0)) { e = 1; if (!keep) break; }
    }
    stsave();
    if (!zos) {
        subwrite();
        if (subn && !dryrun) exit(0);            /* el CCP corre $$$.SUB */
    }
    if (!e && !nerr) {
        for (i = 0; i < nr && !rl[i].made; i++) ;
        if (i == nr && !dryrun) pstr("MAKE: everything is up to date\n");
    }
}
