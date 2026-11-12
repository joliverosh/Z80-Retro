/* NAVAL - la batalla naval: contra otra persona en otra consola de MP/M II (las dos
   corren NAVAL; el primero espera y el segundo se une) o contra el computador.
   Cada uno tiene 5 barcos (5, 4, 3, 3 y 2 casillas) en un mar de 10 x 10; se dispara
   por turnos y gana el que hunde la flota del otro. Mensajes en ingles.
   NAVAL      espera a alguien (C: jugar contra el computador)
   NAVAL C    contra el computador de una vez
   (C) OLIVEROS 2026 */
#include <string.h>
#include "cpm.h"
#include "duel.h"

#define N 10
#define NS 5
#define INV ESC "[7m"
#define NORM ESC "[0m"
#define EOL ESC "[K"
enum { K_UP = 0x81, K_DOWN, K_RIGHT, K_LEFT };

typedef struct { uint8_t x, y, d, len, hits; } ship;
static const uint8_t slen[NS] = { 5, 4, 3, 3, 2 };
static const char *const sname[NS] = { "carrier", "battleship", "cruiser", "submarine", "destroyer" };

static uint8_t own[N][N];        /* mi mar: barco + 1 (0 agua); 0x10 si le dispararon */
static ship ships[NS];
static uint8_t enemy[N][N];      /* lo que se del otro: 0 nada, 1 agua, 2 tocado, 3 hundido */
static ship eships[NS];          /* sus barcos hundidos (los que se conocen) */
static uint8_t esunk;            /* cuantos le hundi */
static uint8_t comp;             /* contra el computador */
static uint8_t cown[N][N];       /* el mar del computador */
static ship cships[NS];
static uint8_t cseen[N][N];      /* lo que sabe el computador del mio: como enemy */
static uint8_t cx, cy;           /* el cursor en el mar del otro */
static uint8_t mbuf[DLEN];
static uint8_t gone;             /* el otro se fue */
static uint8_t myshots, myhits;
static uint8_t peerready;

/* ---------------------------------------------------------------- teclado */
static uint8_t peermsg(void);
static int keyin(void)          /* (mientras no se teclea, atiende lo que mande el otro) */
{
    int k, n;
    while (!(k = getkey())) { if (peermsg()) return 0; delay(8); }
    if (k != 27) return k;
    for (n = 0; n < 300 && !(k = getkey()); n++) ;
    if (k != '[' && k != 'O') return 27;
    for (n = 0; n < 300 && !(k = getkey()); n++) ;
    switch (k) { case 'A': return K_UP; case 'B': return K_DOWN; case 'C': return K_RIGHT; case 'D': return K_LEFT; }
    return 0;
}

/* ---------------------------------------------------------------- flotas */
static uint8_t fits(uint8_t b[N][N], uint8_t x, uint8_t y, uint8_t d, uint8_t l)
{
    uint8_t i, xx, yy;
    int8_t a, c;
    for (i = 0; i < l; i++) {
        xx = d ? x : x + i; yy = d ? y + i : y;
        if (xx >= N || yy >= N) return 0;
        for (a = -1; a <= 1; a++) for (c = -1; c <= 1; c++)   /* sin tocarse */
            if ((uint8_t)(xx + a) < N && (uint8_t)(yy + c) < N && b[yy + c][xx + a]) return 0;
    }
    return 1;
}
static void place(uint8_t b[N][N], ship *s)
{
    uint8_t k, i, x, y, d;
    memset(b, 0, N * N);
    for (k = 0; k < NS; k++) {
        do { d = rnd() & 1; x = rnd() % N; y = rnd() % N; } while (!fits(b, x, y, d, slen[k]));
        s[k].x = x; s[k].y = y; s[k].d = d; s[k].len = slen[k]; s[k].hits = 0;
        for (i = 0; i < slen[k]; i++) b[d ? y + i : y][d ? x : x + i] = k + 1;
    }
}
/* un disparo a b: 0 agua, 1 tocado, 2 hundido, 3 hundido y era el ultimo; *k el barco */
static uint8_t resolve(uint8_t b[N][N], ship *s, uint8_t x, uint8_t y, uint8_t *k)
{
    uint8_t c = b[y][x], i, left = 0;
    b[y][x] |= 0x10;
    if (!(c & 7) || (c & 0x10)) return 0;
    *k = (c & 7) - 1;
    if (++s[*k].hits < s[*k].len) return 1;
    for (i = 0; i < NS; i++) if (s[i].hits < s[i].len) left++;
    return left ? 2 : 3;
}
static void marksunk(uint8_t v[N][N], ship *s)
{
    uint8_t i;
    for (i = 0; i < s->len; i++) v[s->d ? s->y + i : s->y][s->d ? s->x : s->x + i] = 3;
}

