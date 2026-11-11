/* ROGUE - baja por el calabozo, encuentra el Amuleto de Yendor (en el piso 13 o
   mas abajo) y vuelve a subir con el.
   Teclas: h j k l y u b n o las flechas mueven (en mayuscula corren), > baja, < sube
   (con el amuleto), i inventario, q bebe, r lee, e come, w empuna, W viste, T quita
   la armadura, d suelta, s o . descansa, ? ayuda, Q sale. Los mensajes van en ingles.
   (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 50000 */
#include <string.h>
#include "cpm.h"

#define MW 80
#define MH 21                    /* filas del mapa (pantalla 2-22) */
#define MAXO 48                  /* objetos en el piso */
#define MAXM 24                  /* monstruos */
#define NINV 18                  /* el inventario: a-r */
#define AMDEPTH 13               /* donde esta el amuleto */

/* ---------------------------------------------------------------- azar */
static uint16_t rn(uint16_t n) { return n ? rnd() % n : 0; }
static uint16_t dice(uint8_t n, uint8_t s) { uint16_t t = 0; while (n--) t += rn(s) + 1; return t; }

/* ---------------------------------------------------------------- el mapa */
static uint8_t map[MH][MW];      /* ' ' roca, - | paredes, . piso, + puerta, # pasillo, > escalera */
static uint8_t mem[MH][MW];      /* lo que se recuerda de cada lugar (0: nunca visto) */
static uint8_t scr[MH][MW];      /* lo que hay en la pantalla */
static uint8_t oat[MH][MW];      /* objeto en el lugar (indice + 1) */
static uint8_t mat[MH][MW];      /* monstruo en el lugar (indice + 1) */
typedef struct { uint8_t x, y, w, h; } room;   /* con las paredes */
static room rm[9];

/* ---------------------------------------------------------------- objetos */
enum { O_NONE, O_GOLD, O_POT, O_SCR, O_FOOD, O_WPN, O_ARM, O_AMU };
typedef struct { uint8_t t, s, n; int8_t e; uint8_t x, y; } obj;   /* tipo, clase, cuantos, encantamiento */
static obj fl[MAXO];             /* en el piso */
static obj inv[NINV];            /* el inventario (t 0: vacio) */
static const char otc[] = " *!?:)],";

#define NPOT 8
#define NSCR 7
enum { P_HEAL, P_XHEAL, P_STR, P_RESTORE, P_POISON, P_CONF, P_DETECT, P_RAISE };
enum { S_MAP, S_IDENT, S_TELE, S_EWPN, S_EARM, S_SLEEP, S_MONST };
static const char *const potn[NPOT] = { "healing", "extra healing", "gain strength", "restore strength",
    "poison", "confusion", "detect monsters", "raise level" };
static const char *const scrn[NSCR] = { "magic mapping", "identify", "teleportation", "enchant weapon",
    "enchant armor", "sleep", "create monster" };
static const char *const colors[] = { "blue", "red", "green", "amber", "black", "white", "pink",
    "purple", "brown", "golden", "silver", "cloudy", "orange", "plaid" };
static const char *const syl[] = { "zok", "bar", "ix", "nel", "fu", "gra", "mon", "ro", "tu", "wex",
    "ka", "pli", "dor", "sne", "ul", "yag" };
static uint8_t pcol[NPOT];       /* el color de cada pocion */
static char stitle[NSCR][14];    /* el titulo de cada pergamino */
static uint8_t pknown, sknown;   /* bits: ya se sabe que es */
static uint8_t prob_pot[NPOT] = { 25, 8, 6, 8, 10, 10, 8, 3 };   /* de 78 */
static uint8_t prob_scr[NSCR] = { 10, 22, 10, 10, 12, 6, 6 };    /* de 76 */

typedef struct { const char *nm; uint8_t lo, hi; } wpn_t;
#define NWPN 5
static const wpn_t wpns[NWPN] = { { "dagger", 1, 4 }, { "mace", 2, 8 }, { "spear", 2, 10 },
    { "long sword", 3, 12 }, { "two-handed sword", 4, 16 } };
typedef struct { const char *nm; uint8_t ac; } arm_t;
#define NARM 6
static const arm_t arms[NARM] = { { "leather armor", 2 }, { "ring mail", 3 }, { "scale mail", 4 },
    { "chain mail", 5 }, { "banded mail", 6 }, { "plate mail", 7 } };

