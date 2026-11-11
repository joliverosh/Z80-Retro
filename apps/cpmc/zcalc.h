/* zcalc.h - lo que comparten ZCALC (zcalc.c, residente) y sus partes que se
   cargan de ZCALC.OVL cuando hacen falta (zcov*.c) */
#include <string.h>
#include "cpm.h"

#define VERSION "1.2"            /* tambien en zcalc_a.s y en LEEME.md */

#define NC 63                    /* columnas */
#define NR 254                   /* filas */
#define GTOP 4                   /* fila de pantalla de la primera fila de la hoja */
#define GROWS 21                 /* filas de la hoja en pantalla */
#define LW 4                     /* ancho de los numeros de fila */
#define MAXE 120                 /* largo de una entrada */
#define MAXT 160                 /* bytes de una formula compilada */
#define MAXVC 26                 /* columnas en pantalla */
#define OVLSZ 2816               /* lugar para la parte cargada (multiplo de 128) */

#define KUP 0x81
#define KDOWN 0x82
#define KRIGHT 0x83
#define KLEFT 0x84
#define KHOME 0x85
#define KEND 0x86
#define KDEL 0x87
#define KPGUP 0x88
#define KPGDN 0x89
#define ISARROW(k) ((k) >= KUP && (k) <= KLEFT)
#define INV ESC "[7m"
#define NORM ESC "[0m"
#define EOL ESC "[K"

/* ---------------------------------------------------------------- memoria */
extern uint16_t hfree;
void *zalloc(uint16_t n);
void zfree(void *p);

/* ---------------------------------------------------------------- numeros */
/* valor = m * 10^e con |m| < 10^9; m sin ceros al final (0 tiene e = 0) */
typedef struct { int32_t m; int8_t e; } num;
enum { V_NUM, V_ERR, V_NA, V_STR };
typedef struct { uint8_t t; num n; } val;
extern uint8_t nerr;             /* desbordamiento o division por cero (en zcalc_a.s) */
uint8_t ndig(uint32_t u) __sdcccall(0);
void mk32(num *x, uint32_t v, uint8_t neg, int16_t e) __sdcccall(0);
void nadd(num *r, const num *a, const num *b) __sdcccall(0);
void nmul(num *r, const num *a, const num *b) __sdcccall(0);
void ndiv(num *r, const num *a, const num *b) __sdcccall(0);
void nround(num *r, const num *a, int8_t d) __sdcccall(0);
void ntrunc(num *r, const num *a) __sdcccall(0);
int16_t ntoi(const num *a) __sdcccall(0);
int8_t ncmp(const num *a, const num *b);
void nset(num *x, int16_t i);
uint8_t utoa_(uint32_t u, char *o) __sdcccall(0);
uint8_t nplain(char *o, const num *x, int8_t dec, uint8_t max) __sdcccall(0);
uint8_t nsci(char *o, const num *x, uint8_t max) __sdcccall(0);
const char *pnum(const char *s, num *x) __sdcccall(0);
/* formatos: 0 el global, 1 general, 2 grafico, 3+k: k decimales, 13 fecha, 14 hora */
void fmtnum(char *o, const num *x, uint8_t nf, uint8_t w) __sdcccall(0);
uint8_t datestr(char *o, const num *x, uint8_t nf) __sdcccall(0);

/* ---------------------------------------------------------------- celdas */
enum { K_LAB = 1, K_REP, K_NUM, K_FRM };
typedef struct cell {
    struct cell *nx;
    uint8_t c, r;                /* columna y fila (desde 1) */
    uint8_t fl;                  /* bits 0-2 clase, 3 calculando, 4-5 tipo de valor, 7 marca */
    uint8_t f;                   /* formato: bits 0-3 numero, 4-5 alineacion, 6 protegida */
    uint8_t n;                   /* bytes de d */
    uint8_t d[1];                /* texto; o el valor (5 bytes), y en las formulas
                                    la generacion (1) y la formula compilada */
} cell;
#define KIND(x) ((x)->fl & 7)
#define VT(x) (((x)->fl >> 4) & 3)
#define SETVT(x, t) ((x)->fl = ((x)->fl & 0xCF) | ((t) << 4))
#define F_ST 0x08
#define F_PROT 0x40
#define F_MARK 0x80
#define NUMP(x) ((num *)(x)->d)
#define GEN(x) (*((x)->d + 5))
#define TOK(x) ((x)->d + 6)
#define NH 128
extern cell *ht[NH];
cell *find(uint8_t c, uint8_t r) __sdcccall(0);   /* en zcalc_a.s */
extern uint8_t hb;
#define FOR_CELLS(x) for (hb = 0; hb < NH; hb++) for (x = ht[hb]; x; x = x->nx)
void freecell(cell *x);
void delcell(uint8_t c, uint8_t r);
cell *newcell(uint8_t c, uint8_t r, uint8_t k, uint8_t n);
void clearall(void);
extern cell *clip;                /* el portapapeles (/K /V) y la esquina que se copio */
extern uint8_t kc, kr;
void rehash(void);

