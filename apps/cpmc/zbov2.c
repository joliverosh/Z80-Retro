/* zbov2.c - parte de ZBAS.OVL: LIST, EDIT y SAVE (las lineas compiladas como texto)
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include "zbas.h"

extern const char kwp[];
const char *kw(uint8_t k);
/* el texto de una linea compilada (sin el numero) en o; devuelve el largo */
char *lo;
void lput(char c) { *lo++ = c; }
void lputs(const char *s) { while (*s) *lo++ = *s++; }
uint16_t decompile(const uint8_t *t, char *o)
{
    static uint8_t c, prev, i, *p;
    static uint16_t v;
    lo = o; prev = 0;
    while ((c = *t++) != T_END) {
        /* un espacio entre palabras y nombres */
        if (prev && (c >= 0x80 || c == T_ID || c == T_NUM || c == T_LNUM || c == T_STR) &&
            (prev >= 0x80 || prev == T_ID || prev == T_NUM || prev == T_LNUM || prev == T_STR || prev == ':' || prev == ',' || prev == ';'))
            lput(' ');
        else if (prev >= 0x80 && prev != K_LE && prev != K_GE && prev != K_NE && c != '(' && c != ':' && c != ',' && c != ';') lput(' ');
        else if (c >= 0x80 && c != K_LE && c != K_GE && c != K_NE && prev && prev != '(') lput(' ');
        switch (c) {
        case T_NUM: {
            num n;
            memcpy(&n, t, 5); t += 5;
            if (!(i = nplain(lo, &n, -1, 22))) i = nsci(lo, &n, 22);
            lo += i;
            break;
        }
        case T_STR:
            lput('"');
            for (i = *t++; i; i--) lput(*t++);
            lput('"');
            break;
        case T_ID:
            v = t[0] | t[1] << 8; t += 2;
            p = symat(v);
            for (i = 0; i < p[1]; i++) lput(p[2 + i]);
            break;
        case T_LNUM:
            v = t[0] | t[1] << 8; t += 2;
            lo += utoa_(v, lo);
            break;
        case T_RAW:
            if (prev == K_REM || !prev) { if (!prev) lput('\''); else lput(' '); }
            while (*t) lput(*t++);
            break;
        default:
            if (c >= 0x80) lputs(kw(c - 0x80));
            else { lput(c); if (c == ':' || c == ',') { } }
        }
        prev = c;
        if (c == T_RAW) break;
    }
    *lo = 0;
    return lo - o;
}

uint8_t depthof(uint8_t *t, uint8_t *after)   /* sangria de LIST: cuanto baja antes y sube despues */
{
    uint8_t k = *t;
    *after = 0;
    if (k == T_ID && t[3] == ':') { t += 4; k = *t; }
    if (k == K_END && (t[1] == K_IF || t[1] == K_SELECT || t[1] == K_SUB || t[1] == K_FUNCTION)) return 1;
    if (k == K_NEXT || k == K_WEND || k == K_LOOP) return 1;
    if (k == K_ELSE || k == K_ELSEIF || k == K_CASE) { *after = 1; return 1; }
    if ((k == K_IF && blockif(t)) || k == K_WHILE || k == K_DO || k == K_SUB || k == K_FUNCTION) *after = 1;
    if (k == K_SELECT) *after = 2;
    if (k == K_FOR) { uint8_t *p = t; for (; *p != T_END; p += tsize(p)) if (*p == K_NEXT) break; if (*p != K_NEXT) *after = 1; }
    if (k == K_END && t[1] == K_SELECT) return 2;
    return 0;
}
uint8_t usesnums(void)    /* el programa usa numeros de linea? */
{
    uint8_t *l, *p;
    for (l = prog; l < pend; l += LLEN(l))
        for (p = LTOK(l); *p != T_END; p += tsize(p)) if (*p == T_LNUM) return 1;
    return 0;
}
/* una linea como texto (con su numero si nums) en lb */
uint16_t ltext(uint8_t *l, uint8_t nums, uint8_t ind)
{
    char *o = lb;
    uint8_t i;
    if (nums) { o += utoa_(LNUM(l), o); *o++ = ' '; }
    for (i = 0; i < ind && i < 40; i++) *o++ = ' ';
    o += decompile(LTOK(l), o);
    return o - lb;
}
void list(uint16_t a, uint16_t b, uint8_t nums)
{
    uint8_t *l, d = 0, dn, af;
    for (l = prog; l < pend; l += LLEN(l)) {
        dn = depthof(LTOK(l), &af);
        d = d > dn ? d - dn : 0;
        if (LNUM(l) >= a && LNUM(l) <= b) {
            ltext(l, nums, d * 2);
            cons(lb); cons("\n");
            if (brkchk()) break;
        }
        d += af;
    }
}
FCB lf;
uint8_t savefile(const char *nm)
{
    uint8_t *l, nums = usesnums(), d = 0, dn, af, ob[128], op = 0, err = 0;
    uint16_t n, i, rec = 0;
    if (!mkfcb(&lf, nm) || fmake(&lf)) return 1;
    for (l = prog; l < pend; l += LLEN(l)) {
        dn = depthof(LTOK(l), &af);
        d = d > dn ? d - dn : 0;
        n = ltext(l, nums, d * 2);
        lb[n++] = 13; lb[n++] = 10;
        for (i = 0; i < n; i++) { ob[op++] = lb[i]; if (op == 128) { if (rwrite(&lf, rec++, ob)) err = 1; op = 0; } }
        d += af;
    }
    memset(ob + op, 0x1A, 128 - op);
    if (rwrite(&lf, rec, ob)) err = 1;
    fclose(&lf);
    return err;
}
void ovl_entry(uint8_t op)
{
    switch (op) {
    case OV_LIST: list(ovn1, ovn2, 1); break;
    case OV_SAVE: if (savefile(fnb)) error(31); break;
    case OV_EDIT:                        /* la linea ovn1 para cambiarla; ovret 1 si queda algo */
        ltext(findline(ovn1, 1), 1, 0);
        if (getline_(strlen(lb)) && lb[0]) ovret = 1;
        break;
    }
}