/* ---------------------------------------------------------------- monstruos */
#define F_MEAN 1
#define F_FLY 2
#define F_REGEN 4
#define F_GOLD 8                 /* roba oro */
#define F_ITEM 16                /* roba un objeto */
#define F_RUST 32                /* oxida la armadura */
#define F_WEAK 64                /* quita fuerza */
typedef struct { const char *nm; char c; uint8_t lv; int8_t ac; uint8_t dmg; uint16_t xp; uint8_t f; } mtype;
#define NMT 22
static const mtype mt[NMT] = {
    { "bat", 'B', 1, 3, 2, 1, F_FLY }, { "emu", 'E', 1, 7, 2, 2, F_MEAN },
    { "hobgoblin", 'H', 1, 5, 8, 3, F_MEAN }, { "kestrel", 'K', 1, 7, 4, 1, F_MEAN | F_FLY },
    { "snake", 'S', 1, 5, 3, 2, F_MEAN }, { "jackal", 'J', 1, 7, 2, 2, F_MEAN },
    { "orc", 'O', 2, 6, 8, 5, F_MEAN }, { "zombie", 'Z', 2, 8, 8, 6, F_MEAN },
    { "leprechaun", 'L', 3, 8, 1, 10, F_GOLD }, { "nymph", 'N', 3, 9, 0, 15, F_ITEM },
    { "quagga", 'Q', 3, 3, 9, 15, F_MEAN }, { "rattlesnake", 'R', 4, 3, 6, 15, F_MEAN | F_WEAK },
    { "centaur", 'C', 4, 4, 10, 25, 0 }, { "aquator", 'A', 5, 2, 0, 20, F_MEAN | F_RUST },
    { "yeti", 'Y', 4, 6, 12, 50, 0 }, { "wraith", 'W', 5, 4, 8, 55, F_MEAN },
    { "troll", 'T', 6, 4, 14, 120, F_MEAN | F_REGEN }, { "xeroc", 'X', 7, 7, 14, 100, 0 },
    { "ur-vile", 'U', 7, 2, 16, 190, F_MEAN }, { "vampire", 'V', 8, 1, 18, 350, F_MEAN | F_REGEN },
    { "griffin", 'G', 9, 2, 18, 400, F_MEAN | F_FLY }, { "dragon", 'D', 10, -1, 24, 1500, F_MEAN } };
typedef struct { uint8_t t, x, y, awake; int16_t hp; } mon;   /* t: tipo + 1 (0: no hay) */
static mon ms[MAXM];

/* ---------------------------------------------------------------- el jugador */
static uint8_t px, py, depth, maxdepth, plv, str, maxstr, hasamu, conf, detect, quit, dead;
static int16_t hp, maxhp, food;
static uint16_t xp, gold, turn;
static int8_t wield = -1, wear = -1;   /* indices en inv */
static const char *killer;
static const uint16_t xpl[] = { 10, 20, 40, 80, 160, 320, 640, 1300, 2600, 5200, 10000, 20000, 40000 };

/* ---------------------------------------------------------------- pantalla */
static char mb[160];             /* el mensaje que se arma */
static uint8_t ml, mshown;       /* largo; ya hay un mensaje en la linea */
static void ms_(const char *s) { while (*s && ml < sizeof mb - 1) mb[ml++] = *s++; mb[ml] = 0; }
static void mn_(int16_t n)
{
    char b[7], *p = b + 6;
    uint8_t neg = n < 0;
    uint16_t u = neg ? -n : n;
    *p = 0;
    do { *--p = '0' + u % 10; u /= 10; } while (u);
    if (neg) *--p = '-';
    ms_(p);
}
static void mshow(void)          /* el mensaje armado, en la fila 1 */
{
    if (!ml) return;
    if (mshown) {                /* el anterior no se ha leido */
        gotoxy(mshown + 1, 1); pstr(ESC "[7m--More--" ESC "[0m");
        while (waitkey() != ' ') ;
    }
    gotoxy(1, 1); pstr(ESC "[K"); pstr(mb);
    mshown = ml < 70 ? ml + 1 : 70;
    ml = 0; mb[0] = 0;
}
static void msg(const char *s) { ms_(s); mshow(); }
static void mclear(void) { if (mshown) { gotoxy(1, 1); pstr(ESC "[K"); mshown = 0; } }
static uint8_t inroom(uint8_t r, uint8_t x, uint8_t y)
{
    return x >= rm[r].x && x < rm[r].x + rm[r].w && y >= rm[r].y && y < rm[r].y + rm[r].h;
}
static int8_t proom;             /* el cuarto del jugador (-1 en un pasillo) */
static void whereis(void)
{
    uint8_t r;
    proom = -1;
    for (r = 0; r < 9; r++) if (rm[r].w && inroom(r, px, py)) proom = r;
}
static uint8_t seen(uint8_t x, uint8_t y)
{
    int8_t dx = x - px, dy = y - py;
    if (dx >= -1 && dx <= 1 && dy >= -1 && dy <= 1) return 1;
    return proom >= 0 && inroom(proom, x, y);
}
static void status(void)
{
    gotoxy(1, 24);
    pf("Level: %u  Gold: %u  Hp: %d(%d)  Str: %u(%u)  Arm: %d  Exp: %u/%u", depth, gold, hp, maxhp,
       str, maxstr, wear >= 0 ? arms[inv[wear].s].ac + inv[wear].e : 0, plv, xp);
    if (food < 0) pstr("  Faint");
    else if (food < 150) pstr("  Weak");
    else if (food < 300) pstr("  Hungry");
    pstr(ESC "[K");
}
static void draw(void)
{
    static uint8_t x, y, c, d, *m, *s;
    whereis();
    for (y = 0; y < MH; y++) {
        m = mem[y]; s = scr[y];
        for (x = 0; x < MW; x++) {
            if (seen(x, y)) {
                c = map[y][x];
                if (oat[y][x]) c = otc[fl[oat[y][x] - 1].t];
                m[x] = c;
                if ((d = mat[y][x])) c = mt[ms[d - 1].t - 1].c;
            } else {
                c = m[x];
                if (!c) c = ' ';
                if (detect && (d = mat[y][x])) c = mt[ms[d - 1].t - 1].c;
            }
            if (x == px && y == py) c = '@';
            if (s[x] != c) { s[x] = c; gotoxy(x + 1, y + 2); putch(c); }
        }
    }
    status();
    gotoxy(px + 1, py + 2);
}
static void redraw(void) { pstr(CLS); memset(scr, ' ', sizeof scr); mshown = 0; draw(); }

