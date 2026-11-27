/* filtro.h - lo que se incluye antes de cada filtro de Semilla (mks.sh) */
#ifdef HI_TECH_C
/* HI-TECH C (htc/S_*.C): sin el stdio.h de HI-TECH, que hace de getchar y
   putchar macros de su FILE; estas son las de filtro.c */
#include "cpm.h"
int getchar(void);
int putchar(int c);
int puts(char *s);
char *gets(char *s);
int printf(char *f, ...);
int sprintf(char *d, char *f, ...);
#ifndef EOF
#define EOF (-1)
#endif
#ifndef NULL
#define NULL ((void *)0)
#endif
#else
#include <stdio.h>
char *gets(char *s);             /* (SDCC lo quita en C11) */
#endif
