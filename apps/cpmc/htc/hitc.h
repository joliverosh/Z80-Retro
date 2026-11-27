/* hitc.h - lo que le falta a HI-TECH C 3.09 (CP/M) para los fuentes de SDCC.
   Lo incluye cpm.h cuando compila HI-TECH C (define HI_TECH_C). */
#ifndef HITC_H
#define HITC_H
typedef unsigned char uint8_t;
typedef char int8_t;            /* (char ya es con signo en HI-TECH) */
typedef unsigned int uint16_t;
typedef int int16_t;
typedef unsigned long uint32_t;
typedef long int32_t;
#define const                   /* HI-TECH 3.09 no conoce const */
#define __sdcccall(x)
#define __naked
#define brk cpmbrk                       /* (brk ya es de la biblioteca de HI-TECH) */
extern char _Hbss[];             /* el fin de bss (lo pone LINK): lo libre */
#define heap _Hbss
void *memmove(void *d, void *s, uint16_t n);   /* en cpm.c */
#endif