/* ---------------------------------------------------------------- nombres */
static void oname(obj *o)        /* el nombre del objeto, al mensaje */
{
    uint8_t pl = o->n > 1;
    if (pl && o->t != O_GOLD) { mn_(o->n); ms_(" "); }
    switch (o->t) {
    case O_GOLD: mn_(o->n * 10); ms_(" gold pieces"); break;
    case O_POT:
        if (!pl) ms_("a ");
        if (pknown & 1 << o->s) { ms_(pl ? "potions of " : "potion of "); ms_(potn[o->s]); }
        else { ms_(colors[pcol[o->s]]); ms_(pl ? " potions" : " potion"); }
        break;
    case O_SCR:
        if (!pl) ms_("a ");
        ms_(pl ? "scrolls " : "scroll ");
        if (sknown & 1 << o->s) { ms_("of "); ms_(scrn[o->s]); }
        else { ms_("titled '"); ms_(stitle[o->s]); ms_("'"); }
        break;
    case O_FOOD: ms_(pl ? "rations of food" : "a ration of food"); break;
    case O_WPN: if (o->e >= 0) ms_("+"); mn_(o->e); ms_(" "); ms_(wpns[o->s].nm); break;
    case O_ARM: if (o->e >= 0) ms_("+"); mn_(o->e); ms_(" "); ms_(arms[o->s].nm);
        ms_(" ["); mn_(arms[o->s].ac + o->e); ms_("]"); break;
    case O_AMU: ms_("the Amulet of Yendor"); break;
    }
}
static void mname(uint8_t i) { ms_("the "); ms_(mt[ms[i].t - 1].nm); }

