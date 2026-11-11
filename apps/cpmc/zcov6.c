/* zcov6.c - parte de ZCALC que se carga de ZCALC.OVL: los nombres de rango (/N)
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include "zcalc.h"

/* 1 si la formula t usa el nombre id */
static uint8_t hasnm(uint8_t *t, uint8_t id)
{
    while (*t)
        switch (*t) {
        case TK_NUM: t += 6; break;
        case TK_REF: t += 3; break;
        case TK_RNG: t += 5; break;
        case TK_FN: case TK_I8: t += 2; break;
        case TK_STR: t += 2 + t[1]; break;
        case TK_NM: if (t[1] == id) return 1; t += 2; break;
        default: t++;
        }
    return 0;
}
/* vuelve a compilar las formulas que usan el nombre id (con dknm = id + 1,
   ese nombre queda como coordenadas) */
static void retok(uint8_t id)
{
    static cell *x, *y;
    static uint8_t f, c, r;
    FOR_CELLS(x) {
        x->fl &= ~F_MARK;
        if (KIND(x) == K_FRM && hasnm(TOK(x), id)) x->fl |= F_MARK;
    }
    for (;;) {
        y = 0;
        FOR_CELLS(x) if (x->fl & F_MARK) { y = x; break; }
        if (!y) break;
        y->fl &= ~F_MARK;
        dtok(TOK(y), eb, MAXE);
        f = y->f; c = y->c; r = y->r;
        if (!setcell(c, r, eb, 0) && (y = find(c, r))) y->f = f;
    }
    dknm = 0;
    modified = dirty = 1;
}
static uint8_t nfind(const char *s)
{
    static uint8_t i;
    for (i = 0; i < nnm; i++) if (nms[i].nm[0] && !memcmp(nms[i].nm, s, strlen(s) + 1)) return i;
    return 0xFF;
}
static uint8_t okname(char *s)
{
    static uint8_t i, c, r;
    for (i = 0; s[i]; i++) {
        if (s[i] >= 'a' && s[i] <= 'z') s[i] -= 32;
        if (!(isup(s[i]) || (i && (isdig(s[i]) || s[i] == '_')))) return 0;
    }
    if (!i || i > 8 || isarg(s, &c, &r)) return 0;
    return tok(s, tb) == 0 || tb[0] == TK_REF || tb[0] == TK_RNG;   /* no una funcion */
}
static void cmd_name(void)
{
    static uint8_t k, id, c1, r1, c2, r2, i;
    static char nm[10];
    k = ask("Names: C(reate) D(elete) L(ist)");
    if (k == 'L') {
        pstr(CLS "Range names\n\n");
        for (i = 0; i < nnm; i++)
            if (nms[i].nm[0]) { dtok(nms[i].t, sb, 40); pf("  %-9s %s\n", nms[i].nm, sb); }
        pstr("\nPress any key.");
        getk();
        pstr(CLS);
        dirty = 1;
        return;
    }
    if (k != 'C' && k != 'D') return;
    if (!input("Name: ", "") || !eb[0]) return;
    if (!okname(eb)) { msg("Bad name (letters, digits and _, not a cell or a function)"); return; }
    strcpy(nm, eb);
    id = nfind(nm);
    if (k == 'D') {
        if (id == 0xFF) { msg("No such name"); return; }
        dknm = id + 1;
        retok(id);
        nms[id].nm[0] = 0;
        return;
    }
    curref(sb);
    if (!input("Range: ", sb) || !prange(eb, &c1, &r1, &c2, &r2)) return;
    if (id == 0xFF) {
        for (id = 0; id < nnm && nms[id].nm[0]; id++) ;
        if (id == NNM) { msg("Too many names"); return; }
        if (id == nnm) nnm++;
    }
    strcpy(nms[id].nm, nm);
    if (c1 == c2 && r1 == r2) {
        nms[id].t[0] = TK_REF; nms[id].t[1] = c1 | 0xC0; nms[id].t[2] = r1; nms[id].t[3] = TK_END;
    } else {
        nms[id].t[0] = TK_RNG; nms[id].t[1] = c1 | 0xC0; nms[id].t[2] = r1;
        nms[id].t[3] = c2 | 0xC0; nms[id].t[4] = r2; nms[id].t[5] = TK_END;
    }
    retok(id);
}
void ovl_entry(uint8_t op)
{
    (void)op;
    cmd_name();
}
