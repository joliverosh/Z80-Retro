/* CHESS - ajedrez contra el computador. Las jugadas se escriben como e2e4 (e7e8n para
   coronar caballo; si no, dama), O-O y O-O-O. Ordenes: new, undo (deshace la ultima
   jugada de cada uno), go (el computador juega con el bando que mueve), level 1-6
   (cuanto piensa), flip (gira el tablero), help, quit.
   Busqueda alfa-beta con profundizacion iterativa y capturas al final; tablero 0x88.
   Los mensajes van en ingles. (C) OLIVEROS 2026 */
/* mk: --max-allocs-per-node 50000 */
#include <string.h>
#include "cpm.h"

/* ---------------------------------------------------------------- el tablero */
enum { EMPTY, PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING };
#define BLACK 8
#define WHITE 0
#define COLOR(p) ((p) & 8)
#define KIND(p) ((p) & 7)
#define OFF(s) ((s) & 0x88)
#define NOSQ 0x7F
uint8_t b[128];                  /* (chess_a.s usa b, pl, np, amask, astep y pbit) */
static uint8_t side;             /* el que mueve: WHITE o BLACK */
static uint8_t castle;           /* 1 O-O blancas, 2 O-O-O blancas, 4 y 8 negras */
static uint8_t ep;               /* casilla de captura al paso, o NOSQ */
static uint8_t kpos[2];          /* donde estan los reyes ([0] blancas, [1] negras) */
static uint8_t half;             /* jugadas desde la ultima captura o peon */

typedef struct { uint8_t f, t, pr; int8_t sc; } move;   /* de, a, coronacion, orden */
typedef struct { uint8_t cap, castle, ep, half, nq; int16_t msc; } undo;

static const int8_t ndir[8] = { 33, 31, 18, 14, -33, -31, -18, -14 };
static const int8_t kdir[8] = { 1, -1, 16, -16, 17, 15, -17, -15 };
static const uint16_t val[7] = { 0, 100, 320, 330, 500, 900, 0 };

/* que castillos se pierden cuando se mueve o se captura en cada casilla */
static uint8_t cmask(uint8_t s)
{
    switch (s) {
    case 0x00: return 2; case 0x07: return 1; case 0x04: return 3;
    case 0x70: return 8; case 0x77: return 4; case 0x74: return 12;
    }
    return 0;
}

static void score(void);
static void setup(void)
{
    static const uint8_t back[8] = { ROOK, KNIGHT, BISHOP, QUEEN, KING, BISHOP, KNIGHT, ROOK };
    uint8_t i;
    memset(b, 0, sizeof b);
    for (i = 0; i < 8; i++) {
        b[i] = back[i]; b[0x10 + i] = PAWN;
        b[0x60 + i] = PAWN | BLACK; b[0x70 + i] = back[i] | BLACK;
    }
    side = WHITE; castle = 15; ep = NOSQ; half = 0;
    kpos[0] = 0x04; kpos[1] = 0x74;
    score();
}

/* ---------------------------------------------------------------- ataques */
/* las piezas de cada bando: sus casillas (pl), cuantas (np) y donde esta cada una en pl */
uint8_t pl[2][16], np[2];
static uint8_t pi[128];
static void pmov(uint8_t c, uint8_t f, uint8_t t) { uint8_t i = pi[f]; pl[c][i] = t; pi[t] = i; }
static void pdel(uint8_t c, uint8_t s)
{
    uint8_t i = pi[s], l = pl[c][--np[c]];
    pl[c][i] = l; pi[l] = i;
}
static void padd(uint8_t c, uint8_t s) { pl[c][np[c]] = s; pi[s] = np[c]++; }

/* que piezas pueden atacar a la distancia s - f (+ 119), y el paso para las que se
   deslizan: 1 peon blanco, 2 peon negro, 4 caballo, 8 alfil, 16 torre, 32 dama, 64 rey */