/* ---------------------------------------------------------------- el calabozo */
static uint8_t pass(uint8_t c) { return c == '.' || c == '+' || c == '#' || c == '>'; }
static void corr(uint8_t x, uint8_t y)
{
    if (map[y][x] == ' ') map[y][x] = '#';
}
/* une el cuarto a con el b (b a la derecha si horiz, si no debajo) */
static void join(uint8_t a, uint8_t b, uint8_t horiz)
{
    static uint8_t x1, y1, x2, y2, j, i;
    room *A = &rm[a], *B = &rm[b];
    if (horiz) {
        x1 = A->x + A->w - 1; y1 = A->y + 1 + rn(A->h - 2);
        x2 = B->x; y2 = B->y + 1 + rn(B->h - 2);
        map[y1][x1] = '+'; map[y2][x2] = '+';
        j = x1 + 1 + rn(x2 - x1 - 1);
        for (i = x1 + 1; i <= j; i++) corr(i, y1);
        for (i = y1 < y2 ? y1 : y2; i <= (y1 < y2 ? y2 : y1); i++) corr(j, i);
        for (i = j; i < x2; i++) corr(i, y2);
    } else {
        x1 = A->x + 1 + rn(A->w - 2); y1 = A->y + A->h - 1;
        x2 = B->x + 1 + rn(B->w - 2); y2 = B->y;
        map[y1][x1] = '+'; map[y2][x2] = '+';
        j = y1 + 1 + rn(y2 - y1 - 1);
        for (i = y1 + 1; i <= j; i++) corr(x1, i);
        for (i = x1 < x2 ? x1 : x2; i <= (x1 < x2 ? x2 : x1); i++) corr(i, j);
        for (i = j; i < y2; i++) corr(x2, i);
    }
}
static void spot(uint8_t *x, uint8_t *y)   /* un lugar libre en el piso de un cuarto */
{
    room *r;
    do {
        r = &rm[rn(9)];
        *x = r->x + 1 + rn(r->w - 2);
        *y = r->y + 1 + rn(r->h - 2);
    } while (map[*y][*x] != '.' || oat[*y][*x] || mat[*y][*x] || (*x == px && *y == py));
}
static uint8_t pickp(const uint8_t *p, uint8_t n)   /* uno al azar, con su probabilidad */
{
    uint8_t i, t = 0, r;
    for (i = 0; i < n; i++) t += p[i];
    r = rn(t);
    for (i = 0; i < n; i++) { if (r < p[i]) return i; r -= p[i]; }
    return 0;
}
static void newobj(obj *o)
{
    uint8_t r = rn(100);
    o->n = 1; o->e = 0; o->s = 0;
    if (r < 30) { o->t = O_GOLD; o->n = rn(depth * 3 + 3) + 2; }
    else if (r < 55) { o->t = O_POT; o->s = pickp(prob_pot, NPOT); }
    else if (r < 78) { o->t = O_SCR; o->s = pickp(prob_scr, NSCR); }
    else if (r < 88) { o->t = O_FOOD; }
    else if (r < 94) { o->t = O_WPN; o->s = rn(NWPN); r = rn(10); o->e = r < 2 ? -1 : r > 7 ? rn(3) + 1 : 0; }
    else { o->t = O_ARM; o->s = rn(NARM); r = rn(10); o->e = r < 2 ? -1 : r > 7 ? rn(3) + 1 : 0; }
}
static uint8_t putobj(obj *o, uint8_t x, uint8_t y)   /* lo deja en el piso */
{
    uint8_t i;
    for (i = 0; i < MAXO && fl[i].t; i++) ;
    if (i == MAXO) return 0;
    fl[i] = *o; fl[i].x = x; fl[i].y = y;
    oat[y][x] = i + 1;
    return 1;
}
static void newmon(uint8_t awake)
{
    uint8_t i, t, x, y, lo, hi;
    for (i = 0; i < MAXM && ms[i].t; i++) ;
    if (i == MAXM) return;
    lo = depth > 6 ? depth - 6 : 1; hi = depth + 1;
    do t = rn(NMT); while (mt[t].lv < lo || mt[t].lv > hi);
    spot(&x, &y);
    ms[i].t = t + 1; ms[i].x = x; ms[i].y = y; ms[i].awake = awake;
    ms[i].hp = dice(mt[t].lv, 8);
    mat[y][x] = i + 1;
}
static void level(void)
{
    static uint8_t i, j, k, n, x, y;
    static obj o;
    memset(map, ' ', sizeof map); memset(mem, 0, sizeof mem);
    memset(oat, 0, sizeof oat); memset(mat, 0, sizeof mat);
    memset(fl, 0, sizeof fl); memset(ms, 0, sizeof ms);
    for (i = 0; i < 9; i++) {    /* un cuarto en cada parte de una cuadricula de 3 x 3 */
        room *r = &rm[i];
        r->w = 5 + rn(20); r->h = 4 + rn(3);
        r->x = (i % 3) * 26 + rn(25 - r->w + 1);
        r->y = (i / 3) * 7 + rn(6 - r->h + 1);
        for (y = r->y; y < r->y + r->h; y++)
            for (x = r->x; x < r->x + r->w; x++)
                map[y][x] = (y == r->y || y == r->y + r->h - 1) ? '-' : (x == r->x || x == r->x + r->w - 1) ? '|' : '.';
    }
    for (j = 0; j < 3; j++) {    /* cada fila unida, y cada fila con la de abajo */
        join(j * 3, j * 3 + 1, 1);
        join(j * 3 + 1, j * 3 + 2, 1);
        if (j < 2) {
            k = rn(3);
            join(j * 3 + k, j * 3 + 3 + k, 0);
            if (rn(2)) { n = (k + 1 + rn(2)) % 3; join(j * 3 + n, j * 3 + 3 + n, 0); }
        }
    }
    px = py = 0;
    spot(&x, &y); map[y][x] = '>';
    n = 3 + rn(4);
    for (i = 0; i < n; i++) { newobj(&o); spot(&x, &y); putobj(&o, x, y); }
    if (depth >= AMDEPTH && !hasamu) { o.t = O_AMU; o.n = 1; o.e = 0; spot(&x, &y); putobj(&o, x, y); }
    spot(&x, &y); px = x; py = y;
    n = 3 + depth / 3 + rn(3);
    for (i = 0; i < n; i++) newmon(rn(3) == 0);
    detect = 0;
    redraw();
}

