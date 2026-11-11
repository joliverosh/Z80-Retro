/* zcov1.c - parte de ZCALC que se carga de ZCALC.OVL: cargar .ZC y .CSV
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 200000 */
#include "zcalc.h"

static uint8_t hexv(char c) { return c <= '9' ? c - '0' : c - 'A' + 10; }
static uint8_t loadfile(const char *name)
{
    static char l[130];
    static uint8_t n;
    static uint8_t c;
    static uint8_t r;
    static uint8_t fl;
    static uint8_t bad;
    static int ch;
    static const char *p;
    static cell *x;
    bad = 0;
    if (!mkfcb(&inf, name) || fopen(&inf)) return 1;
    inp = 128;
    clearall();
    gw = 9; gnf = 1; autoc = 1; nnm = 0;
    memset(cw, 0, sizeof cw);
    for (;;) {
        n = 0;
        while ((ch = rdc()) >= 0 && ch != 26 && ch != '\n') if (ch != '\r' && n < 129) l[n++] = ch;
        l[n] = 0;
        if (n) {
            if (l[0] == 'G' && l[1] == ' ') {
                for (p = l + 2, n = 0; isdig(*p); p++) n = n * 10 + *p - '0';
                if (n >= 3 && n <= 40) gw = n;
                if (p[0] == ' ' && isdig(p[1])) { gnf = (p[1] - '0') * 10 + p[2] - '0'; if (!gnf || gnf > 12) gnf = 1; }
                autoc = p[4] != 'M';
            } else if (l[0] == 'W' && l[1] == ' ') {
                p = l + 2; c = *p++ - 'A' + 1;
                if (isup(*p)) c = c * 26 + (*p++ - 'A' + 1);
                for (n = 0, p++; isdig(*p); p++) n = n * 10 + *p - '0';
                if (c <= NC && n >= 3 && n <= 40) cw[c] = n;
            } else if (l[0] == 'N' && l[1] == ' ') {          /* N NOMBRE rango */
                for (p = l + 2, n = 0; *p && *p != ' ' && n < 8; p++) nms[nnm].nm[n++] = *p;
                nms[nnm].nm[n] = 0;
                if (*p == ' ' && nnm < NNM && tok(p + 1, tb) && (tb[0] == TK_REF || tb[0] == TK_RNG)) {
                    memcpy(nms[nnm].t, tb, 6);
                    nnm++;
                } else bad = 1;
            } else if (l[0] != 'Z') {
                p = l;
                if (pref(&p, &c, &r, &fl) && p[0] == '|' && p[3] == '|') {
                    fl = hexv(p[1]) << 4 | hexv(p[2]);
                    p += 4;
                    if (*p == '"') n = setcell(c, r, p + 1, 1);
                    else if (*p == '\\') n = setcell(c, r, p + 1, 2);
                    else n = setcell(c, r, p, 0);
                    if (n == 2) { bad = 2; break; }
                    if (n) bad = 1;
                    else if ((x = find(c, r))) x->f = fl;
                } else bad = 1;
            }
        }
        if (ch < 0 || ch == 26) break;
    }
    fclose(&inf);
    strncpy(fname_, name, 15);
    recalc();
    modified = 0;
    dirty = 1;
    return bad ? bad + 1 : 0;
}
/* un campo de CSV es numero si es solo [signo] cifras [. cifras] [E [signo] cifras] */
static uint8_t isnumtxt(const char *s)
{
    uint8_t d = 0;
    if (*s == '-' || *s == '+') s++;
    while (isdig(*s)) { s++; d++; }
    if (*s == '.') { s++; while (isdig(*s)) { s++; d++; } }
    if (!d) return 0;
    if (*s == 'E' || *s == 'e') {
        s++;
        if (*s == '-' || *s == '+') s++;
        if (!isdig(*s)) return 0;
        while (isdig(*s)) s++;
    }
    return !*s;
}
static uint8_t loadcsv(const char *name)
{
    static char l[130];
    static uint8_t n, row, col, inq, qend, e, c, r;
    static int ch;
    if (!mkfcb(&inf, name) || fopen(&inf)) return 1;
    inp = 128;
    n = row = col = inq = qend = e = 0;
    for (;;) {
        ch = rdc();
        if (ch == 26) ch = -1;
        if (inq) {
            if (ch == '"') {
                if (qend) { if (n < 129) l[n++] = '"'; qend = 0; } else qend = 1;
                continue;
            }
            if (!qend && ch >= 0) { if (n < 129) l[n++] = ch; continue; }
            inq = qend = 0;
        }
        if (ch == '"' && !n) { inq = 1; continue; }
        if (ch == '\r') continue;
        if (ch == ',' || ch == '\n' || ch < 0) {
            l[n] = 0;
            c = cc + col; r = cr + row;
            if (n && c >= cc && c <= NC && r >= cr && r <= NR) {
                if (isnumtxt(l)) e = setcell(c, r, l, 0);
                else e = setcell(c, r, l, 1);
                if (e == 2) break;
                e = 0;
            }
            n = 0;
            if (ch == ',') col++;
            else { col = 0; row++; }
            if (ch < 0) break;
            continue;
        }
        if (n < 129) l[n++] = ch;
    }
    fclose(&inf);
    dirty = 1;
    return e == 2 ? 3 : 0;
}
static void load(void)
{
    static uint8_t e, iscsv;
    if (!input("Load (.ZC, .WKS, or .CSV at the cursor): ", fname_) || !eb[0]) return;
    defext(eb, ".ZC");
    iscsv = strchr(eb, '.') && !memcmp(strchr(eb, '.'), ".CSV", 5);
    if (!iscsv && modified && ask("Sheet not saved. Load anyway? (Y/N)") != 'Y') return;
    if (strchr(eb, '.') && !memcmp(strchr(eb, '.'), ".WK", 3)) { ovlret = 9; return; }   /* 1-2-3: zcov8 */
    e = iscsv ? loadcsv(eb) : loadfile(eb);
    if (e == 1) msg("File not found");
    else if (e == 2) msg("Some lines could not be read");
    else if (e == 3) msg("Memory full");
}

void ovl_entry(uint8_t op)
{
    if (op == 1) load();
    else if (strchr(eb, '.') && !memcmp(strchr(eb, '.'), ".WK", 3)) ovlret = 9;
    else ovlret = loadfile(eb);
}