/* ---------------------------------------------------------------- formulas */
enum { TK_END, TK_NUM, TK_REF, TK_RNG, TK_FN, TK_LE, TK_GE, TK_NE, TK_I8, TK_STR, TK_NM };
#define STRP(x) (*(char **)(x)->d)    /* el texto que da una formula (VT V_STR) */
#define STRN(x) (*((x)->d + 2))
uint8_t isup(char c);
uint8_t isdig(char c);
uint8_t pref(const char **ps, uint8_t *c, uint8_t *r, uint8_t *fl) __sdcccall(0);
uint8_t colname(char *o, uint8_t c) __sdcccall(0);
uint8_t refname(char *o, uint8_t c, uint8_t r, uint8_t fl) __sdcccall(0);
uint8_t tok(const char *s, uint8_t *o) __sdcccall(0);
uint8_t dtok(const uint8_t *t, char *o, uint8_t max) __sdcccall(0);
void recalc(void);
extern uint8_t tb[MAXT];
extern uint8_t modified, dirty;
uint8_t setcell(uint8_t c, uint8_t r, const char *s, uint8_t label);
void celltext(cell *x, char *o, uint8_t max);
extern uint8_t am, arow, aat, mc1, mr1, mc2, mr2;
extern int16_t mdc, mdr;
void adjform(uint8_t *t) __sdcccall(0);
void shiftform(uint8_t *t, int16_t dc, int16_t dr) __sdcccall(0);
void adjall(void);
/* nombres de rango: el nombre y la referencia compilada (TK_REF o TK_RNG, con $, y TK_END);
   en las formulas va la referencia seguida de TK_NM id (zcalc_a.s los usa) */
#define NNM 24
typedef struct { char nm[9]; uint8_t t[6]; } name_t;
extern name_t nms[NNM];
extern uint8_t nnm, dknm;
uint8_t copycell(cell *x, uint8_t c, uint8_t r);

/* ---------------------------------------------------------------- pantalla y teclado */
extern uint8_t cc, cr, fc, fr, tcn, trn, gw, gnf, autoc;
extern uint8_t cw[NC + 1];
#define CW(c) (cw[c] ? cw[c] : gw)
extern char fname_[16];
extern char sb[90];
extern char eb[MAXE + 1];
void cellstr(char *o, uint8_t c, uint8_t r, uint8_t w) __sdcccall(0);
uint8_t getk(void);
uint8_t ask(const char *s);
uint8_t input(const char *prompt, const char *init);
void msg(const char *s);
uint8_t isarg(char *s, uint8_t *c, uint8_t *r);
uint8_t prange(char *s, uint8_t *c1, uint8_t *r1, uint8_t *c2, uint8_t *r2);
void curref(char *o);
uint8_t usedmax(uint8_t *mc, uint8_t *mr);

/* ---------------------------------------------------------------- archivos */
extern FCB of, inf;
extern uint8_t ob[128], obp, odev, oerr, inp;
int rdc(void);
void oc(char c);
void os(const char *s);
uint8_t oclose(void);
uint8_t ofile(const char *name);
void defext(char *s, const char *ext);

/* ---------------------------------------------------------------- partes cargadas */
/* ZCALC.OVL: OV_LOAD (1: /SL, 2: cargar eb al empezar), OV_SAVE (1: /SS, 2: /SX,
   3: /P), OV_CMD (/F /G /R /M), OV_HELP (1: ?, 2: /A), OV_CMD2 (/L /O /K /V), OV_NAME (/N), OV_CHART (/X),
   OV_WKS (leer .WKS/.WK1 de eb), OV_WKSW (/SW), OV_WKSF (las formulas de lo leido) */
enum { OV_LOAD = 1, OV_SAVE, OV_CMD, OV_HELP, OV_CMD2, OV_NAME, OV_CHART, OV_WKS, OV_WKSW, OV_WKSF, NOVL };
extern void *wkl;
extern uint8_t ovlreg[OVLSZ];
extern uint8_t ovlret, ovlop;
uint8_t ovl(uint8_t n, uint8_t op);
