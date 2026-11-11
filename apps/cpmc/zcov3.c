/* zcov3.c - parte de ZCALC que se carga de ZCALC.OVL: las ordenes /F /G /R /M
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include "zcalc.h"

static uint8_t fmtkey(uint8_t k, uint8_t f)
{
    if (k == 'D') return f & 0x40;      /* el bloqueo se queda */
    if (k == 'G') return (f & 0xF0) | 1;
    if (k == 'I') return (f & 0xF0) | 3;
    if (k == '$') return (f & 0xF0) | 5;
    if (k == '*') return (f & 0xF0) | 2;
    if (k >= '0' && k <= '9') return (f & 0xF0) | (k - '0' + 3);
    if (k == '/') return (f & 0xF0) | 13;   /* fecha dd/mm/aa */
    if (k == ':') return (f & 0xF0) | 14;   /* hora hh:mm */
    if (k == 'L') return (f & 0xCF) | 0x10;
    if (k == 'R') return (f & 0xCF) | 0x20;
    return 0xFF;
}
static uint8_t askw(uint8_t def)
{
    static uint8_t w;
    static char *p;
    w = 0;
    utoa_(def, sb); sb[ndig(def)] = 0;
    if (!input("Column width (3-40): ", sb)) return 0;
    for (p = eb; *p >= '0' && *p <= '9'; p++) w = w * 10 + *p - '0';
    if (*p || w < 3 || w > 40) { msg("Width 3-40"); return 0; }
    return w;
}
static void cmd_format(void)
{
    static uint8_t k;
    static uint8_t f;
    static uint8_t w;
    static cell *x;
    k = ask("Format: D(efault) G I $ 0-9 *(graph) /(date) :(time) L R W(idth)");
    if (k == 'W') { if ((w = askw(CW(cc)))) { cw[cc] = w == gw ? 0 : w; modified = 1; } return; }
    x = find(cc, cr);
    f = fmtkey(k, x ? x->f : 0);
    if (f == 0xFF) return;
    if (!x) { if (!(x = newcell(cc, cr, K_LAB, 0))) { msg("Memory full"); return; } }
    x->f = f;
    if (KIND(x) == K_LAB && !x->n && !f) delcell(cc, cr);
    modified = 1;
}
static void cmd_global(void)
{
    static uint8_t k;
    static uint8_t w;
    static uint8_t i;
    k = ask("Global: C(olumn width) F(ormat) R(ecalc)");
    if (k == 'C') {
        if ((w = askw(gw))) { gw = w; for (i = 1; i <= NC; i++) cw[i] = 0; modified = 1; }
    } else if (k == 'F') {
        k = ask("Global format: G I $ 0-9 *");
        if ((i = fmtkey(k, 0)) != 0xFF && (i & 15)) { gnf = i & 15; modified = 1; }
    } else if (k == 'R') {
        k = ask("Recalc: A(utomatic) M(anual)");
        if (k == 'A') { autoc = 1; recalc(); } else if (k == 'M') autoc = 0;
    }
}
static void cmd_repl(void)
{
    static uint8_t c1;
    static uint8_t r1;
    static uint8_t c2;
    static uint8_t r2;
    static uint8_t t1;
    static uint8_t u1;
    static uint8_t t2;
    static uint8_t u2;
    static uint8_t c;
    static uint8_t r;
    static uint8_t i;
    static uint8_t j;
    static uint8_t err;
    err = 0;
    curref(sb);
    if (!input("Replicate from: ", sb) || !prange(eb, &c1, &r1, &c2, &r2)) return;
    if (!input("To: ", "") || !prange(eb, &t1, &u1, &t2, &u2)) return;
    /* destinos: un bloque en cada (c, r) de la lista */
    for (r = u1; r <= u2 && r >= u1; r++)
        for (c = t1; c <= t2; c++) {
            if (!((c1 == c2 && r1 == r2) || (c == t1 && r == u1) ||
                  (c1 == c2 && u1 == u2) || (r1 == r2 && t1 == t2))) continue;
            for (j = 0; j <= r2 - r1 && r + j <= NR; j++)
                for (i = 0; i <= c2 - c1 && c + i <= NC; i++) {
                    cell *x = find(c1 + i, r1 + j);
                    if (x) { if (copycell(x, c + i, r + j)) err = 1; }
                    else delcell(c + i, r + j);
                }
        }
    if (err) msg("Memory full");
}
static void cmd_move(void)
{
    static uint8_t c1;
    static uint8_t r1;
    static uint8_t c2;
    static uint8_t r2;
    static uint8_t tc;
    static uint8_t tr;
    static uint8_t c;
    static uint8_t r;
    static cell *x;
    curref(sb);
    if (!input("Move from: ", sb) || !prange(eb, &c1, &r1, &c2, &r2)) return;
    if (!input("To: ", "") || !isarg(eb, &tc, &tr)) return;
    am = 2; mc1 = c1; mr1 = r1; mc2 = c2; mr2 = r2; mdc = tc - c1; mdr = tr - r1;
    if (!mdc && !mdr) return;
    adjall();
    /* las del destino que no se mueven se pierden; las movidas cambian de lugar */
    FOR_CELLS(x) {
        uint8_t ins = x->c >= c1 && x->c <= c2 && x->r >= r1 && x->r <= r2;
        int16_t nc = x->c + mdc, nr = x->r + mdr;
        if (ins) { x->fl |= F_MARK; if (nc < 1 || nc > NC || nr < 1 || nr > NR) x->c = 0; }
        else x->fl &= ~F_MARK;
    }
    FOR_CELLS(x)
        if (!(x->fl & F_MARK) && x->c >= c1 + mdc && x->c <= c2 + mdc && x->r >= r1 + mdr && x->r <= r2 + mdr) x->c = 0;
    FOR_CELLS(x)
        if ((x->fl & F_MARK) && x->c) { x->c += mdc; x->r += mdr; }
    FOR_CELLS(x) x->fl &= ~F_MARK;
    (void)c; (void)r;
    rehash();
    modified = dirty = 1;
}
void ovl_entry(uint8_t op)
{
    switch (op) {
    case 'F': cmd_format(); dirty = 1; break;
    case 'G': cmd_global(); dirty = 1; break;
    case 'R': cmd_repl(); break;
    case 'M': cmd_move(); break;
    }
}