/* ---------------------------------------------------------------- el inventario */
static uint8_t additem(obj *o)   /* 0 si no cabe */
{
    uint8_t i = NINV;
    if (o->t == O_POT || o->t == O_SCR || o->t == O_FOOD)
        for (i = 0; i < NINV; i++)
            if (inv[i].t == o->t && inv[i].s == o->s) { inv[i].n += o->n; break; }
    if (i == NINV) {
        for (i = 0; i < NINV && inv[i].t; i++) ;
        if (i == NINV) return 0;
        inv[i] = *o;
    }
    ms_("you now have "); oname(&inv[i]); ms_(" ("); mb[ml++] = 'a' + i; mb[ml] = 0; ms_(")");
    return 1;
}
static void pickup(void)
{
    uint8_t i = oat[py][px];
    obj *o;
    if (!i) return;
    o = &fl[i - 1];
    if (o->t == O_GOLD) { gold += o->n * 10; ms_("you found "); oname(o); }
    else if (o->t == O_AMU) { hasamu = 1; ms_("you have the Amulet of Yendor! Now go back up"); }
    else if (!additem(o)) { ms_("there is "); oname(o); ms_(" here, but your pack is full"); mshow(); return; }
    mshow();
    o->t = 0; oat[py][px] = 0;
}
static void showinv(uint8_t kind)   /* kind 0: todo */
{
    uint8_t i, r = 2;
    for (i = 0; i < NINV; i++) {
        if (!inv[i].t || (kind && inv[i].t != kind)) continue;
        gotoxy(1, r++); pstr(ESC "[K ");
        putch('a' + i); pstr(") ");
        ml = 0; oname(&inv[i]); pstr(mb); ml = 0; mb[0] = 0;
        if (i == wield) pstr(" (in hand)");
        if (i == wear) pstr(" (being worn)");
    }
    if (r == 2) { gotoxy(1, r++); pstr(ESC "[K You have nothing appropriate."); }
    gotoxy(1, r); pstr(ESC "[K--press space--");
    while (waitkey() != ' ') ;
    redraw();
}
static int8_t choose(const char *what, uint8_t kind)   /* el indice, o -1 */
{
    uint8_t k;
    for (;;) {
        mclear(); ms_(what); ms_(" (* for list) "); mshow(); mshown = 0;
        k = waitkey();
        if (k == '*') { showinv(kind); continue; }
        mclear();
        if (k == 27) return -1;
        k = (k | 32) - 'a';
        if (k < NINV && inv[k].t && (!kind || inv[k].t == kind)) return k;
        msg(k < NINV && inv[k].t ? "you can't do that with it" : "you don't have that");
        return -1;
    }
}
static void useup(uint8_t i)
{
    if (--inv[i].n) return;
    inv[i].t = 0;
    if (wield == i) wield = -1;
    if (wear == i) wear = -1;
}

/* ---------------------------------------------------------------- pelea */
static void gainxp(uint16_t n)
{
    xp += n;
    while (plv < 14 && xp >= xpl[plv - 1]) {
        uint8_t h = rn(10) + 1;
        plv++; maxhp += h; hp += h;
        ms_("welcome to level "); mn_(plv); mshow();
    }
}
static void killmon(uint8_t i)
{
    mat[ms[i].y][ms[i].x] = 0;
    ms[i].t = 0;
}
static void attack(uint8_t i)    /* el jugador pega al monstruo i */
{
    const mtype *m = &mt[ms[i].t - 1];
    int16_t ch, d;
    obj *w = wield >= 0 ? &inv[wield] : 0;
    ms[i].awake = 1;
    ch = 55 + 5 * ((int16_t)plv - m->lv) + 3 * (m->ac - 5) + (w ? 5 * w->e : 0) + (str > 16 ? 5 * (str - 16) : 0);
    if (ch < 5) ch = 5;
    if (ch > 95) ch = 95;
    if (rn(100) >= ch) { ms_("you miss "); mname(i); mshow(); return; }
    d = w ? wpns[w->s].lo + rn(wpns[w->s].hi - wpns[w->s].lo + 1) + w->e : rn(3) + 1;
    if (str > 16) d += str - 16;
    if (str < 7) d--;
    if (d < 1) d = 1;
    ms[i].hp -= d;
    if (ms[i].hp <= 0) {
        ms_("you defeated "); mname(i); mshow();
        gainxp(m->xp + plv);
        killmon(i);
    } else { ms_("you hit "); mname(i); mshow(); }
}
static void monhits(uint8_t i)   /* el monstruo i pega al jugador */
{
    const mtype *m = &mt[ms[i].t - 1];
    int16_t ch, ac = wear >= 0 ? arms[inv[wear].s].ac + inv[wear].e : 0;
    uint8_t k;
    ch = 50 + 5 * m->lv - 6 * ac;
    if (ch < 5) ch = 5;
    if (ch > 95) ch = 95;
    if (rn(100) >= ch) { mname(i); ms_(" misses"); mb[0] &= ~32; mshow(); return; }
    mname(i); mb[0] &= ~32;
    if (m->f & F_GOLD && gold) {
        k = rn(50 + depth * 30); if (k > gold) k = gold;
        gold -= k; ms_(" steals some gold and vanishes"); mshow(); killmon(i); return;
    }
    if (m->f & F_ITEM) {
        uint8_t j, n = 0;
        for (j = 0; j < NINV; j++) if (inv[j].t && j != wield && j != wear) n++;
        if (n) {
            n = rn(n);
            for (j = 0; j < NINV; j++) if (inv[j].t && j != wield && j != wear && !n--) break;
            ms_(" stole "); inv[j].n = 1; oname(&inv[j]); ms_(" and vanished"); mshow();
            inv[j].t = 0; killmon(i); return;
        }
    }
    if (m->f & F_RUST && wear >= 0 && inv[wear].s && inv[wear].e > -3) {
        inv[wear].e--; ms_(" hits; your armor weakens"); mshow(); return;
    }
    if (m->f & F_WEAK && str > 3 && rn(2)) { str--; ms_(" bites; you feel weaker"); mshow(); }
    else { ms_(" hits"); mshow(); }
    hp -= m->dmg ? rn(m->dmg) + 1 : 0;
    if (hp <= 0) { dead = 1; killer = m->nm; }
}
static void movemons(void)
{
    static uint8_t i, nx, ny, bx, by, x, y;
    static int8_t dx, dy;
    static uint16_t best, d;
    static const mtype *m;
    for (i = 0; i < MAXM && !dead; i++) {
        if (!ms[i].t) continue;
        m = &mt[ms[i].t - 1];
        x = ms[i].x; y = ms[i].y;
        if (m->f & F_REGEN && ms[i].hp < m->lv * 8 && !(turn & 3)) ms[i].hp++;
        if (!ms[i].awake) {       /* se despierta si el jugador anda cerca */
            dx = x - px; dy = y - py;
            if ((proom >= 0 && inroom(proom, x, y)) || (dx >= -2 && dx <= 2 && dy >= -2 && dy <= 2))
                if (rn(m->f & F_MEAN ? 3 : 8) == 0) ms[i].awake = 1;
            continue;
        }
        dx = px - x; dy = py - y;
        if (dx >= -1 && dx <= 1 && dy >= -1 && dy <= 1 && !(m->f & F_FLY && rn(3) == 0)
            && !((map[y][x] == '+' || map[py][px] == '+') && dx && dy)) { monhits(i); continue; }
        best = 0xFFFF; bx = x; by = y;
        for (dy = -1; dy <= 1; dy++)
            for (dx = -1; dx <= 1; dx++) {
                nx = x + dx; ny = y + dy;
                if ((!dx && !dy) || nx >= MW || ny >= MH || !pass(map[ny][nx]) || mat[ny][nx] || oat[ny][nx] && fl[oat[ny][nx] - 1].t == O_AMU) continue;
                if (nx == px && ny == py) continue;
                if (dx && dy && (map[y][x] == '+' || map[ny][nx] == '+')) continue;
                if (m->f & F_FLY && rn(2)) d = rn(100);      /* vuela sin rumbo */
                else d = (int16_t)(px - nx) * (px - nx) + (int16_t)(py - ny) * (py - ny);
                if (d < best) { best = d; bx = nx; by = ny; }
            }
        if (bx != x || by != y) {
            mat[y][x] = 0; mat[by][bx] = i + 1;
            ms[i].x = bx; ms[i].y = by;
        }
    }
}