/* ---------------------------------------------------------------- pantalla */
#define GX0 5                    /* columna de mi mar */
#define GX1 45                   /* del otro */
#define GY 4                     /* fila de la primera linea */
static void cell(uint8_t g, uint8_t x, uint8_t y)
{
    uint8_t v;
    gotoxy((g ? GX1 : GX0) + 3 + x * 3, GY + 1 + y);
    if (g && x == cx && y == cy) pstr(INV);
    if (!g) {
        v = own[y][x];
        if ((v & 7) && (v & 0x10)) pstr(ESC "[1;31m X ");
        else if (v & 7) pstr(ESC "[1m # ");
        else if (v & 0x10) pstr(ESC "[36m o ");
        else pstr(ESC "[34m . ");
    } else switch (enemy[y][x]) {
        case 1: pstr(ESC "[36m o "); break;
        case 2: pstr(ESC "[1;31m X "); break;
        case 3: pstr(ESC "[1;33m # "); break;
        default: pstr(ESC "[34m . ");
    }
    pstr(NORM);
}
static void grid(uint8_t g)
{
    uint8_t x, y, gx = g ? GX1 : GX0;
    gotoxy(gx, GY - 1);
    pstr(g ? (comp ? "THE COMPUTER'S SEA" : "THE OTHER PLAYER'S SEA") : "YOUR FLEET");
    gotoxy(gx, GY);
    pstr("   ");
    for (x = 0; x < N; x++) { putch(' '); putch('A' + x); putch(' '); }
    for (y = 0; y < N; y++) {
        gotoxy(gx, GY + 1 + y); pf("%2u ", y + 1);
        for (x = 0; x < N; x++) cell(g, x, y);
    }
}
static void pad(const char *s) { uint8_t n = 0; while (*s) { putch(*s++); n++; } while (n++ < 11) putch(' '); }
static void fleets(void)        /* lo que queda de cada flota */
{
    uint8_t k, i;
    for (k = 0; k < NS; k++) {
        gotoxy(GX0, GY + 11 + k);
        pad(sname[k]);
        for (i = 0; i < slen[k]; i++) pstr(i < ships[k].hits ? ESC "[31mX" NORM : "#");
        pstr(ships[k].hits >= slen[k] ? "  sunk" EOL : EOL);
        gotoxy(GX1, GY + 11 + k);
        pad(sname[k]);
        for (i = 0; i < slen[k]; i++) putch('#');
        pstr(eships[k].len ? "  sunk" EOL : EOL);
    }
}
static void say(const char *s) { gotoxy(1, 21); pstr(s); pstr(EOL); }   /* 20: los disparos */
static void say2(const char *s) { gotoxy(1, 22); pstr(s); pstr(EOL); }
static void keys(const char *s) { gotoxy(1, 23); pstr(INV); pstr(s); pstr(NORM EOL); }
static void drawall(void)
{
    pstr(CLS HIDE);
    gotoxy(1, 1);
    pstr(INV " N A V A L  -  battleship                                     (C) OLIVEROS 2026 " NORM);
    grid(0); grid(1); fleets();
}
static void stats(void)
{
    gotoxy(GX1, 2);
    if (myshots) pf("shots %u, hits %u (%u%%)" EOL, myshots, myhits, myhits * 100 / myshots);
}

