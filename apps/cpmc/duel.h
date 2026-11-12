/* duel.h - dos programas en consolas distintas de MP/M II juegan uno contra otro.
   Se hablan por un archivo de A: (usuario 0) abierto en modo sin bloqueo por los dos
   (atributo f5'): el XIOS tiene una sola cache de la SD, asi que lo que escribe uno lo
   lee el otro en el acto. Las colas de MP/M (134-140) no sirven entre programas: el QCB
   tendria que estar en la memoria comun, y esa es del sistema.
     registro 0: la sala de espera: 'D', estado (0 nadie, 1 alguien espera, 2 ya se unio),
                 mesa, consola del que espera, la hora (segundos del dia) del que espera
     registros 1+2k y 2+2k: la mesa k (4 mesas): lo que manda el que espero (1+2k) y lo
                 que manda el que se unio (2+2k): [0] numero del mensaje, [1] el ultimo
                 numero que leyo del otro, [2] tipo, [3..] datos
   Cada mensaje espera a que el otro lo lea antes del siguiente; mientras tanto se guarda
   lo que llega (hasta DQN mensajes), para que no se traben si mandan los dos a la vez.
   Uso: dopen("NAVAL   DAT"); dlobby() en un bucle hasta que diga DL_GO; dsend/drecv;
   dclose() al final. (C) OLIVEROS 2026 */
#define DSLOTS 4
#define DQN 4
#define DLEN 120
enum { DL_WAIT, DL_GO, DL_ERR };
static FCB dfcb;
static uint8_t dme;                  /* 0: espero (juega primero); 1: me uni */
static uint8_t dslot, dseq, dlast, dpack, dstate;
static uint16_t dbeat;               /* tics de la ultima vez que escribi la hora */
static uint8_t drb[128], dwb[128];   /* lo que lee y lo que manda */
static uint8_t dq[DQN][DLEN + 1], dqn;   /* lo que llego mientras se esperaba */