/* ---------------------------------------------------------------- el turno */
static void tick(void)
{
    turn++;
    if (conf) conf--;
    if (hp < maxhp && (plv >= 10 || turn % (20 - plv * 2) == 0)) hp++;
    food--;
    if (food == 300) msg("you are starting to get hungry");
    else if (food == 150) msg("you are starting to feel weak");
    else if (food < -150) { dead = 1; killer = "starvation"; }
    if (food < 0 && rn(8) == 0) { msg("you faint"); movemons(); movemons(); }
    movemons();
    if (rn(70) == 0) newmon(1);
}
static void teleport(void) { uint8_t x, y; spot(&x, &y); px = x; py = y; }
static void quaff(void)
{
    int8_t i = choose("quaff what?", O_POT);
    uint8_t s;
    if (i < 0) return;
    s = inv[i].s;
    pknown |= 1 << s;
    switch (s) {
    case P_HEAL: hp += dice(plv, 4); if (hp > maxhp) hp = ++maxhp; msg("you begin to feel better"); break;
    case P_XHEAL: hp += dice(plv, 8); if (hp > maxhp) { maxhp += 2; hp = maxhp; } msg("you feel much better"); break;
    case P_STR: str++; if (str > maxstr) maxstr = str; msg("you feel stronger. What bulging muscles!"); break;
    case P_RESTORE: str = maxstr; msg("hey, this tastes great. It makes you feel warm all over"); break;
    case P_POISON: if (str > 3) str -= rn(3) + 1; if (str < 3) str = 3; hp -= rn(4); if (hp < 1) hp = 1;
        msg("you feel very sick now"); break;
    case P_CONF: conf = rn(8) + 8; msg("wait, what's going on here? Huh? What? Who?"); break;
    case P_DETECT: detect = 1; msg("you sense the presence of monsters"); break;
    case P_RAISE: msg("you suddenly feel much more skillful"); gainxp(xpl[plv - 1] > xp ? xpl[plv - 1] - xp : 1); break;
    }
    useup(i);
    tick();
}
static void readscr(void)
{
    int8_t i = choose("read what?", O_SCR), j;
    uint8_t s, x, y;
    if (i < 0) return;
    s = inv[i].s;
    sknown |= 1 << s;
    useup(i);
    switch (s) {
    case S_MAP:
        for (y = 0; y < MH; y++) for (x = 0; x < MW; x++) if (map[y][x] != ' ') mem[y][x] = map[y][x];
        msg("this scroll has a map on it"); break;
    case S_IDENT:
        msg("this is a scroll of identify");
        j = choose("identify what?", 0);
        if (j >= 0) {
            if (inv[j].t == O_POT) pknown |= 1 << inv[j].s;
            if (inv[j].t == O_SCR) sknown |= 1 << inv[j].s;
            oname(&inv[j]); mshow();
        }
        break;
    case S_TELE: teleport(); msg("you feel dizzy"); break;
    case S_EWPN:
        if (wield < 0) msg("you feel a strange sense of loss");
        else { inv[wield].e++; msg("your weapon glows blue for a moment"); }
        break;
    case S_EARM:
        if (wear < 0) msg("you feel a strange sense of loss");
        else { inv[wear].e++; msg("your armor glows silver for a moment"); }
        break;
    case S_SLEEP: msg("you fall asleep"); for (x = rn(5) + 4; x && !dead; x--) tick(); break;
    case S_MONST: newmon(1); msg("you hear a faint cry of anguish in the distance"); break;
    }
    tick();
}
static void eat(void)
{
    int8_t i = choose("eat what?", O_FOOD);
    if (i < 0) return;
    useup(i);
    food += 1100 + rn(400);
    if (food > 2000) food = 2000;
    msg(rn(4) ? "yum, that tasted good" : "this food tastes awful");
    tick();
}
static void wieldw(void)
{
    int8_t i = choose("wield what?", O_WPN);
    if (i < 0) return;
    wield = i;
    ms_("you are now wielding "); oname(&inv[i]); mshow();
    tick();
}
static void weara(void)
{
    int8_t i = choose("wear what?", O_ARM);
    if (i < 0) return;
    if (wear >= 0) { msg("you are already wearing some armor; take it off (T) first"); return; }
    wear = i;
    ms_("you are now wearing "); oname(&inv[i]); mshow();
    tick(); tick();
}
static void takeoff(void)
{
    if (wear < 0) { msg("you aren't wearing any armor"); return; }
    ms_("you used to be wearing "); oname(&inv[wear]); mshow();
    wear = -1;
    tick();
}
static void drop(void)
{
    int8_t i;
    obj o;
    if (oat[py][px] || map[py][px] != '.') { msg("there is something there already"); return; }
    if ((i = choose("drop what?", 0)) < 0) return;
    if (i == wear) { msg("you can't, you are wearing it"); return; }
    o = inv[i];
    if (o.t == O_POT || o.t == O_SCR || o.t == O_FOOD) o.n = 1;
    putobj(&o, px, py);
    useup(i);
    ms_("dropped "); oname(&o); mshow();
    tick();
}

