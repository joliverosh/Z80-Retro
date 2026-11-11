/* zcov2.c - parte de ZCALC que se carga de ZCALC.OVL: guardar, exportar CSV, imprimir
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include "zcalc.h"

static void save(void)
{
    static cell *x;
    static uint8_t i;
    static char b[8];
    if (!input("Save as: ", fname_) || !eb[0]) return;
    defext(eb, ".ZC");
    if (ofile(eb)) { msg("Can't create file"); return; }
    strncpy(fname_, eb, 15);
    os("ZCALC 1\r\n");
    utoa_(gw, b); b[ndig(gw)] = 0;
    os("G "); os(b); oc(' '); oc(gnf >= 10 ? '1' : '0'); oc('0' + (gnf >= 10 ? gnf - 10 : gnf)); oc(' '); oc(autoc ? 'A' : 'M'); os("\r\n");
    for (i = 1; i <= NC; i++)
        if (cw[i]) { os("W "); colname(b, i); os(b); oc(' '); utoa_(cw[i], b); b[ndig(cw[i])] = 0; os(b); os("\r\n"); }
    for (i = 0; i < nnm; i++)
        if (nms[i].nm[0]) { os("N "); os(nms[i].nm); oc(' '); dtok(nms[i].t, sb, 40); os(sb); os("\r\n"); }
    FOR_CELLS(x) {
        refname(b, x->c, x->r, 0); os(b);
        oc('|'); oc("0123456789ABCDEF"[x->f >> 4]); oc("0123456789ABCDEF"[x->f & 15]); oc('|');
        celltext(x, sb, 86); os(sb); os("\r\n");
    }
    if (oclose()) msg("Disk full");
    else modified = 0;
}
static void csv(void)
{
    static uint8_t mc;
    static uint8_t mr;
    static uint8_t c;
    static uint8_t r;
    static uint8_t i;
    static cell *x;
    static char name[16];
    if (!usedmax(&mc, &mr)) return;
    strcpy(name, fname_);
    if (strchr(name, '.')) *strchr(name, '.') = 0;
    if (*name) strcat(name, ".CSV");
    if (!input("CSV file: ", name) || !eb[0]) return;
    defext(eb, ".CSV");
    if (ofile(eb)) { msg("Can't create file"); return; }
    for (r = 1; r <= mr; r++) {
        for (c = 1; c <= mc; c++) {
            if (c > 1) oc(',');
            x = find(c, r);
            if (!x || KIND(x) == K_REP) continue;
            if (KIND(x) == K_LAB) {
                oc('"');
                for (i = 0; i < x->n; i++) { if (x->d[i] == '"') oc('"'); oc(x->d[i]); }
                oc('"');
            } else if (VT(x) == V_STR) {
                oc('"');
                for (i = 0; i < STRN(x); i++) { if (STRP(x)[i] == '"') oc('"'); oc(STRP(x)[i]); }
                oc('"');
            } else if (VT(x)) os(VT(x) == V_ERR ? "#ERROR" : "#NA");
            else { if (!nplain(sb, NUMP(x), -1, 30)) nsci(sb, NUMP(x), 22); os(sb); }
        }
        os("\r\n");
    }
    if (oclose()) msg("Disk full");
}
static void print(void)
{
    static uint8_t mc;
    static uint8_t mr;
    static uint8_t c1;
    static uint8_t r1;
    static uint8_t c2;
    static uint8_t r2;
    static uint8_t c;
    static uint8_t r;
    static uint8_t n;
    if (!usedmax(&mc, &mr)) return;
    if (!input("Print to file (Enter = printer): ", "")) return;
    if (eb[0]) {
        defext(eb, ".PRN");
        if (ofile(eb)) { msg("Can't create file"); return; }
    } else odev = 1;
    strcpy(sb, "A1:");
    refname(sb + 3, mc, mr, 0);
    if (!input("Range: ", sb) || !prange(eb, &c1, &r1, &c2, &r2)) { if (!odev) { oclose(); } return; }
    for (r = r1; r <= r2 && r >= r1; r++) {
        for (c = c1, n = 0; c <= c2; c++) {
            cellstr(sb, c, r, CW(c));
            os(sb);
        }
        os("\r\n");
        (void)n;
    }
    if (odev) oc(12);
    if (oclose()) msg("Disk full");
}

void ovl_entry(uint8_t op)
{
    if (op == 1) save();
    else if (op == 2) csv();
    else print();
}
