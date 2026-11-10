/* crc32.h - CRC-32 de ZIP (polinomio EDB88320), con tabla de 1 KB */
uint32_t crctab[256];
static void crcinit(void)
{
    uint16_t i; uint8_t k;
    for (i = 0; i < 256; i++) {
        uint32_t c = i;
        for (k = 0; k < 8; k++) c = c & 1 ? (c >> 1) ^ 0xEDB88320UL : c >> 1;
        crctab[i] = c;
    }
}
/* crc = crc32 de un trozo, empezando con 0xFFFFFFFF y terminando con ~
   (crc32_a.s; el programa que use esto lleva ese .s al enlazar) */
uint32_t crcbuf(uint32_t c, const uint8_t *p, uint16_t n) __sdcccall(0);
