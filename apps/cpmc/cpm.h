/* cpm.h - lo minimo para escribir programas de CP/M y MP/M II en C (SDCC) */
#ifndef CPM_H
#define CPM_H
#include <stdint.h>
typedef struct { uint8_t dr; char f[11]; uint8_t ex, s1, s2, rc; uint8_t d[16];
                 uint8_t cr, r0, r1, r2; } FCB;
uint16_t bdos(uint8_t c, uint16_t de) __sdcccall(0);
uint8_t zios(uint8_t c, uint8_t b, uint16_t de, uint16_t hl) __sdcccall(0);
extern uint16_t zde, zhl;
void exit(void);
void oflush(void);                /* lo que espera en el bufer de salida, a la consola */
void putch(char c);              /* sin traducir (BDOS 6) */
void pstr(const char *s);        /* \n -> CR LF */
void pf(const char *fmt, ...);   /* %d %u %ld %lu %x %X %lx %s %c, ancho y 0 */
int  getkey(void);               /* 0 si no hay tecla (no espera) */
int  waitkey(void);              /* espera una tecla */
void delay(uint16_t ticks);      /* BDOS 141 (MP/M) */
uint8_t ismpm(void);
/* archivos: FCB y registros de 128 */
uint8_t mkfcb(FCB *f, const char *name);   /* 0 si el nombre no sirve */
uint8_t fopen(FCB *f);           /* 0 bien */
void    fclose(FCB *f);
uint8_t fread(FCB *f, uint8_t *buf);  /* 0 bien, 1 fin */
uint8_t fwrite(FCB *f, uint8_t *buf); /* 0 bien */
uint8_t fmake(FCB *f);           /* borra y crea; 0 bien */
uint16_t fsize(FCB *f);          /* registros */
char *args(void);                /* la linea de ordenes (sin el espacio inicial) */
char *nextarg(char **p);         /* la siguiente palabra, terminada en 0 */
void fname(FCB *f, char *out);   /* "A:NOMBRE.EXT" */
uint16_t ticks(void);            /* tics de ZIOS (servicio 31), 16 bits bajos */
uint8_t tps(void);               /* tics por segundo */
#define ESC "\x1b"
/* MP/M */
uint16_t sysdat(void);           /* BDOS 154 */
uint16_t datapg(void);           /* la de XDOS (TOD, listas): SYSDAT+252 */
uint8_t mycons(void);            /* BDOS 153: consola del proceso (0-4) */
typedef struct { uint16_t day; uint8_t h, m, s; } TOD;   /* h m s en BCD */
void gettod(TOD *t);             /* BDOS 155 */
void ymd(uint16_t day, uint16_t *y, uint8_t *mo, uint8_t *d); /* dia 1 = 1/1/1978 */
uint8_t bcd(uint8_t b);
uint16_t rnd(void);
void srnd(uint16_t s);
#define CLS     ESC "[H" ESC "[J"
#define HOME    ESC "[H"
#define HIDE    ESC "[?25l"
#define SHOW    ESC "[?25h"
void gotoxy(uint8_t x, uint8_t y);   /* 1-80, 1-24 */
/* mas archivos */
uint8_t fdelete(FCB *f);         /* 0 bien */
uint8_t rread(FCB *f, uint16_t rec, uint8_t *buf);   /* lectura directa (BDOS 33); 0 bien */
uint8_t rwrite(FCB *f, uint16_t rec, uint8_t *buf);  /* escritura directa (BDOS 34) */
typedef char NAME12[12];         /* unidad (0 = la actual) y los 11 del nombre */
uint8_t glob(const char *spec, NAME12 *out, uint8_t max);  /* los que casan; cuantos */
void nm2fcb(NAME12 n, FCB *f);
/* lectura de a un byte */
typedef struct { FCB f; uint8_t b[128]; uint8_t p; uint8_t eof; } RD;
uint8_t ropen(RD *r, FCB *f);    /* 0 bien */
int rgetc(RD *r);                /* -1 al final (no mira ^Z) */
/* SDCC 4.2: (int32_t)a * b con a y b de 16 bits sale mal; usar esta */
int32_t mul16(int16_t a, int16_t b);
uint8_t brk(void);               /* 1 si se pulso ^C, Q o ESC */
#endif
