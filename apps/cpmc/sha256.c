/* SHA256 - la suma SHA-256 de archivos, como sha256sum
   SHA256 archivo...   (admite * y ?)
   SHA256 -T archivo   texto: solo hasta el primer ^Z
   CP/M guarda los archivos en registros de 128 bytes: sin -T entra el archivo
   entero, con el relleno del ultimo registro. */
#include <string.h>
#include "cpm.h"
const uint32_t K[64] = {
0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
uint32_t H[8], W[64];
void shacomp(void);
static uint8_t blk[64];
static uint32_t total;
static NAME12 nm[64];
static FCB f;
static uint8_t rec[128];

static void compress(uint8_t *p)
{
    uint8_t i;
    for (i = 0; i < 16; i++, p += 4)
        W[i] = ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint16_t)p[2] << 8) | p[3];
    shacomp();                   /* sha256_a.s */
}
static void init(void)
{
    static const uint32_t H0[8] = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
                                   0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
    memcpy(H, H0, sizeof H);
    total = 0;
}
/* el final: lo que queda (n < 128 bytes en p), el 80h, ceros y la longitud */
static void fin(uint8_t *p, uint8_t n)
{
    uint32_t bits;
    uint8_t i;
    total += n;
    bits = total << 3;
    if (n >= 64) { compress(p); p += 64; n -= 64; }
    memcpy(blk, p, n);
    blk[n++] = 0x80;
    if (n > 56) { memset(blk + n, 0, 64 - n); compress(blk); n = 0; }
    memset(blk + n, 0, 64 - n);
    blk[59] = total >> 29;
    for (i = 0; i < 4; i++) blk[63 - i] = bits >> (i * 8);
    compress(blk);
}
void main(void)
{
    char *p = args(), *a, s[16];
    uint8_t text = 0;
    if ((a = nextarg(&p)) && !strcmp(a, "-T")) { text = 1; a = nextarg(&p); }
    if (!a) { pstr("Usage: SHA256 [-T] file...   (-T: text, up to the first ^Z)\n"); return; }
    do {
        uint8_t n = glob(a, nm, 64), i, j;
        if (!n) { pf("%s: not found\n", a); continue; }
        for (i = 0; i < n; i++) {
            uint8_t k = 0;
            nm2fcb(nm[i], &f);
            fname(&f, s);
            if (fopen(&f)) continue;
            init();
            while (!fread(&f, rec)) {
                k = 128;
                if (text) {
                    uint8_t *z = memchr(rec, 0x1A, 128);
                    if (z) { k = z - rec; break; }
                }
                compress(rec); compress(rec + 64);
                total += 128; k = 0;
                if (brk()) return;
            }
            fclose(&f);
            fin(rec, k);
            for (j = 0; j < 8; j++) pf("%08lx", H[j]);
            pf("  %s\n", s + (s[1] == ':' ? 2 : 0));
        }
    } while ((a = nextarg(&p)));
}