uint8_t amask[239];
int8_t astep[239];
const uint8_t pbit[16] = { 0, 1, 4, 8, 16, 32, 64, 0, 0, 2, 4, 8, 16, 32, 64, 0 };
static void tables(void)
{
    uint8_t i, n;
    int8_t d;
    for (i = 0; i < 8; i++) {
        amask[119 + ndir[i]] |= 4;
        amask[119 + kdir[i]] |= 64;
        d = kdir[i];
        for (n = 1; n < 8; n++) {
            amask[119 + n * d] |= i < 4 ? 16 | 32 : 8 | 32;
            astep[119 + n * d] = d;
        }
    }
    amask[119 + 15] |= 1; amask[119 + 17] |= 1;
    amask[119 - 15] |= 2; amask[119 - 17] |= 2;
}
uint8_t attacked(uint8_t s, uint8_t by);   /* by ataca la casilla s (chess_a.s) */
static uint8_t incheck(uint8_t c) { return attacked(kpos[c >> 3], c ^ BLACK); }

/* ---------------------------------------------------------------- jugadas */
#define MAXMV 2400
static move mv[MAXMV];           /* las listas de todas las profundidades */
static move *mvp;                /* el primero libre */
static uint8_t caponly;          /* solo capturas (y coronaciones) */
static void add(uint8_t f, uint8_t t, uint8_t pr)
{
    static int8_t sc;
    if (mvp >= mv + MAXMV) return;
    if (b[t]) sc = 10 * KIND(b[t]) - KIND(b[f]) + 60;    /* la mas valiosa con la menos valiosa */
    else if (pr) sc = 50;
    else if (t == ep && KIND(b[f]) == PAWN) sc = 69;
    else { if (caponly) return; sc = 0; }
    mvp->f = f; mvp->t = t; mvp->pr = pr; mvp->sc = sc;
    mvp++;
}
static void addp(uint8_t f, uint8_t t)   /* de peon: con coronacion */
{
    if ((t >> 4) == 7 || (t >> 4) == 0) { add(f, t, QUEEN); if (!caponly) { add(f, t, KNIGHT); add(f, t, ROOK); add(f, t, BISHOP); } }
    else add(f, t, 0);
}
static void gen(void)
{
    static uint8_t s, p, k, t, i, j, them, fwd, r2;
    static int8_t d;
    them = side ^ BLACK;
    for (j = 0; j < np[side >> 3]; j++) {
        s = pl[side >> 3][j];
        p = b[s];
        k = KIND(p);
        if (k == PAWN) {
            if (side == WHITE) { fwd = 16; r2 = 1; } else { fwd = -16; r2 = 6; }
            t = s + fwd;
            if (!b[t]) {
                addp(s, t);
                if ((s >> 4) == r2 && !caponly) { t += fwd; if (!b[t]) add(s, t, 0); }
            }
            t = s + fwd - 1; if (!OFF(t) && ((b[t] && COLOR(b[t]) == them) || t == ep)) addp(s, t);
            t = s + fwd + 1; if (!OFF(t) && ((b[t] && COLOR(b[t]) == them) || t == ep)) addp(s, t);
        } else if (k == KNIGHT || k == KING) {
            for (i = 0; i < 8; i++) {
                t = s + (k == KNIGHT ? ndir[i] : kdir[i]);
                if (!OFF(t) && (!b[t] || COLOR(b[t]) == them)) add(s, t, 0);
            }
            if (k == KING && !caponly) {   /* los castillos */
                if (side == WHITE && s == 0x04) {
                    if (castle & 1 && !b[5] && !b[6] && !attacked(4, BLACK) && !attacked(5, BLACK) && !attacked(6, BLACK)) add(4, 6, 0);
                    if (castle & 2 && !b[3] && !b[2] && !b[1] && !attacked(4, BLACK) && !attacked(3, BLACK) && !attacked(2, BLACK)) add(4, 2, 0);
                } else if (side == BLACK && s == 0x74) {
                    if (castle & 4 && !b[0x75] && !b[0x76] && !attacked(0x74, WHITE) && !attacked(0x75, WHITE) && !attacked(0x76, WHITE)) add(0x74, 0x76, 0);
                    if (castle & 8 && !b[0x73] && !b[0x72] && !b[0x71] && !attacked(0x74, WHITE) && !attacked(0x73, WHITE) && !attacked(0x72, WHITE)) add(0x74, 0x72, 0);
                }
            }
        } else {
            for (i = k == BISHOP ? 4 : 0; i < (k == ROOK ? 4 : 8); i++) {
                d = kdir[i];
                for (t = s + d; !OFF(t); t += d) {
                    if (b[t]) { if (COLOR(b[t]) == them) add(s, t, 0); break; }
                    if (!caponly) add(s, t, 0);
                }
            }
        }
    }
}
/* ---------------------------------------------------------------- evaluacion */
/* desde las blancas, la fila 1 primero (a1..h1) */
static const int8_t pst_p[64] = {
     0,  0,  0,  0,  0,  0,  0,  0,   5, 10, 10,-20,-20, 10, 10,  5,
     5, -5,-10,  0,  0,-10, -5,  5,   0,  0,  0, 20, 20,  0,  0,  0,
     5,  5, 10, 25, 25, 10,  5,  5,  10, 10, 20, 30, 30, 20, 10, 10,
    50, 50, 50, 50, 50, 50, 50, 50,   0,  0,  0,  0,  0,  0,  0,  0 };
