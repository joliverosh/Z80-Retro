/* zbas.h - lo que comparten ZBAS (zbas.c, residente: correr los programas) y la
   parte que se carga de ZBAS.OVL cuando hace falta (zbov.c: compilar, LIST, LOAD,
   SAVE, RENUM...). (C) OLIVEROS 2026 */
#include <string.h>
#include <setjmp.h>
#include "cpm.h"
#include "znum.h"
#define VERSION "1.0"            /* tambien en LEEME.md */
enum { T_END, T_NUM, T_STR, T_ID, T_LNUM, T_RAW };
enum {
    K_PRINT = 0x80, K_INPUT, K_LET, K_IF, K_THEN, K_ELSE, K_ELSEIF, K_END, K_FOR, K_TO,
    K_STEP, K_NEXT, K_WHILE, K_WEND, K_DO, K_LOOP, K_UNTIL, K_EXIT, K_SELECT, K_CASE,
    K_IS, K_GOTO, K_GOSUB, K_RETURN, K_SUB, K_FUNCTION, K_CALL, K_LOCAL, K_DIM, K_DATA,
    K_READ, K_RESTORE, K_REM, K_STOP, K_CLS, K_LOCATE, K_COLOR, K_RANDOMIZE, K_OPEN, K_CLOSE,
    K_AS, K_OUTPUT, K_APPEND, K_LINE, K_SWAP, K_SLEEP, K_BEEP, K_ON, K_AND, K_OR,
    K_NOT, K_XOR, K_MOD, K_LE, K_GE, K_NE, K_RUN, K_LIST, K_NEW, K_LOAD,
    K_SAVE, K_FILES, K_SYSTEM, K_CONT, K_DELETE, K_RENUM, K_EDIT, K_TRON, K_TROFF, K_ERASE,
    K_USING, K_TAB, K_SPC, K_KILL, K_AUTO,
    /* funciones */
    F_FIRST,
    F_ABS = F_FIRST, F_INT, F_FIX, F_SGN, F_SQR, F_SIN, F_COS, F_TAN, F_ATN, F_LOG,
    F_LOG10, F_EXP, F_RND, F_PI, F_ROUND, F_PMT, F_PV, F_FV, F_DATE, F_TODAY,
    F_NOW, F_YEAR, F_MONTH, F_DAY, F_LEN, F_LEFT, F_RIGHT, F_MID, F_INSTR, F_UCASE,
    F_LCASE, F_STR, F_VAL, F_CHR, F_ASC, F_SPACE, F_STRING, F_TRIM, F_LTRIM, F_RTRIM,
    F_HEX, F_DATES, F_TIMES, F_INKEY, F_EOF, F_FORMAT, F_MIN, F_MAX, F_FRE, F_POS,
    F_LAST
};
#define NKW (F_LAST - 0x80)
typedef struct fb { uint16_t sz; struct fb *nx; } fb;
typedef struct { uint8_t s; num n; uint8_t *p; uint16_t l; } value;
typedef struct { uint8_t t; union { num n; struct { uint8_t *p; uint16_t l; } s; struct { void *a; } a;
                                    struct { uint8_t *l; uint16_t r; } f; } u; } slot;
enum { S_NUM, S_STR, S_NARR, S_SARR, S_SUB, S_FUNC, S_SFUNC, S_LABEL };
#define LLEN(p) ((p)[0] | (p)[1] << 8)
#define LNUM(p) ((p)[2] | (p)[3] << 8)
#define LJMP(p) (*(uint16_t *)((p) + 4))
#define LTOK(p) ((p) + 6)
enum { C_FOR = 1, C_GOSUB, C_WHILE, C_DO, C_CALL, C_FUNC };
typedef struct {
    uint8_t k;
    uint8_t *line, *tp;          /* donde volver o donde empieza el bloque */
    uint16_t v;                  /* FOR: la variable; CALL: cuantas locales guardo */
    num lim, step;
} ctl;
#define NCTL 24
typedef struct { uint16_t i; slot s; } saved;
#define NSAV 64
typedef struct { uint8_t nd; uint16_t d[3]; } arrhdr;   /* y despues los elementos */