/* ---------------------------------------------------------------- con el otro */
static void chat(void)
{
    char t[61];
    uint8_t n = 0;
    int k;
    say2("Message: " SHOW);
    for (;;) {
        k = waitkey();
        if (k == 27) { n = 0; break; }
        if (k == 13 || k == 10) break;
        if ((k == 8 || k == 127) && n) { n--; pstr("\b \b"); continue; }
        if (k >= ' ' && k < 127 && n < 60) { t[n++] = k; putch(k); }
    }
    t[n] = 0;
    pstr(HIDE);
    say2("");
    if (n) { if (dsend('T', t, n + 1)) gone = 1; else { gotoxy(1, 22); pf("You said: %s" EOL, t); } }
}
static uint8_t quitask(void)
{
    int k;
    say2("Leave the game? (Y/N)");
    k = waitkey() | 32;
    say2("");
    if (k != 'y') return 0;
    if (!comp) dsend('Q', 0, 0);
    gone = 2;
    return 1;
}
/* la charla y el adios; 1 si el otro se fue */
static uint8_t peermsg(void)
{
    uint8_t t;
    if (comp || gone) return gone;
    if (!dqn && dpoll()) return 0;
    if (!dqn || (dq[0][0] != 'T' && dq[0][0] != 'Q')) return 0;
    t = drecv(mbuf);
    if (t == 'T') { gotoxy(1, 22); pf(INV " They say: " NORM " %s" EOL, (char *)mbuf); }
    else { say("The other player left the game."); gone = 1; }
    return gone;
}
/* espera un mensaje del tipo want (atiende la charla y las teclas); 0 si se acabo */
static uint8_t waitfor(uint8_t want)
{
    uint8_t t;
    int k;
    for (;;) {
        if (gone) return 0;
        t = drecv(mbuf);
        if (t == want) return t;
        if (t == 'T') { gotoxy(1, 22); pf(INV " They say: " NORM " %s" EOL, (char *)mbuf); }
        else if (t == 'Q') { say("The other player left the game."); gone = 1; return 0; }
        else if (!t) {
            k = getkey();
            if (k == 't' || k == 'T') chat();
            else if (k == 'q' || k == 'Q' || k == 27) { if (quitask()) return 0; }
            else delay(15);
        }
    }
}

/* ---------------------------------------------------------------- el computador */
static uint8_t aishot(uint8_t *ox, uint8_t *oy)
{
    static const int8_t dx[4] = { 1, -1, 0, 0 }, dy[4] = { 0, 0, 1, -1 };
    uint8_t x, y, i, n, xx, yy, minl = 5, k;
    int8_t a, b;
    for (k = 0; k < NS; k++) if (ships[k].hits < slen[k] && slen[k] < minl) minl = slen[k];
    /* tocados sin hundir: seguir la linea, o probar al lado */
    for (y = 0; y < N; y++) for (x = 0; x < N; x++) {
        if (cseen[y][x] != 2) continue;
        for (i = 0; i < 4; i++) {           /* con otro tocado al lado: seguir esa linea */
            a = dx[i]; b = dy[i];
            xx = x - a; yy = y - b;
            if (xx < N && yy < N && cseen[yy][xx] == 2) {
                xx = x; yy = y;
                while (xx < N && yy < N && cseen[yy][xx] == 2) { xx += a; yy += b; }
                if (xx < N && yy < N && !cseen[yy][xx]) { *ox = xx; *oy = yy; return 1; }
            }
        }
    }
    for (y = 0; y < N; y++) for (x = 0; x < N; x++) {
        if (cseen[y][x] != 2) continue;
        for (n = 0; n < 8; n++) {
            i = (rnd() + n) & 3;
            xx = x + dx[i]; yy = y + dy[i];
            if (xx < N && yy < N && !cseen[yy][xx]) { *ox = xx; *oy = yy; return 1; }
        }
    }
    /* a buscar: casillas que dejan lugar al barco mas chico, en damero */
    for (n = 0; n < 250; n++) {
        x = rnd() % N; y = rnd() % N;
        if (cseen[y][x] || ((x + y) % minl && n < 200)) continue;
        for (i = 0, k = 0; i < 4; i++) {     /* lugar libre alrededor */
            xx = x + dx[i]; yy = y + dy[i];
            if (xx < N && yy < N && !cseen[yy][xx]) k++;
        }
        if (k || n > 220) { *ox = x; *oy = y; return 1; }
    }
    for (y = 0; y < N; y++) for (x = 0; x < N; x++) if (!cseen[y][x]) { *ox = x; *oy = y; return 1; }
    return 0;
}
static void aiknows(uint8_t x, uint8_t y, uint8_t r, uint8_t k)
{
    int8_t a, b;
    uint8_t i, xx, yy;
    cseen[y][x] = r ? 2 : 1;
    if (r >= 2) {                          /* hundido: lo de alrededor es agua */
        for (i = 0; i < ships[k].len; i++) {
            xx = ships[k].d ? ships[k].x : ships[k].x + i;
            yy = ships[k].d ? ships[k].y + i : ships[k].y;
            cseen[yy][xx] = 3;
            for (a = -1; a <= 1; a++) for (b = -1; b <= 1; b++)
                if ((uint8_t)(xx + a) < N && (uint8_t)(yy + b) < N && !cseen[yy + b][xx + a]) cseen[yy + b][xx + a] = 1;
        }
    }
}