static const int8_t pst_n[64] = {
   -50,-40,-30,-30,-30,-30,-40,-50, -40,-20,  0,  5,  5,  0,-20,-40,
   -30,  5, 10, 15, 15, 10,  5,-30, -30,  0, 15, 20, 20, 15,  0,-30,
   -30,  5, 15, 20, 20, 15,  5,-30, -30,  0, 10, 15, 15, 10,  0,-30,
   -40,-20,  0,  0,  0,  0,-20,-40, -50,-40,-30,-30,-30,-30,-40,-50 };
static const int8_t pst_b[64] = {
   -20,-10,-10,-10,-10,-10,-10,-20, -10,  5,  0,  0,  0,  0,  5,-10,
   -10, 10, 10, 10, 10, 10, 10,-10, -10,  0, 10, 10, 10, 10,  0,-10,
   -10,  5,  5, 10, 10,  5,  5,-10, -10,  0,  5, 10, 10,  5,  0,-10,
   -10,  0,  0,  0,  0,  0,  0,-10, -20,-10,-10,-10,-10,-10,-10,-20 };
static const int8_t pst_r[64] = {
     0,  0,  0,  5,  5,  0,  0,  0,  -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,  -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,  -5,  0,  0,  0,  0,  0,  0, -5,
     5, 10, 10, 10, 10, 10, 10,  5,   0,  0,  0,  0,  0,  0,  0,  0 };
static const int8_t pst_k[64] = {     /* con damas en el tablero */
    20, 30, 10,  0,  0, 10, 30, 20,  20, 20,  0,  0,  0,  0, 20, 20,
   -10,-20,-20,-20,-20,-20,-20,-10, -20,-30,-30,-40,-40,-30,-30,-20,
   -30,-40,-40,-50,-50,-40,-40,-30, -30,-40,-40,-50,-50,-40,-40,-30,
   -30,-40,-40,-50,-50,-40,-40,-30, -30,-40,-40,-50,-50,-40,-40,-30 };
static const int8_t pst_ke[64] = {    /* al final */
   -50,-30,-30,-30,-30,-30,-30,-50, -30,-30,  0,  0,  0,  0,-30,-30,
   -30,-10, 20, 30, 30, 20,-10,-30, -30,-10, 30, 40, 40, 30,-10,-30,
   -30,-10, 30, 40, 40, 30,-10,-30, -30,-10, 20, 30, 30, 20,-10,-30,
   -30,-20,-10,  0,  0,-10,-20,-30, -50,-40,-30,-20,-20,-30,-40,-50 };