static uint32_t dnow(void)           /* segundos del dia */
{
    TOD t;
    gettod(&t);
    return (uint32_t)bcd(t.h) * 3600 + bcd(t.m) * 60 + bcd(t.s);
}
static uint8_t drd(uint8_t r) { return rread(&dfcb, r, drb); }
static uint8_t dwr(uint8_t r, uint8_t *p) { return rwrite(&dfcb, r, p); }
/* 0 bien. Crea el archivo la primera vez (oculto, con 1 + 2 * DSLOTS registros) */
static uint8_t dopen(const char *name11)
{
    uint8_t i, u = bdos(32, 0xFF);
    bdos(45, 0xFF);                       /* los errores del BDOS vuelven, sin mensaje */
    bdos(32, 0);
    memset(&dfcb, 0, sizeof dfcb);
    dfcb.dr = 1;
    memcpy(dfcb.f, name11, 11);
    bdos(26, (uint16_t)drb);
    if ((bdos(17, (uint16_t)&dfcb) & 0xFF) == 0xFF) {   /* no esta: crearlo */
        memset(dwb, 0, 128);
        if (fmake(&dfcb)) { bdos(32, u); return 1; }
        for (i = 0; i < 1 + 2 * DSLOTS; i++) fwrite(&dfcb, dwb);
        fclose(&dfcb);
        dfcb.f[9] |= 0x80;                /* SYS: que no aparezca en DIR */
        bdos(30, (uint16_t)&dfcb);
        dfcb.f[9] &= 0x7F;
    }
    memset(&dfcb.ex, 0, sizeof dfcb - 12);
    dfcb.f[4] |= 0x80;                    /* f5': modo sin bloqueo */
    i = fopen(&dfcb);
    bdos(32, u);
    dstate = 0;
    return i;
}
/* la sala de espera: llamar seguido (cada medio segundo esta bien) */
static uint8_t dlobby(void)
{
    uint32_t now = dnow(), t;
    if (drd(0)) return DL_ERR;
    t = drb[4] | (uint32_t)drb[5] << 8 | (uint32_t)drb[6] << 16;
    if (dstate == 0) {                    /* recien llegado: unirse o esperar */
        if (drb[0] == 'D' && drb[1] == 1 && drb[3] != mycons() && (now + 86400 - t) % 86400 < 10) {
            dme = 1; dslot = drb[2];
            drb[1] = 2;
            if (dwr(0, drb)) return DL_ERR;
            dseq = dlast = dpack = dqn = 0;
            dstate = 2;
            return DL_GO;
        }
        dme = 0;
        dslot = drb[0] == 'D' ? (drb[2] + 1) % DSLOTS : 0;
        memset(dwb, 0, 128);
        dwr(1 + 2 * dslot, dwb); dwr(2 + 2 * dslot, dwb);
        dstate = 1;
        dbeat = ticks() - 1000;
    }
    if (drb[0] == 'D' && drb[1] == 2 && drb[2] == dslot && dstate == 1 && drb[3] == mycons()) {
        dseq = dlast = dpack = dqn = 0;
        dstate = 2;
        return DL_GO;
    }
    if (drb[0] == 'D' && drb[1] == 1 && drb[3] != mycons() && (now + 86400 - t) % 86400 < 10 &&
        drb[3] < mycons()) {               /* empezamos a esperar a la vez: espera el de menor consola */
        dstate = 0;
        return dlobby();
    }
    if ((uint16_t)(ticks() - dbeat) >= 2 * tps() || drb[1] != 1 || drb[3] != mycons()) {
        memset(drb, 0, 128);
        drb[0] = 'D'; drb[1] = 1; drb[2] = dslot; drb[3] = mycons();
        drb[4] = now; drb[5] = now >> 8; drb[6] = now >> 16;
        if (dwr(0, drb)) return DL_ERR;
        dbeat = ticks();
    }
    return DL_WAIT;
}
static void dleave(void)             /* deja la sala si se estaba esperando */
{
    if (dstate == 1 && !drd(0) && drb[1] == 1 && drb[3] == mycons()) { drb[1] = 0; dwr(0, drb); }
    dstate = 0;
}
/* lo que mando el otro, si hay algo nuevo; lo guarda en la cola. 1 si hubo error */
static uint8_t dpoll(void)
{
    if (drd(dme ? 1 + 2 * dslot : 2 + 2 * dslot)) return 1;
    dpack = drb[1];
    if (drb[0] != dlast && dqn < DQN) {
        dlast = drb[0];
        memcpy(dq[dqn++], drb + 2, DLEN + 1);
        dwb[0] = dseq; dwb[1] = dlast;
        return dwr(dme ? 2 + 2 * dslot : 1 + 2 * dslot, dwb);
    }
    return 0;
}
/* el tipo del siguiente mensaje (0 si no hay) y sus datos en buf */
static uint8_t drecv(uint8_t *buf)
{
    uint8_t t;
    if (!dqn) dpoll();
    if (!dqn) return 0;
    t = dq[0][0];
    memcpy(buf, dq[0] + 1, DLEN);
    dqn--;
    memmove(dq[0], dq[1], dqn * (DLEN + 1));
    return t;
}
/* manda un mensaje; espera (como mucho unos 20 s) a que el otro lea el anterior.
   0 bien, 1 el otro no lo leyo */
static uint8_t dsend(uint8_t type, const void *data, uint8_t n)
{
    uint16_t t0 = ticks();
    while (dpack != dseq) {
        if (dpoll()) return 1;
        if (dpack == dseq) break;
        if ((uint16_t)(ticks() - t0) > 20 * tps()) return 1;
        delay(6);
    }
    dseq++;
    if (!dseq) dseq = 1;
    memset(dwb, 0, 128);
    dwb[0] = dseq; dwb[1] = dlast; dwb[2] = type;
    memcpy(dwb + 3, data, n);
    return dwr(dme ? 2 + 2 * dslot : 1 + 2 * dslot, dwb);
}
static void dclose(void) { dleave(); fclose(&dfcb); }
