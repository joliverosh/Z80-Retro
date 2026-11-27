/* c/ejemplos/cksum.c - cksum-milla: el CRC-32 de POSIX (cksum) de la entrada.
 * Proyecto Semilla, version 1. */
/* cksum-milla: CRC-32 de POSIX sobre stdin.  Imprime "CRC bytes", igual que
   `cksum` sin nombre de archivo.  Usa enteros de 32 bits (clase 32). */
/* (aqui iba "#pragma clase 32" de Semilla: el cpp de HI-TECH C no acepta
   #pragma, ni dentro de un #if; SDCC no lo necesita) */
#ifndef HI_TECH_C                /* (con HI-TECH C, lo de filtro.h) */
#include <stdio.h>
#endif

unsigned long tabla[256];

void hazTabla(void)
{
    unsigned long c;
    int i, k;
    for (i = 0; i < 256; i++) {
        c = (unsigned long)i << 24;
        for (k = 0; k < 8; k++) {
            if (c >> 31) c = (c << 1) ^ 0x04C11DB7;
            else c = c << 1;
        }
        tabla[i] = c;
    }
}

int main(void)
{
    unsigned long crc, n, len;
    int c;
    hazTabla();
    crc = 0;
    n = 0;
    while ((c = getchar()) != -1) {
        crc = (crc << 8) ^ tabla[((crc >> 24) ^ c) & 255];
        n++;
    }
    len = n;
    while (n) {
        crc = (crc << 8) ^ tabla[((crc >> 24) ^ (n & 255)) & 255];
        n = n >> 8;
    }
    printf("%lu %lu\n", ~crc, len);   /* (%lu: en SDCC el int es de 16 bits) */
    return 0;
}