/* lo que vale la pieza p en s (positivo para las blancas); los reyes van aparte */
static int16_t pv(uint8_t p, uint8_t s)
{
    uint8_t i = (s >> 4) * 8 + (s & 7);
    int16_t v;
    if (COLOR(p)) i ^= 56;               /* las negras se miran desde su lado */
    v = val[KIND(p)];
    switch (KIND(p)) {
    case PAWN: v += pst_p[i]; break;
    case KNIGHT: v += pst_n[i]; break;
    case BISHOP: v += pst_b[i]; break;
    case ROOK: v += pst_r[i]; break;
    case KING: return 0;
    }
    return COLOR(p) ? -v : v;
}
static int16_t msc;              /* la suma de pv de todo el tablero */
static uint8_t nq;               /* damas en el tablero */
static void score(void)
{
    uint8_t s;
    msc = 0; nq = 0; np[0] = np[1] = 0;
    if (!amask[119 + 1]) tables();
    for (s = 0; s < 128; s++) {
        if (OFF(s)) { s += 7; continue; }
        if (b[s]) { msc += pv(b[s], s); if (KIND(b[s]) == QUEEN) nq++; padd(COLOR(b[s]) >> 3, s); }
    }
}
static int16_t eval(void)        /* para el que mueve */
{
    static int16_t sc;
    static uint8_t w, k;
    const int8_t *t = nq ? pst_k : pst_ke;
    w = kpos[0]; k = kpos[1];
    sc = msc + t[(w >> 4) * 8 + (w & 7)] - t[((k >> 4) * 8 + (k & 7)) ^ 56];
    return side == WHITE ? sc : -sc;
}

static void make(move *m, undo *u)
{
    uint8_t f = m->f, t = m->t, p = b[f], c = side >> 3;
    u->cap = b[t]; u->castle = castle; u->ep = ep; u->half = half; u->msc = msc; u->nq = nq;
    half++;
    msc -= pv(p, f);
    if (b[t]) { msc -= pv(b[t], t); if (KIND(b[t]) == QUEEN) nq--; pdel(c ^ 1, t); }
    if (KIND(p) == PAWN) {
        half = 0;
        if (t == ep) {                   /* al paso */
            uint8_t e = side == WHITE ? t - 16 : t + 16;
            u->cap = 0x80; msc -= pv(b[e], e); b[e] = 0; pdel(c ^ 1, e);
        }
        if (m->pr) { p = m->pr | side; if (m->pr == QUEEN) nq++; }
    }
    pmov(c, f, t);
    msc += pv(p, t);
    if (u->cap) half = 0;
    ep = NOSQ;
    if (KIND(p) == PAWN && (t - f == 32 || f - t == 32)) ep = (f + t) >> 1;
    if (KIND(p) == KING) {
        kpos[side >> 3] = t;
        if (t - f == 2) { msc += pv(b[f + 3], f + 1) - pv(b[f + 3], f + 3); b[f + 1] = b[f + 3]; b[f + 3] = 0; pmov(c, f + 3, f + 1); }   /* O-O */
        else if (f - t == 2) { msc += pv(b[f - 4], f - 1) - pv(b[f - 4], f - 4); b[f - 1] = b[f - 4]; b[f - 4] = 0; pmov(c, f - 4, f - 1); }   /* O-O-O */
    }
    castle &= ~(cmask(f) | cmask(t));
    b[t] = p; b[f] = 0;
    side ^= BLACK;
}
static void unmake(move *m, undo *u)
{
    uint8_t f = m->f, t = m->t, p = b[t], c;
    side ^= BLACK;
    c = side >> 3;
    if (m->pr) p = PAWN | side;
    b[f] = p;
    pmov(c, t, f);
    if (u->cap == 0x80) {
        uint8_t e = side == WHITE ? t - 16 : t + 16;
        b[t] = 0; b[e] = PAWN | (side ^ BLACK); padd(c ^ 1, e);
    } else if ((b[t] = u->cap)) padd(c ^ 1, t);
    if (KIND(p) == KING) {
        kpos[c] = f;
        if (t - f == 2) { b[f + 3] = b[f + 1]; b[f + 1] = 0; pmov(c, f + 1, f + 3); }
        else if (f - t == 2) { b[f - 4] = b[f - 1]; b[f - 1] = 0; pmov(c, f - 1, f - 4); }
    }
    castle = u->castle; ep = u->ep; half = u->half; msc = u->msc; nq = u->nq;
}