/* ---------------------------------------------------------------- residente (zbas.c) */
extern char heap[];
extern uint8_t *prog, *pend;
extern uint8_t *names, *nend;
extern uint16_t nsym;
extern uint8_t *dbase, *dtop;
extern uint8_t *memtop;
extern fb *freel;
extern uint16_t hfree;
extern jmp_buf errjb;
extern uint16_t errline;
extern uint8_t running;
extern uint8_t errn;
extern slot *vars;
extern uint16_t nvars;
extern uint8_t col;
extern uint8_t outf;
extern char lb[256];
extern uint8_t *cl;
extern uint8_t *tp;
extern uint8_t direct[260];
extern uint8_t tron;
extern ctl cs[NCTL];
extern uint8_t csp;
extern saved sv[NSAV];
extern uint8_t svp;
extern uint8_t *dnext, *datap;
extern uint8_t *contline, *conttp;
extern FCB *files[4];
extern uint8_t *fbuf[4], fpos[4], fmode[4], feof_[4];
extern value retv;
extern uint8_t retset;
extern uint8_t clk[4], csec;
extern uint8_t *wl, *wp;
extern uint8_t fbufp[4];
extern uint16_t frec[4];
extern uint8_t jumped, fret;
extern uint16_t ticks_;
extern char fnb[16];
void heapinit(void);
void *zalloc(uint16_t n);
void zfree(void *p);
void error(uint8_t n);
void *xalloc(uint16_t n);
uint8_t *symat(uint16_t i);
void growvars(void);
slot *var(uint16_t i);
void sfree_(value *v);
void newstr(value *v, const uint8_t *s, uint16_t n);
void conc(uint8_t c);
void cons(const char *s);
uint8_t brkchk(void);
uint8_t getline_(uint8_t n0);
void conss(const char *s);
uint8_t isal(uint8_t c);
uint8_t isdg(uint8_t c);
uint8_t up(uint8_t c);
uint8_t *findline(uint16_t n, uint8_t exact);
void clearvars(void);
uint8_t peek(void);
void skip(uint8_t c);
uint8_t accept(uint8_t c);
void numexpr(num *n);
int16_t intexpr(void);
void strexpr(value *v);
void setn(value *v, int16_t i);
void setb(value *v, uint8_t b);
uint8_t truth(const num *n);
slot *arrsize(uint16_t ix, uint16_t *dims, uint8_t nd, uint8_t isstr);
uint8_t *element(uint16_t ix, uint8_t isstr);
void primary(value *v);
void power(value *v);
void term(value *v);
void sum(value *v);
int8_t scmp(value *a, value *b);
void relation(value *v);
void andexpr(value *v);
void expr(value *v);
uint8_t clock_(void);
uint8_t b2(uint8_t b);
void substr(value *v, value *s, uint16_t from, uint16_t n);
void func(uint8_t f, value *v);
uint8_t tsize(const uint8_t *p);
uint8_t *nextline(uint8_t *l);
uint8_t wfirst(void);
uint8_t wnext(void);
uint8_t blockif(const uint8_t *p);
uint8_t findend(uint8_t open, uint8_t stopelse);
void skipstmt(void);
void jumpw(void);
uint8_t findendc(uint8_t open, uint8_t stopelse);
void store(slot *s, uint8_t isstr, value *v);
uint8_t *lvalue(uint8_t *isstr, slot **sp);
void assignto(uint8_t *e, slot *s, uint8_t isstr, value *v);
void let(void);
void outc(uint8_t c);
void outs(const uint8_t *s, uint16_t n);
void outnum(const num *n);
uint8_t chan(void);
void print(void);
void fflush_(uint8_t h);
int16_t fgetc_(uint8_t h);
void fpeekeof(uint8_t h);
void closef(uint8_t h);
void openf(void);
uint8_t field(uint8_t h, char *o, uint8_t max, uint8_t wholeline);
uint8_t settext(uint8_t *e, slot *s, uint8_t isstr, const char *t, uint8_t n);
void input(uint8_t whole);
void readdata(void);
void pushc(uint8_t k);
void goline(uint8_t *l);
uint8_t *target(void);
void save(uint16_t i);
void restore(uint8_t to);
void bind(uint8_t *l, value *args, uint8_t n);
uint8_t getargs(value *a);
void callfn(uint16_t ix, value *v);
void callsub(uint16_t ix);
void endproc(void);
uint8_t casematch(value *v);
void afterw(void);
void doif(void);
void dofor(void);
void donext(void);
uint8_t docond(void);
void dosub_or_let(void);
void bfname(value *v, const char *ext);
void stmt_(void);
void advance(void);
void runloop(uint8_t level);

extern uint8_t *htop;            /* el fin del heap de datos: memtop, o la parte cargada */

/* ---------------------------------------------------------------- las partes cargadas */
/* ZBAS.OVL tiene tres partes; la que hace falta se carga arriba del heap (en una
   direccion multiplo de 256, por eso solo se corrigen los bytes altos de sus
   direcciones) y se queda ahi hasta que el heap necesita el lugar o se pide otra.
   Cada una empieza con un salto a su ovl_entry(ovop).
   zbov1: OV_LINE (una linea del teclado: ovret 1 si hay que correrla en direct, 2 si es
          EDIT ovn1), OV_NUMLINE (guardar la linea de lb), OV_LOAD (fnb), OV_DELETE (ovn1-ovn2)
   zbov2: OV_LIST (ovn1-ovn2), OV_SAVE (fnb), OV_EDIT (ovn1 en lb; ovret 1 si quedo algo)
   zbov3: OV_ERR (el mensaje de errn; ovk: con la linea), OV_RUN, OV_RENUM
          (desde ovn1, de a ovn2), OV_FILES */
enum { OV_LINE = 1, OV_NUMLINE, OV_LOAD, OV_DELETE, OV_LIST, OV_SAVE, OV_EDIT,
       OV_ERR, OV_RUN, OV_RENUM, OV_FILES };
extern uint8_t ovop, ovret, ovk;
extern uint16_t ovn1, ovn2;
extern uint8_t *ovb;             /* donde esta cargada (0 = no hay ninguna) */
extern uint8_t resolved;         /* ya se vio donde estan las etiquetas, SUB y FUNCTION */
extern uint8_t autoon;           /* AUTO: el numero que sigue y el paso */
extern uint16_t autonum, autoinc;
void ovl(uint8_t op);
void prompt_ok(void);
void newprog(void);