/* ---------------------------------------------------------------- moverse */
static const int8_t dxs[] = { -1, 0, 0, 1, -1, 1, -1, 1 };   /* h j k l y u b n */
static const int8_t dys[] = { 0, 1, -1, 0, -1, -1, 1, 1 };
static const char dirs[] = "hjklyubn";
/* un paso; 0 si no se pudo o hay que parar de correr */
static uint8_t step(int8_t dx, int8_t dy)
{
    uint8_t nx, ny, m;
    if (conf && rn(2)) { m = rn(8); dx = dxs[m]; dy = dys[m]; }
    nx = px + dx; ny = py + dy;
    if (nx >= MW || ny >= MH) return 0;
    if ((m = mat[ny][nx])) { attack(m - 1); tick(); return 0; }
    if (!pass(map[ny][nx])) return 0;
    if (dx && dy && (map[py][px] == '+' || map[ny][nx] == '+')) return 0;
    px = nx; py = ny;
    pickup();
    tick();
    return map[py][px] == '.' && !oat[py][px];
}
static uint8_t nearmon(void)     /* hay un monstruo a la vista */
{
    uint8_t i;
    for (i = 0; i < MAXM; i++) if (ms[i].t && seen(ms[i].x, ms[i].y)) return 1;
    return 0;
}
static void help(void)
{
    pstr(CLS);
    pstr("ROGUE - find the Amulet of Yendor (level 13 or deeper) and bring it back up.\n\n"
         "  h j k l y u b n  move (or the arrow keys); in capitals: run\n"
         "  >  go down the stairs        <  go up (only with the Amulet)\n"
         "  i  inventory                 q  quaff a potion\n"
         "  r  read a scroll             e  eat\n"
         "  w  wield a weapon            W  wear armor          T  take armor off\n"
         "  d  drop                      s or .  rest a turn\n"
         "  ^R redraw                    Q  quit\n\n"
         "  @ you   . floor   + door   # passage   > stairs\n"
         "  * gold  ! potion  ? scroll  : food  ) weapon  ] armor  , the Amulet\n"
         "  A-Z monsters: walk into them to fight.\n\n--press space--");
    while (waitkey() != ' ') ;
    redraw();
}
static int keyin(void)           /* una tecla; las flechas como h j k l */
{
    int k = waitkey(), n;
    if (k != 27) return k;
    for (n = 0; n < 200 && !(k = getkey()); n++) ;
    if (k != '[' && k != 'O') return 27;
    for (n = 0; n < 200 && !(k = getkey()); n++) ;
    switch (k) { case 'A': return 'k'; case 'B': return 'j'; case 'C': return 'l'; case 'D': return 'h'; }
    return 0;
}
static void command(void)
{
    int k;
    const char *d;
    uint8_t n;
    draw();
    k = keyin();
    mclear();
    if ((d = strchr(dirs, k)) && k) { step(dxs[d - dirs], dys[d - dirs]); return; }
    if (k >= 'A' && k <= 'Z' && (d = strchr(dirs, k | 32))) {   /* correr */
        for (n = 0; n < 80 && step(dxs[d - dirs], dys[d - dirs]) && !nearmon() && !dead; n++) draw();
        return;
    }
    switch (k) {
    case '>':
        if (map[py][px] != '>') { msg("I see no way down"); return; }
        depth++; if (depth > maxdepth) maxdepth = depth;
        level(); return;
    case '<':
        if (map[py][px] != '>') { msg("I see no way up"); return; }
        if (!hasamu) { msg("your way is magically blocked"); return; }
        if (--depth == 0) { quit = 2; return; }
        level(); msg("you feel a wrenching sensation in your gut"); return;
    case 'i': showinv(0); return;
    case 'q': quaff(); return;
    case 'r': readscr(); return;
    case 'e': eat(); return;
    case 'w': wieldw(); return;
    case 'W': weara(); return;
    case 'T': takeoff(); return;
    case 'd': drop(); return;
    case 's': case '.': tick(); return;
    case '?': help(); return;
    case 18: case 12: redraw(); return;
    case 'Q':
        msg("really quit? (y/n)");
        if ((waitkey() | 32) == 'y') quit = 1;
        mclear();
        return;
    }
    if (k) msg("type ? for help");
}