/* ---------------------------------------------------------------- busqueda */
#define MATE 30000
static uint32_t nodes;
static uint16_t tstart, tlimit;
static uint8_t stop, maxd, vary;
static move best, rootbest;
static void pick(move *a, move *e)   /* la de mejor orden, a la cabeza */
{
    static move *m, *bm, tmp;
    bm = a;
    for (m = a + 1; m < e; m++) if (m->sc > bm->sc) bm = m;
    if (bm != a) { tmp = *a; *a = *bm; *bm = tmp; }
}
static void tcheck(void)        /* (cada 256 posiciones: llamar al sistema cuesta) */
{
    if ((uint16_t)(ticks() - tstart) >= tlimit) stop = 1;
    if (!((uint8_t)(nodes >> 8) & 3) && getkey() == 27) stop = 1;
}
/* hay que ver si la jugada deja al rey en jaque: si se estaba en jaque, si mueve el rey,
   si es al paso o si sale de una linea con el rey (podria estar clavada) */
static uint8_t risky(move *m, uint8_t chk)
{
    static uint8_t f, k;
    static int8_t dx, dy;
    f = m->f;
    if (chk || KIND(b[f]) == KING || (KIND(b[f]) == PAWN && m->t == ep)) return 1;
    k = kpos[side >> 3];
    dx = (f & 7) - (k & 7); dy = (f >> 4) - (k >> 4);
    return !dx || !dy || dx == dy || dx == -dy;
}
static int16_t quiesce(int16_t alpha, int16_t beta)
{
    move *a, *e, *m;
    undo u;
    int16_t s;
    uint8_t chk, r;
    if (!((uint8_t)++nodes)) tcheck();
    if (stop) return 0;
    chk = incheck(side);
    s = eval();
    if (s >= beta) return s;
    if (s > alpha) alpha = s;
    a = mvp; caponly = 1; gen(); caponly = 0; e = mvp;
    for (m = a; m < e; m++) {
        pick(m, e);
        r = risky(m, chk);
        make(m, &u);
        if (r && incheck(side ^ BLACK)) { unmake(m, &u); continue; }
        s = -quiesce(-beta, -alpha);
        unmake(m, &u);
        if (stop) break;
        if (s > alpha) { alpha = s; if (s >= beta) break; }
    }
    mvp = a;
    return alpha;
}
static int16_t search(uint8_t depth, int16_t alpha, int16_t beta, uint8_t ply)
{
    move *a, *e, *m;
    undo u;
    int16_t s;
    uint8_t legal = 0, chk, r;
    if (!((uint8_t)++nodes)) tcheck();
    if (stop) return 0;
    chk = incheck(side);
    if (chk) depth++;                    /* en jaque: un poco mas */
    if (!depth) return quiesce(alpha, beta);
    if (ply && half >= 100) return 0;
    a = mvp; gen(); e = mvp;
    if (!ply)                            /* la mejor de la vuelta anterior, primero */
        for (m = a; m < e; m++) if (m->f == rootbest.f && m->t == rootbest.t && m->pr == rootbest.pr) m->sc = 127;
    for (m = a; m < e; m++) {
        pick(m, e);
        r = risky(m, chk);
        make(m, &u);
        if (r && incheck(side ^ BLACK)) { unmake(m, &u); continue; }
        legal++;
        s = -search(depth - 1, -beta, -alpha, ply + 1);
        if (!ply && vary) s += rnd() % vary;     /* en la apertura: no siempre lo mismo */
        unmake(m, &u);
        if (stop) break;
        if (s > alpha) {
            alpha = s;
            if (!ply) best = *m;
            if (s >= beta) break;
        }
    }
    mvp = a;
    if (!legal && !stop) return chk ? -MATE + ply : 0;
    return alpha;
}
static int16_t lastsc;
static uint8_t lastd;
static uint8_t think(move *out)  /* la jugada del computador; 0 si no hay */
{
    uint8_t d;
    int16_t s;
    nodes = 0; stop = 0; tstart = ticks();
    rootbest.f = NOSQ;
    out->f = NOSQ;
    for (d = 1; d <= maxd; d++) {
        best.f = NOSQ;
        mvp = mv;
        s = search(d, -MATE - 1, MATE + 1, 0);
        if (stop && d > 1) break;
        if (best.f != NOSQ) { *out = best; rootbest = best; lastsc = s; lastd = d; }
        if (s > MATE - 100 || s < -MATE + 100) break;   /* mate a la vista */
        if ((uint16_t)(ticks() - tstart) > tlimit / 2) break;   /* no alcanzaria otra vuelta */
    }
    return out->f != NOSQ;
}