/* ---------------------------------------------------------------- partida */
static void reveal(ship *s)      /* (al final) los barcos que no encontre */
{
    uint8_t k, i, x, y;
    for (k = 0; k < NS; k++) {
        if (eships[k].len) continue;
        for (i = 0; i < s[k].len; i++) {
            x = s[k].d ? s[k].x : s[k].x + i; y = s[k].d ? s[k].y + i : s[k].y;
            if (enemy[y][x] != 2) enemy[y][x] = 3;
        }
    }
    grid(1);
}
static uint8_t myturn(void)      /* 1 si gane, 2 si se acabo, 0 sigue */
{
    uint8_t ox, oy, r, k = 0;
    int c;
    say("Your turn: arrows (or a letter and a number) then Enter or Space to fire.");
    keys(" arrows move   Enter fire   T talk   Q quit ");
    for (;;) {
        cell(1, cx, cy);
        c = keyin();
        ox = cx; oy = cy;
        if (c == K_UP && cy) cy--;
        else if (c == K_DOWN && cy < N - 1) cy++;
        else if (c == K_LEFT && cx) cx--;
        else if (c == K_RIGHT && cx < N - 1) cx++;
        else if ((c | 32) >= 'a' && (c | 32) <= 'j') cx = (c | 32) - 'a';
        else if (c >= '1' && c <= '9') cy = c - '1';
        else if (c == '0') cy = 9;
        else if (c == 't' || c == 'T') { if (!comp) chat(); }
        else if (c == 'q' || c == 'Q' || c == 27) { if (quitask()) return 2; }
        else if (c == 13 || c == 10 || c == ' ') {
            if (enemy[cy][cx]) { say("You already fired there."); continue; }
            break;
        }
        if (ox != cx || oy != cy) cell(1, ox, oy);
        if (gone) return 2;
    }
    myshots++;
    if (comp) r = resolve(cown, cships, cx, cy, &k);
    else {
        mbuf[0] = cx; mbuf[1] = cy;
        if (dsend('S', mbuf, 2)) { say("The other player doesn't answer."); gone = 1; return 2; }
        say("Firing...");
        if (!waitfor('H')) return 2;
        r = mbuf[2];
        if (r >= 2) { k = mbuf[3]; eships[k].x = mbuf[4]; eships[k].y = mbuf[5]; eships[k].d = mbuf[6]; eships[k].len = mbuf[7]; }
    }
    if (comp && r >= 2) eships[k] = cships[k];
    enemy[cy][cx] = r ? 2 : 1;
    if (r) myhits++;
    if (r >= 2) { esunk++; marksunk(enemy, &eships[k]); grid(1); fleets(); }
    else cell(1, cx, cy);
    stats();
    gotoxy(1, 20); pstr("                                        ");
    gotoxy(1, 20);
    pf("You: %c%u ", 'A' + cx, cy + 1);
    if (r >= 2) pf("sank the %s!", sname[k]); else pstr(r ? "hit!" : "water.");
    return r == 3;
}
static uint8_t theirturn(void)   /* 1 si perdi, 2 si se acabo, 0 sigue */
{
    uint8_t x, y, r, k = 0;
    say(comp ? "The computer is aiming..." : "The other player is aiming...");
    keys(comp ? " Q quit " : " T talk   Q quit ");
    if (comp) { delay(tps() / 2); aishot(&x, &y); }
    else {
        if (!waitfor('S')) return 2;
        x = mbuf[0]; y = mbuf[1];
    }
    r = resolve(own, ships, x, y, &k);
    if (comp) aiknows(x, y, r, k);
    else {
        mbuf[0] = x; mbuf[1] = y; mbuf[2] = r; mbuf[3] = k;
        mbuf[4] = ships[k].x; mbuf[5] = ships[k].y; mbuf[6] = ships[k].d; mbuf[7] = ships[k].len;
        if (dsend('H', mbuf, 8)) { say("The other player doesn't answer."); gone = 1; return 2; }
    }
    cell(0, x, y);
    if (r) fleets();
    gotoxy(41, 20);
    pf("%s: %c%u ", comp ? "Computer" : "They", 'A' + x, y + 1);
    if (r >= 2) pf("sank your %s!" EOL, sname[k]); else pstr(r ? "hit!" EOL : "water." EOL);
    return r == 3;
}
static uint8_t setup(void)       /* la flota; 1 si se acabo */
{
    int k;
    for (;;) {
        place(own, ships);
        grid(0); fleets();
        say("This is your fleet. R: another layout, Enter: ready.");
        keys(comp ? " R new layout   Enter ready   Q quit " : " R new layout   Enter ready   T talk   Q quit ");
        for (;;) {
            if (!comp) {                   /* mientras, lo que diga el otro */
                k = drecv(mbuf);
                if (k == 'T') { gotoxy(1, 22); pf(INV " They say: " NORM " %s" EOL, (char *)mbuf); }
                if (k == 'Q') { say("The other player left the game."); return 1; }
                if (k == 'R') { say2("The other player is ready."); peerready = 1; }
                k = getkey();
                if (!k) { delay(10); continue; }
            } else k = waitkey();
            if (k == 'r' || k == 'R') break;
            if (k == 13 || k == 10) {
                if (comp) return 0;
                if (dsend('R', 0, 0)) { say("The other player doesn't answer."); return 1; }
                if (peerready) return 0;
                say("Waiting for the other player to place the fleet...");
                return !waitfor('R');
            }
            if (k == 't' || k == 'T') { if (!comp) chat(); }
            if (k == 'q' || k == 'Q' || k == 27) { if (quitask()) return 1; }
        }
    }
}
static uint8_t lobby(void)       /* 0 contra alguien, 1 contra el computador, 2 salir */
{
    uint8_t r, ok, shown = 0;
    int k;
    pstr(CLS SHOW);
    pstr("N A V A L  -  battleship   (C) OLIVEROS 2026\n\n");
    if (!ismpm()) { pstr("Only the computer to play against here (two players need MP/M II).\n"); return 1; }
    ok = !dopen("NAVAL   DAT");
    if (!ok) { pstr("Can't open A:NAVAL.DAT: only the computer to play against.\n"); return 1; }
    for (;;) {
        r = dlobby();
        if (r == DL_GO) return 0;
        if (r == DL_ERR) { pstr("\nTrouble with A:NAVAL.DAT.\n"); return 1; }
        if (dstate == 1 && !shown) {
            pstr("\rWaiting for someone to run NAVAL on another console...  "
                 "(C: play the computer, Q: quit) ");
            shown = 1;
        }
        k = getkey();
        if (k == 'c' || k == 'C') { dleave(); return 1; }
        if (k == 'q' || k == 'Q' || k == 27) { dleave(); return 2; }
        delay(tps() / 3);
    }
}
void main(void)
{
    uint8_t r, turn;
    char *a = args(), *w = nextarg(&a);
    srnd(ticks() ^ (uint16_t)mycons() << 8);
    if (w && (w[0] | 32) == 'c') comp = 1;
    else {
        r = lobby();
        if (r == 2) { pstr("\n"); dclose(); return; }
        comp = r;
        if (comp && ismpm()) { pstr("\nAgainst the computer: press a key"); waitkey(); }
    }
    if (comp) place(cown, cships);
    drawall();
    if (!comp) say2(dme ? "You joined the game: the other player fires first."
                        : "Someone joined the game: you fire first.");
    if (setup()) goto end;
    say2("");
    turn = comp ? 0 : dme;
    for (;;) {
        r = turn ? theirturn() : myturn();
        if (r) break;
        turn ^= 1;
    }
    if (r == 1) {
        say2("");
        if (turn == 0) { say(INV " You sank the whole fleet: you win! " NORM); }
        else {
            say(INV " Your fleet is at the bottom of the sea: you lose. " NORM);
            if (comp) reveal(cships);
        }
        if (!comp) {                         /* los barcos que no se encontraron */
            for (r = 0; r < NS; r++) {
                mbuf[r * 4] = ships[r].x; mbuf[r * 4 + 1] = ships[r].y;
                mbuf[r * 4 + 2] = ships[r].d; mbuf[r * 4 + 3] = ships[r].len;
            }
            if (!dsend('F', mbuf, NS * 4) && waitfor('F')) {
                for (r = 0; r < NS; r++) {
                    cships[r].x = mbuf[r * 4]; cships[r].y = mbuf[r * 4 + 1];
                    cships[r].d = mbuf[r * 4 + 2]; cships[r].len = mbuf[r * 4 + 3];
                }
                reveal(cships);
            }
        }
    }
end:
    keys(" press a key ");
    while (getkey()) ;
    if (gone != 2) waitkey();
    if (!comp) dclose();
    pstr(CLS SHOW);
    oflush();
}