/* ---------------------------------------------------------------- empezar y terminar */
static void setup(void)
{
    uint8_t i, j, t;
    static obj o;
    {
        uint8_t c[14];               /* 8 de los 14 colores, al azar */
        for (i = 0; i < 14; i++) c[i] = i;
        for (i = 13; i; i--) { j = rn(i + 1); t = c[i]; c[i] = c[j]; c[j] = t; }
        for (i = 0; i < NPOT; i++) pcol[i] = c[i];
    }
    for (i = 0; i < NSCR; i++) {
        stitle[i][0] = 0;
        for (j = rn(2) + 2; j; j--) {
            strcat(stitle[i], syl[rn(16)]);
            if (j > 1) strcat(stitle[i], " ");
        }
    }
    depth = maxdepth = 1; plv = 1; str = maxstr = 16; hp = maxhp = 12; food = 1300;
    o.t = O_FOOD; o.n = 1; o.s = 0; o.e = 0; additem(&o);
    o.t = O_WPN; o.s = 1; o.e = 1; additem(&o); wield = 1;
    o.t = O_ARM; o.s = 1; o.e = 1; additem(&o); wear = 2;
    ml = 0; mb[0] = 0;
}
static void theend(void)
{
    pstr(CLS SHOW);
    if (quit == 2) {
        pf("\n  You escaped the Dungeons of Doom with the Amulet of Yendor\n"
           "  and %u gold pieces, at experience level %u.\n\n  Congratulations!\n\n", gold, plv);
        return;
    }
    pstr("\n\n               __________\n"
         "              /          \\\n"
         "             /    REST    \\\n"
         "            /      IN      \\\n"
         "           /     PEACE      \\\n"
         "          |                  |\n");
    pf("          |   %5u Au       |\n", gold);
    if (dead) {
        uint8_t n = strlen(killer);
        pstr("          |    killed by     |\n          |");
        for (n = (18 - n) / 2 + ((18 - n) & 1); n; n--) putch(' ');
        pstr(killer);
        for (n = (18 - strlen(killer)) / 2; n; n--) putch(' ');
        pstr("|\n");
    }
    else pstr("          |      quit        |\n          |                  |\n");
    pf("          |   on level %3u   |\n", depth);
    pstr("         *|     *  *  *      | *\n"
         " ________)/\\\\_//(\\/(/\\)/\\//\\/|_)_______\n\n");
}
void main(void)
{
    srnd(ticks() ^ 0x5A3C);
    pstr(HIDE);
    setup();
    level();
    msg("Hello, welcome to the Dungeons of Doom. Type ? for help");
    while (!quit && !dead) command();
    if (dead) { draw(); msg("you die..."); waitkey(); }
    theend();
    oflush();
}