/* ---------------------------------------------------------------- legales */
static uint8_t legal(move *list)  /* las jugadas legales en list; cuantas */
{
    move *a, *e, *m;
    undo u;
    uint8_t n = 0;
    mvp = mv; a = mvp; gen(); e = mvp;
    for (m = a; m < e; m++) {
        make(m, &u);
        if (!incheck(side ^ BLACK)) list[n++] = *m;
        unmake(m, &u);
    }
    mvp = mv;
    return n;
}

/* ---------------------------------------------------------------- pantalla */
#define HMAX 400
static move hm[HMAX];            /* las jugadas de la partida */
static undo hu[HMAX];
static uint8_t hpc[HMAX];        /* la pieza que se movio (para escribirla) */
static uint16_t nh;
static uint8_t flip, comp = BLACK, level = 3;
static char line[40];
static const char pc[] = " PNBRQK";
static const uint16_t lsec[7] = { 0, 1, 3, 8, 20, 45, 90 };   /* segundos por nivel */
static const uint8_t ldep[7] = { 0, 2, 3, 20, 20, 20, 20 };

static void sqname(char *o, uint8_t s) { o[0] = 'a' + (s & 7); o[1] = '1' + (s >> 4); o[2] = 0; }
static void mvtext(char *o, uint16_t i)   /* la jugada i de la partida */
{
    move *m = &hm[i];
    uint8_t k = KIND(hpc[i]);
    if (k == KING && (m->t - m->f == 2)) { strcpy(o, "O-O"); return; }
    if (k == KING && (m->f - m->t == 2)) { strcpy(o, "O-O-O"); return; }
    *o = k == PAWN ? ' ' : pc[k];
    sqname(o + 1, m->f);
    o[3] = hu[i].cap ? 'x' : '-';
    sqname(o + 4, m->t);
    if (m->pr) { o[6] = '='; o[7] = pc[m->pr]; o[8] = 0; }
}
static void drawboard(void)
{
    uint8_t r, c, s, p, rr, cc;
    for (rr = 0; rr < 8; rr++) {
        r = flip ? rr : 7 - rr;
        for (cc = 0; cc < 2; cc++) {
            gotoxy(2, 3 + rr * 2 + cc);
            if (!cc) putch('1' + r); else putch(' ');
            putch(' ');
            for (c = 0; c < 8; c++) {
                s = r * 16 + (flip ? 7 - c : c);
                p = b[s];
                pstr((r + (s & 7)) & 1 ? ESC "[43m" : ESC "[42m");
                if (cc || !p) pstr("     ");
                else {
                    pstr(COLOR(p) ? "  " ESC "[30m" : "  " ESC "[1;37m");
                    putch(COLOR(p) ? pc[KIND(p)] | 32 : pc[KIND(p)]);
                    pstr(ESC "[22;39m  ");
                }
            }
            pstr(ESC "[0m");
        }
    }
    gotoxy(4, 19);
    for (c = 0; c < 8; c++) { pstr("  "); putch('a' + (flip ? 7 - c : c)); pstr("  "); }
}
static void drawinfo(void)
{
    uint16_t i, f;
    uint8_t r;
    char t[12];
    gotoxy(48, 2); pstr("C H E S S   (C) OLIVEROS 2026");
    gotoxy(48, 3); pf("Level %u: up to %u s a move" ESC "[K", level, lsec[level]);
    gotoxy(48, 4); pf("You play %s" ESC "[K", comp == BLACK ? "white" : comp == WHITE ? "black" : "both sides");
    f = nh > 26 ? (nh - 25) & ~1 : 0;    /* las ultimas jugadas, de a dos */
    for (r = 0, i = f; r < 13; r++, i += 2) {
        gotoxy(48, 6 + r); pstr(ESC "[K");
        if (i >= nh) continue;
        pf("%3u.", i / 2 + 1);
        mvtext(t, i); pstr(t);
        if (i + 1 < nh) { gotoxy(64, 6 + r); mvtext(t, i + 1); pstr(t); }
    }
}
static void say(const char *s) { gotoxy(1, 21); pstr(s); pstr(ESC "[K"); }
static void drawall(void)
{
    pstr(CLS);
    drawboard(); drawinfo();
}

