/* dskdir.h - el directorio de un disco CP/M entero en memoria, por la BIOS
   (para CHKDIR y UNERA). dd_open(unidad) lo lee a dd_dir; dd_write() lo
   escribe. (C) OLIVEROS 2026 */
static uint16_t dd_spt, dd_dsm, dd_drm, dd_off, dd_al, dd_first;
static uint8_t dd_bsh, dd_blm, dd_exm, dd_drv, dd_big;
static uint8_t dd_dir[512 * 32];         /* hasta 512 entradas */
static uint16_t dd_nrec;                 /* registros del directorio */

static uint8_t dd_io(uint8_t wr, uint16_t r, uint8_t *b)
{
    r += dd_off * dd_spt;
    biosc(9, dd_drv, 0);
    biosc(10, r / dd_spt, 0);
    biosc(11, r % dd_spt, 0);
    biosc(12, (uint16_t)b, 0);
    biosc(wr ? 14 : 13, 1, 0);
    return biosa;
}
/* 0 bien; 1 no existe, 2 directorio muy grande, 3 error al leer */
static uint8_t dd_open(uint8_t drv)
{
    uint16_t dph, dpb, i;
    uint8_t *p;
    dd_drv = drv;
    bdos(48, 0);                         /* lo que esta en la cache, al disco (BDOS 48, ZOS y CP/M 3) */
    dph = biosc(9, drv, 0);
    if (!dph) return 1;
    dpb = *(uint16_t *)(dph + 10);
    p = (uint8_t *)dpb;
    dd_spt = p[0] | (p[1] << 8);
    dd_bsh = p[2]; dd_blm = p[3]; dd_exm = p[4];
    dd_dsm = p[5] | (p[6] << 8);
    dd_drm = p[7] | (p[8] << 8);
    dd_al = (p[9] << 8) | p[10];
    dd_off = p[13] | (p[14] << 8);
    dd_big = dd_dsm > 255;
    if (dd_drm >= 512) return 2;
    dd_nrec = (dd_drm + 1) / 4;
    for (dd_first = 0, i = 0x8000; i && (dd_al & i); i >>= 1) dd_first++;   /* bloques del directorio */
    for (i = 0; i < dd_nrec; i++) if (dd_io(0, i, dd_dir + i * 128)) return 3;
    return 0;
}
static uint8_t dd_write(void)
{
    uint16_t i;
    for (i = 0; i < dd_nrec; i++) if (dd_io(1, i, dd_dir + i * 128)) return 1;
    bdos(37, (uint16_t)1 << dd_drv);    /* que la BDOS vuelva a leer el directorio */
    return 0;
}
/* el bloque k (0-15 u 0-7) de la entrada e */
static uint16_t dd_blk(uint8_t *e, uint8_t k)
{
    return dd_big ? e[16 + 2 * k] | (e[17 + 2 * k] << 8) : e[16 + k];
}
static uint8_t dd_nblk(void) { return dd_big ? 8 : 16; }
/* el numero de extension de la entrada (con s2) */
static uint16_t dd_ext(uint8_t *e) { return (e[12] & 31) | ((uint16_t)(e[14] & 63) << 5); }
/* "NOMBRE.EXT" de la entrada */
static void dd_name(uint8_t *e, char *o)
{
    uint8_t i;
    for (i = 1; i < 9 && (e[i] & 0x7F) != ' '; i++) *o++ = e[i] & 0x7F;
    if ((e[9] & 0x7F) != ' ') {
        *o++ = '.';
        for (i = 9; i < 12 && (e[i] & 0x7F) != ' '; i++) *o++ = e[i] & 0x7F;
    }
    *o = 0;
}
/* bits de los bloques */
static uint8_t dd_map[2048];
static uint8_t dd_test(uint16_t b) { return dd_map[b >> 3] & (1 << (b & 7)); }
static void dd_set(uint16_t b) { dd_map[b >> 3] |= 1 << (b & 7); }
