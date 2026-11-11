/* znum.h - numeros decimales de 9 cifras (znum_a.s y znum.c) */
#ifndef ZNUM_H
#define ZNUM_H
#include <stdint.h>

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

void npow(num *r, const num *a, const num *b) __sdcccall(0);
uint8_t nsqrt(num *r, const num *a) __sdcccall(0);
void nsub(num *r, const num *a, const num *b);
/* las funciones con ids de ZCALC (F_PMT = 20 ... F_LOG = 37): v = f(a[0..n-1]);
   los flujos de @NPV/@IRR van en cfb/cfn */
void cfunc(val *v, val *a, uint8_t n, uint8_t id) __sdcccall(0);
extern num cfb[48];
extern uint8_t cfn;
#endif