/* ---------------------------------------------------------------- partida */
static void play(move *m)
{
    if (nh >= HMAX) return;
    hpc[nh] = b[m->f];
    hm[nh] = *m;
    make(m, &hu[nh]);
    nh++;
}
static void takeback(void)
{
    if (!nh) return;
    nh--;
    unmake(&hm[nh], &hu[nh]);
}
static uint8_t over(void)        /* dice si termino la partida */
{
    static move l[120];
    if (!legal(l)) {
        if (incheck(side)) say(side == WHITE ? "Checkmate: black wins." : "Checkmate: white wins.");
        else say("Stalemate: a draw.");
        return 1;
    }
    if (half >= 100) { say("Fifty moves without a capture or a pawn move: a draw."); return 1; }
    {                                    /* reyes solos, o con un caballo o un alfil */
        uint8_t s, n = 0, minor = 0;
        for (s = 0; s < 128; s++) {
            if (OFF(s)) { s += 7; continue; }
            if (b[s] && KIND(b[s]) != KING) { n++; if (KIND(b[s]) == KNIGHT || KIND(b[s]) == BISHOP) minor++; }
        }
        if (!n || (n == 1 && minor)) { say("Not enough pieces left to mate: a draw."); return 1; }
    }
    if (incheck(side)) say("Check!");
    return 0;
}
static uint8_t parse(char *s, move *out)   /* la jugada escrita, si es legal */
{
    static move l[120];
    uint8_t n, i, f, t, pr = 0, k;
    for (i = 0; s[i]; i++) if (s[i] >= 'A' && s[i] <= 'Z' && s[i] != 'O') s[i] |= 32;
    n = legal(l);
    if (s[0] == 'O' || s[0] == '0') {    /* O-O, O-O-O */
        k = kpos[side >> 3];
        t = strlen(s) >= 5 ? k - 2 : k + 2;
        for (i = 0; i < n; i++) if (l[i].f == k && l[i].t == t && KIND(b[k]) == KING) { *out = l[i]; return 1; }
        return 0;
    }
    if (s[0] < 'a' || s[0] > 'h' || s[1] < '1' || s[1] > '8') return 0;
    i = 2; if (s[i] == '-' || s[i] == 'x') i++;
    if (s[i] < 'a' || s[i] > 'h' || s[i + 1] < '1' || s[i + 1] > '8') return 0;
    f = (s[1] - '1') * 16 + s[0] - 'a';
    t = (s[i + 1] - '1') * 16 + s[i] - 'a';
    switch (s[i + 2] == '=' ? s[i + 3] : s[i + 2]) {
    case 'n': pr = KNIGHT; break; case 'b': pr = BISHOP; break; case 'r': pr = ROOK; break;
    default: pr = QUEEN;
    }
    for (k = 0; k < n; k++)
        if (l[k].f == f && l[k].t == t && (!l[k].pr || l[k].pr == pr)) { *out = l[k]; return 1; }
    return 0;
}
static void getline(void)
{
    uint8_t n = 0;
    int k;
    gotoxy(1, 22); pstr(side == WHITE ? "White" : "Black"); pstr(" to move: " ESC "[K" SHOW);
    for (;;) {
        k = waitkey();
        if (k == 13 || k == 10) break;
        if ((k == 8 || k == 127) && n) { n--; pstr("\b \b"); continue; }
        if (k >= ' ' && k < 127 && n < sizeof line - 1) { line[n++] = k; putch(k); }
    }
    line[n] = 0;
    pstr(HIDE);
}
static uint32_t perft(uint8_t d)   /* (prueba: cuantas posiciones hay a d jugadas) */
{
    move *a, *e, *m;
    undo u;
    uint32_t n = 0;
    if (!d) return 1;
    a = mvp; gen(); e = mvp;
    for (m = a; m < e; m++) {
        make(m, &u);
        if (!incheck(side ^ BLACK)) n += perft(d - 1);
        unmake(m, &u);
    }
    mvp = a;
    return n;
}
static void help(void)
{
    pstr(CLS);
    pstr("CHESS\n\n"
         "  Type your move with the squares: e2e4 (or e2-e4, e4xd5). To promote to\n"
         "  something other than a queen add the piece: e7e8n. Castle with O-O or O-O-O.\n\n"
         "  new        a new game (you play white)\n"
         "  undo       take back your last move (and the computer's)\n"
         "  go         the computer plays the side to move (you take the other)\n"
         "  both       you play both sides; go again to let the computer play\n"
         "  level N    how long the computer thinks: 1 (1 s) to 6 (90 s)\n"
         "  flip       turn the board around\n"
         "  quit       leave\n\n"
         "  ESC while the computer thinks makes it move with what it has found.\n"
         "  White pieces are capitals, black pieces small letters.\n\n--press a key--");
    waitkey();
}
void main(void)
{
    static move m;
    static uint8_t done, n;
    static char t[12];
    srnd(ticks());
    pstr(HIDE);
    setup();
    nh = 0; done = 0;
    drawall();
    say("Type help for the commands.");
    for (;;) {
        if (!done && side == comp) {
            say("Thinking...");
            maxd = ldep[level]; tlimit = lsec[level] * tps();
            vary = nh < 12 ? 8 : 0;
            if (think(&m)) {
                play(&m);
                drawboard(); drawinfo();
                mvtext(t, nh - 1);
                gotoxy(1, 21); pstr("My move: "); pstr(t);
                if (lastsc > MATE - 100) pstr("  (I see mate)");
                pf("   [depth %u, %lu positions]" ESC "[K", lastd, nodes);
                done = over();
            } else done = over();    /* (no tenia jugada: ya habia terminado) */
            continue;
        }
        getline();
        n = strlen(line);
        if (!n) continue;
        if (!strcmp(line, "quit") || !strcmp(line, "q")) break;
        else if (!strcmp(line, "help") || line[0] == '?') { help(); drawall(); }
        else if (!strcmp(line, "new")) { setup(); nh = 0; done = 0; comp = BLACK; drawall(); say(""); }
        else if (!strncmp(line, "perft", 5)) { mvp = mv; gotoxy(1, 21); pf("perft: %lu" ESC "[K", perft(line[n - 1] - '0')); }
        else if (!strcmp(line, "flip")) { flip ^= 1; drawboard(); }
        else if (!strcmp(line, "undo")) {
            takeback();
            if (comp != 0xFF && side == comp) takeback();
            done = 0; drawboard(); drawinfo(); say("");
        } else if (!strcmp(line, "go")) { comp = side; drawinfo(); }
        else if (!strcmp(line, "both")) { comp = 0xFF; drawinfo(); say(""); }
        else if (!strncmp(line, "level", 5)) {
            n = line[n - 1] - '0';
            if (n >= 1 && n <= 6) level = n;
            drawinfo(); say("");
        } else if (done) say("The game is over: type new (or undo).");
        else if (parse(line, &m)) { play(&m); drawboard(); drawinfo(); say(""); done = over(); }
        else say("That is not a legal move (help shows how to write them).");
    }
    pstr(CLS SHOW);
    oflush();
}
